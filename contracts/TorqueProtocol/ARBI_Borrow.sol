// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "../CompoundBase/IWETH9.sol";
import "../CompoundBase/bulkers/IARBBulker.sol";
import "../CompoundBase/IComet.sol";
import "./Torque/IUsgEngine.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract ARBI_Borrow  is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable{
    using SafeMath for uint256;

    address public bulker;
    address public asset;
    address public baseAsset;
    address public comet;
    address public engine;
    address public usg;
        /// @notice The action for supplying an asset to Comet
    bytes32 public constant ACTION_SUPPLY_ASSET = "ACTION_SUPPLY_ASSET";

    /// @notice The action for supplying a native asset (e.g. ETH on Ethereum mainnet) to Comet
    bytes32 public constant ACTION_SUPPLY_ETH = "ACTION_SUPPLY_NATIVE_TOKEN";

    /// @notice The action for transferring an asset within Comet
    bytes32 public constant ACTION_TRANSFER_ASSET = "ACTION_TRANSFER_ASSET";

    /// @notice The action for withdrawing an asset from Comet
    bytes32 public constant ACTION_WITHDRAW_ASSET = "ACTION_WITHDRAW_ASSET";

    /// @notice The action for withdrawing a native asset from Comet
    bytes32 public constant ACTION_WITHDRAW_ETH = "ACTION_WITHDRAW_NATIVE_TOKEN";

    /// @notice The action for claiming rewards from the Comet rewards contract
    bytes32 public constant ACTION_CLAIM_REWARD = "ACTION_CLAIM_REWARD";
    uint constant BASE_ASSET_MANTISA = 1e6;
    uint constant PRICE_MANTISA = 1e2;
    uint constant SCALE = 1e18;
    uint constant WITHDRAW_OFFSET = 1e2;
    uint constant USG_DECIMAL_OFFSET = 1e12;

    struct BorrowInfo {
        address user;
        uint borrowed;
        uint supplied;

        uint borrowTime;
    }

    mapping(address => BorrowInfo) public borrowInfoMap;
    event UserBorrow(address user, address collateralAddress, uint amount);
    event UserRepay(address user, address collateralAddress, uint repayAmount, uint claimAmount);
    
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(address _comet, address _asset, address _baseAsset, address _bulker, address _engine, address _usg) public initializer {
        comet = _comet;
        asset = _asset;
        baseAsset = _baseAsset;
        bulker = _bulker;
        engine = _engine;
        usg = _usg;
        IComet(comet).allow(_bulker, true);
        __Ownable_init();
        __ReentrancyGuard_init();
    }


// Test only
    function setBulker(address _bulker) public onlyOwner{
        bulker = _bulker;
    }
    function setasset(address _asset) public onlyOwner{
        asset = payable(_asset);
    }
    
    function setComet(address _comet) public onlyOwner{
        comet = _comet;
    }
    function allow(address _asset, address spender, uint amount) public onlyOwner{
        ERC20(_asset).approve(spender, amount);
    }
    function setAllowTo(address manager, bool _allow) public onlyOwner{
        IComet(comet).allow(manager, _allow);
    }
// End test

    function getBorrowable(uint amount) public view returns (uint){
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        return amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);
    }

    function borrow(uint supplyAmount, uint borrowAmount, uint usgBorrowAmount) public nonReentrant(){
         (uint mintable, bool canMint) = IUsgEngine(engine).getMintableUSG(baseAsset, address(this), borrowAmount);
        require(canMint, 'user cant mint more usg');
        require(mintable > usgBorrowAmount, "exceed borrow amount");
        IComet icomet = IComet(comet);


        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);
        
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint maxBorrow = (supplyAmount.add(userBorrowInfo.supplied)).mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);

        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= borrowAmount, "borrow cap exceed");
        require(ERC20(asset).transferFrom(msg.sender, address(this), supplyAmount), "transfer asset fail");

         uint accruedInterest = 0;
        if(userBorrowInfo.borrowed > 0) {
            accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
        }

        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(borrowAmount).add(accruedInterest);
        userBorrowInfo.supplied = userBorrowInfo.supplied.add(supplyAmount);
        userBorrowInfo.borrowTime = block.timestamp;

        bytes32[] memory actions = new bytes32[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, supplyAmount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmount);
        callData[1] = withdrawAssetCalldata;

        ERC20(asset).approve(comet, supplyAmount);
        IARBBulker(bulker).invoke(actions, callData);
	    ERC20(baseAsset).approve(address(engine), borrowAmount);

        uint usgBefore = ERC20(usg).balanceOf(address(this));

        IUsgEngine(engine).depositCollateralAndMintUsg(baseAsset, borrowAmount, usgBorrowAmount);

        uint exepectedUsg = usgBefore.add(usgBorrowAmount);
        require(exepectedUsg == ERC20(usg).balanceOf(address(this)), "invalid claim borrow usg amount");

        require(ERC20(usg).transfer(msg.sender, usgBorrowAmount), "transfer token fail");
    }

    

    function withdraw(uint withdrawAmount) public nonReentrant(){
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        require(userBorrowInfo.supplied > 0, "User does not have asseet");
        
        if(userBorrowInfo.borrowed > 0) {
            uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
            userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(accruedInterest);
            userBorrowInfo.borrowTime = block.timestamp;
        }

        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);

        uint minRequireSupplyAmount = userBorrowInfo.borrowed.mul(SCALE).mul(PRICE_MANTISA).div(price).div(uint(info.borrowCollateralFactor).sub(WITHDRAW_OFFSET));
        uint withdrawableAmount = userBorrowInfo.supplied - minRequireSupplyAmount;

        require(withdrawAmount < withdrawableAmount, "Exceed asset supply");

        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAmount);
        
        bytes32[] memory actions = new bytes32[](1);

        actions[0] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](1);

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, withdrawAmount);
        callData[0] = withdrawAssetCalldata;

        IARBBulker(bulker).invoke(actions, callData);

        ERC20(asset).transfer(msg.sender, withdrawAmount);
    } 

    function repay(uint usgRepayAmount) public nonReentrant(){
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];

        uint withdrawUsdcAmountFromEngine = IUsgEngine(engine).getBurnableUSG(baseAsset, address(this), usgRepayAmount);
        require(userBorrowInfo.borrowed >= withdrawUsdcAmountFromEngine, "exceed current borrowed amount");
        require(ERC20(usg).transferFrom(msg.sender,address(this), usgRepayAmount), "transfer asset fail");


        uint baseAssetBalanceBefore = ERC20(baseAsset).balanceOf(address(this));

        ERC20(usg).approve(address(engine), usgRepayAmount);
        IUsgEngine(engine).redeemCollateralForUsg(baseAsset, withdrawUsdcAmountFromEngine, usgRepayAmount);

        uint baseAssetBalanceExpected = baseAssetBalanceBefore.add(withdrawUsdcAmountFromEngine);
        require(baseAssetBalanceExpected == ERC20(baseAsset).balanceOf(address(this)), "invalid usdc claim from engine");



        uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(accruedInterest);

        uint withdrawAssetAmount = userBorrowInfo.supplied.mul(withdrawUsdcAmountFromEngine).div(userBorrowInfo.borrowed);

        uint repayUsdcAmount = withdrawUsdcAmountFromEngine;

        bytes32[] memory actions = new bytes32[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), baseAsset, repayUsdcAmount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, withdrawAssetAmount);
        callData[1] = withdrawAssetCalldata;

        ERC20(baseAsset).approve(comet, repayUsdcAmount);
        IARBBulker(bulker).invoke(actions, callData);

        userBorrowInfo.borrowed = userBorrowInfo.borrowed.sub(withdrawUsdcAmountFromEngine);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAssetAmount);
        userBorrowInfo.borrowTime = block.timestamp;

        require(ERC20(asset).transfer(msg.sender, withdrawAssetAmount), "transfer asset claim from compound fail");
    }
    function borrowBalanceOf(address user) public view returns (uint) {
        
        BorrowInfo storage userBorrowInfo = borrowInfoMap[user];
        if(userBorrowInfo.borrowed == 0) {
            return 0;
        }

        uint borrowAmount = userBorrowInfo.borrowed;
        uint interest = calculateInterest(borrowAmount, userBorrowInfo.borrowTime);

        return borrowAmount + interest;
    }

    function calculateInterest(uint borrowAmount, uint borrowTime) public view returns (uint) {
        IComet icomet = IComet(comet);
        uint totalSecond = block.timestamp - borrowTime;
        return borrowAmount.mul(icomet.getBorrowRate(icomet.getUtilization())).mul(totalSecond).div(1e18);
    }
}