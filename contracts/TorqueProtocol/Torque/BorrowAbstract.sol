// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|


import "./RewardUtil.sol";
import "../../CompoundBase/IWETH9.sol";
import "../../CompoundBase/bulkers/IBulker.sol";
import "../../CompoundBase/IComet.sol";

import "./interfaces/ICometRewards.sol";
import "./interfaces/ITUSDEngine.sol";


import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

abstract contract BorrowAbstract is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    
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

    address public bulker;
    address public asset;
    address public baseAsset;
    address public comet;
    address public cometReward;
    address public engine;
    address public usd;
    address public rewardUtil;
    address public rewardToken;
    address public treasury;
    uint public lastClaimCometTime;
    uint public claimPeriod;
    
    uint constant BASE_ASSET_MANTISA = 1e6;
    uint constant PRICE_MANTISA = 1e2;
    uint constant SCALE = 1e18;
    uint constant WITHDRAW_OFFSET = 1e2;
    uint constant TUSD_DECIMAL_OFFSET = 1e12;
    uint constant PRICE_SCALE = 1e8;

    struct BorrowInfo {
        address user;
        uint baseBorrowed;
        uint borrowed;
        uint supplied;

        uint borrowTime;
        uint reward;
    }

    mapping(address => BorrowInfo) public borrowInfoMap;
    uint public totalBorrow;
    uint public totalSupplied;
    uint public repaySlippage;
    event UserBorrow(address user, address collateralAddress, uint amount);
    event UserRepay(address user, address collateralAddress, uint repayAmount, uint claimAmount);
    
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(address _comet, address _cometReward, address _asset, address _baseAsset, address _bulker, address _engine, address _tusd, address _treasury, address _rewardUtil, address _rewardToken) public initializer {
        comet = _comet;
        cometReward = _cometReward;
        asset = _asset;
        baseAsset = _baseAsset;
        bulker = _bulker;
        engine = _engine;
        usd = _tusd;
        treasury = _treasury;
        rewardUtil = _rewardUtil;
        rewardToken = _rewardToken;
        IComet(comet).allow(_bulker, true);
        claimPeriod = 86400;
        repaySlippage = 2;
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

    function setTusdEngine(address _newEngine) public onlyOwner{
        engine = _newEngine;
    }

    function setTusd(address _tusd) public onlyOwner{
        usd = _tusd;
    }
    function setRepaySlippage(uint _repaySlippage) public onlyOwner{
        require(_repaySlippage < 100, "invalid value");
        repaySlippage = _repaySlippage;
    }

    function setTotalSupplied(uint _totalSupplied) public onlyOwner{
        totalSupplied = _totalSupplied;
    }
    function setTotalBorrow(uint _totalBorrow) public onlyOwner{
        totalBorrow = _totalBorrow;
    }
    // End test


    //get collatral factor scale up by 1e18
    function getCollateralFactor() public view returns (uint){
        IComet icomet = IComet(comet);
        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        return info.borrowCollateralFactor;
    }

    // Gets max amount that can be borrowed by current user's supplied asset
    function getUserBorrowable(address _user) public view returns (uint){
        BorrowInfo storage userBorrowInfo = borrowInfoMap[_user];
        if(userBorrowInfo.supplied > 0) {
            return 0;
        }
        uint assetSupplyAmount = userBorrowInfo.supplied;
        uint maxUsdc = getBorrowableUsdc(assetSupplyAmount);
        uint maxUsd = getBorrowable(maxUsdc);
        return maxUsd;
    }
    // Gets max amount that can be borrowed by supplied asset
    function getBorrowable(uint supplyAmount) public view returns (uint){
        uint maxBorrow = getBorrowableUsdc(supplyAmount);

        // Get the amount of USD the user is allowed to mint for the given asset
        (uint mintable,) = ITUSDEngine(engine).getMintableTUSD(baseAsset, msg.sender, maxBorrow);
        return mintable;
    }
    // Gets max amount that can be borrowed by supplied asset
    function getBorrowableUsdc(uint supplyAmount) public view returns (uint){
        IComet icomet = IComet(comet);

        // Fetch the asset information and its price.
        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);
        
        uint assetDecimal = ERC20(asset).decimals();
        // Calculate the maximum borrowable amount for the user based on collateral
        uint maxBorrow = supplyAmount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(10**assetDecimal).div(SCALE);
        return maxBorrow;
    }
    // Allows a user to withdraw their collateral
    function withdraw(uint withdrawAmount) public nonReentrant(){
        
        // Fetch a users borrowing information
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        require(userBorrowInfo.supplied > 0, "User does not have asset");
        
        if(userBorrowInfo.borrowed > 0) {
            uint reward = RewardUtil(rewardUtil).calculateReward(userBorrowInfo.baseBorrowed, userBorrowInfo.borrowTime);
            userBorrowInfo.reward = userBorrowInfo.reward.add(reward);
            uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
            userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(accruedInterest);
            userBorrowInfo.borrowTime = block.timestamp;
        }

        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);

        uint assetDecimal = ERC20(asset).decimals();
        uint minRequireSupplyAmount = userBorrowInfo.borrowed.mul(SCALE).mul(10**assetDecimal).mul(PRICE_MANTISA).div(price).div(uint(info.borrowCollateralFactor).sub(WITHDRAW_OFFSET));
        uint withdrawableAmount = userBorrowInfo.supplied - minRequireSupplyAmount;

        require(withdrawAmount < withdrawableAmount, "Exceeds asset supply");

        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAmount);

        bytes[] memory callData = new bytes[](1);

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, withdrawAmount);
        callData[0] = withdrawAssetCalldata;

        IBulker(bulker).invoke(buildWithdraw(), callData);

        ERC20(asset).transfer(msg.sender, withdrawAmount);
        totalSupplied = totalSupplied.sub(withdrawAmount);
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
    //APR scale up by 1e18
    function getApr() public view returns (uint) {
        IComet icomet = IComet(comet);
        uint borowRate = icomet.getBorrowRate(icomet.getUtilization());
        return borowRate.mul(31536000);
    }

    function claimCReward() public onlyOwner{
        require(lastClaimCometTime + claimPeriod < block.timestamp, "already claim");
        require(treasury != address(0), "invalid treasury");
        lastClaimCometTime = block.timestamp;
        ICometRewards(cometReward).claim(comet, treasury, true);
    }

    receive() external payable {
    }

    function buildBorrowAction() pure virtual public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);
        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;
        return actions;
    }
    function buildWithdraw() pure public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](1);
        actions[0] = ACTION_WITHDRAW_ASSET;
        return actions;
    }
    function buildRepay() pure virtual public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;
        return actions;
    }
}
