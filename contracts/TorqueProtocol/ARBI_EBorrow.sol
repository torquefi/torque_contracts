// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

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

contract ARBI_EBorrow  is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable{
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
        uint relayBorrowed;
        uint borrowed;
        uint supplied;

        uint accruedInterest;
        uint borrowTime;
    }
    struct BorrowSnapshoot {
        uint amount;
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

        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);
        return amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);
    }

    function borrow(uint borrowAmount, uint usgBorrowAmount) public payable nonReentrant(){
        uint supplyAmount = msg.value;
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint maxBorrow = (supplyAmount.add(userBorrowInfo.supplied)).mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);

        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= borrowAmount, "borrow cap exceed");

        (uint mintable, bool canMint) = IUsgEngine(engine).getMintableUSG(baseAsset, address(this), borrowAmount);
        require(canMint, 'user cant mint more usg');


        if(userBorrowInfo.borrowed > 0) {
            uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
            userBorrowInfo.accruedInterest += accruedInterest;
        }

        require(mintable > usgBorrowAmount, "exceed borrow amount");
        
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(borrowAmount);
        userBorrowInfo.supplied = userBorrowInfo.supplied.add(supplyAmount);
        userBorrowInfo.borrowTime = block.timestamp;
        userBorrowInfo.relayBorrowed += usgBorrowAmount;

        bytes32[] memory actions = new bytes32[](2);

        actions[0] = ACTION_SUPPLY_ETH;
        actions[1] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), supplyAmount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmount);
        callData[1] = withdrawAssetCalldata;

        IARBBulker(bulker).invoke{value: supplyAmount}(actions, callData);

        ERC20(baseAsset).approve(address(engine), borrowAmount);
        IUsgEngine(engine).depositCollateralAndMintUsg{value:0}(baseAsset, borrowAmount, usgBorrowAmount);
        require(ERC20(usg).transfer(msg.sender, usgBorrowAmount), "transfer token fail");
    }

    function withdraw(uint withdrawAmount) public nonReentrant(){
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        require(userBorrowInfo.supplied > 0, "User does not have debt");
        
        if(userBorrowInfo.borrowed > 0) {
            uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
            userBorrowInfo.accruedInterest += accruedInterest;
        }

        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);

        uint minRequireSupplyAmount = userBorrowInfo.borrowed.add(userBorrowInfo.accruedInterest).mul(SCALE).mul(PRICE_MANTISA).div(price).div(uint(info.borrowCollateralFactor).sub(WITHDRAW_OFFSET));
        uint withdrawableAmount = userBorrowInfo.supplied - minRequireSupplyAmount;

        require(withdrawAmount < withdrawableAmount, "Exceed asset supply");

        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAmount);
        userBorrowInfo.borrowTime = block.timestamp;
        
        bytes32[] memory actions = new bytes32[](1);

        actions[0] = ACTION_WITHDRAW_ETH;

        bytes[] memory callData = new bytes[](1);

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), withdrawAmount);
        callData[0] = withdrawAssetCalldata;

        IARBBulker(bulker).invoke(actions, callData);

        (bool success, ) = msg.sender.call{ value: withdrawAmount }("");
        require(success, "transfer eth failed");
    } 

    function repay(uint usgRepayAmount) public nonReentrant(){

        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        require(userBorrowInfo.relayBorrowed >= usgRepayAmount, "exceed current borrowed amount");
        require(ERC20(usg).transferFrom(msg.sender,address(this), usgRepayAmount), "transfer asset fail");

        uint withdrawUsdcAmountFromEngine = IUsgEngine(engine).getBurnableUSG(baseAsset, msg.sender, usgRepayAmount);

        ERC20(usg).approve(address(engine), usgRepayAmount);
        IUsgEngine(usg).redeemCollateralForUsg(baseAsset, withdrawUsdcAmountFromEngine, usgRepayAmount);

        uint withdrawAssetAmount = userBorrowInfo.supplied.mul(withdrawUsdcAmountFromEngine).div(userBorrowInfo.borrowed);
        uint extraInterest = userBorrowInfo.accruedInterest.mul(withdrawUsdcAmountFromEngine).div(userBorrowInfo.borrowed);

        uint interest = calculateInterest(withdrawUsdcAmountFromEngine, userBorrowInfo.borrowTime) + extraInterest;

        uint repayUsdcAmount = withdrawUsdcAmountFromEngine + interest;

        bytes32[] memory actions = new bytes32[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ETH;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), baseAsset, repayUsdcAmount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), withdrawAssetAmount);
        callData[1] = withdrawAssetCalldata;

        ERC20(baseAsset).approve(comet, repayUsdcAmount);
        IARBBulker(bulker).invoke(actions, callData);

        userBorrowInfo.relayBorrowed = userBorrowInfo.borrowed.sub(usgRepayAmount);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.sub(withdrawUsdcAmountFromEngine);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAssetAmount);
        userBorrowInfo.accruedInterest = userBorrowInfo.accruedInterest.sub(extraInterest);


        (bool success, ) = msg.sender.call{ value: withdrawAssetAmount }("");
        require(success, "transfer eth failed");
    }
    
    function borrowBalanceOf(address user) public view returns (uint) {
        
        BorrowInfo storage userBorrowInfo = borrowInfoMap[user];
        if(userBorrowInfo.borrowed == 0) {
            return 0;
        }

        uint borrowAmount = userBorrowInfo.borrowed;
        uint extraInterest = userBorrowInfo.accruedInterest.mul(borrowAmount).div(userBorrowInfo.borrowed);

        uint interest = calculateInterest(borrowAmount, userBorrowInfo.borrowTime) + extraInterest;

        return borrowAmount + interest;
    }

    function partialBorrowBalanceOf(address user, uint borrowAmount) public view returns (uint) {
        
        BorrowInfo storage userBorrowInfo = borrowInfoMap[user];
        if(userBorrowInfo.borrowed == 0) {
            return 0;
        }

        uint extraInterest = userBorrowInfo.accruedInterest.mul(borrowAmount).div(userBorrowInfo.borrowed);

        uint interest = calculateInterest(borrowAmount, userBorrowInfo.borrowTime) + extraInterest;

        return borrowAmount + interest;
    }

    function calculateInterest(uint borrowAmount, uint borrowTime) public view returns (uint) {
        IComet icomet = IComet(comet);
        uint totalSecond = block.timestamp - borrowTime;
        return borrowAmount.mul(icomet.getBorrowRate(icomet.getUtilization())).mul(totalSecond).div(1e18);
    }

    receive() external payable {
    }
}