// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "../../CompoundBase/IWETH9.sol";
import "../../CompoundBase/bulkers/IARBBulker.sol";
import "../../CompoundBase/IComet.sol";

import "./interfaces/ICometRewards.sol";
import "./interfaces/IUSDEngine.sol";

import "./RewardUtil.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract ETHBorrow is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable{
    using SafeMath for uint256;

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
    uint constant USD_DECIMAL_OFFSET = 1e12;

    struct BorrowInfo {
        address user;
        uint baseBorrowed;
        uint borrowed;
        uint supplied;

        uint borrowTime;
        uint reward;
    }

    mapping(address => BorrowInfo) public borrowInfoMap;
    event UserBorrow(address user, address collateralAddress, uint amount);
    event UserRepay(address user, address collateralAddress, uint repayAmount, uint claimAmount);
    
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(address _comet, address _cometReward, address _asset, address _baseAsset, address _bulker, address _engine, address _usd, address _treasury, address _rewardUtil, address _rewardToken) public initializer {
        comet = _comet;
        cometReward = _cometReward;
        asset = _asset;
        baseAsset = _baseAsset;
        bulker = _bulker;
        engine = _engine;
        usd = _usd;
        treasury = _treasury;
        rewardUtil = _rewardUtil;
        rewardToken = _rewardToken;
        IComet(comet).allow(_bulker, true);
        claimPeriod = 86400;
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

    function setUsdEngine(address _newEngine) public onlyOwner{
        engine = _newEngine;
    }

    function setUsd(address _usd) public onlyOwner{
        usd = _usd;
    }
// End test

    function getBorrowable(uint amount) public view returns (uint){
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);
        return amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);
    }

    function borrow(uint borrowAmount, uint usdBorrowAmount) public payable nonReentrant(){
        (uint mintable, bool canMint) = IUSDEngine(engine).getMintableUSD(baseAsset, address(this), borrowAmount);
        require(canMint, 'User can not mint more USD');
        require(mintable > usdBorrowAmount, "Exceeds borrow amount");

        uint supplyAmount = msg.value;
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint maxBorrow = (supplyAmount.add(userBorrowInfo.supplied)).mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);

        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= borrowAmount, "Borrow cap exceeded");

        uint accruedInterest = 0;
        uint reward = 0 ;
        if(userBorrowInfo.borrowed > 0) {
            accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
            reward = RewardUtil(rewardUtil).calculateReward(userBorrowInfo.baseBorrowed, userBorrowInfo.borrowTime);
        }

        userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.add(borrowAmount);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(borrowAmount).add(accruedInterest);
        if(reward > 0) {
            userBorrowInfo.reward = userBorrowInfo.reward.add(reward);
        }
        userBorrowInfo.supplied = userBorrowInfo.supplied.add(supplyAmount);
        userBorrowInfo.borrowTime = block.timestamp;

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

        uint usdBefore = ERC20(usd).balanceOf(address(this));

        IUSDEngine(engine).depositCollateralAndMintUsd{value:0}(baseAsset, borrowAmount, usdBorrowAmount);

        uint exepectedUsd = usdBefore.add(usdBorrowAmount);
        require(exepectedUsd == ERC20(usd).balanceOf(address(this)), "Invalid amount");

        require(ERC20(usd).transfer(msg.sender, usdBorrowAmount), "Transfer token failed");
    }

    function withdraw(uint withdrawAmount) public nonReentrant(){
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

        uint minRequireSupplyAmount = userBorrowInfo.borrowed.mul(SCALE).mul(PRICE_MANTISA).div(price).div(uint(info.borrowCollateralFactor).sub(WITHDRAW_OFFSET));
        uint withdrawableAmount = userBorrowInfo.supplied - minRequireSupplyAmount;

        require(withdrawAmount < withdrawableAmount, "Exceeds asset supply");

        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAmount);
        
        bytes32[] memory actions = new bytes32[](1);

        actions[0] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](1);

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, withdrawAmount);
        callData[0] = withdrawAssetCalldata;

        IARBBulker(bulker).invoke(actions, callData);

        ERC20(asset).transfer(msg.sender, withdrawAmount);
    } 


    function repay(uint usdRepayAmount) public nonReentrant(){

        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];

        (uint withdrawUsdcAmountFromEngine, bool burnable) = IUSDEngine(engine).getBurnableUSD(baseAsset, address(this), usdRepayAmount);
        require(burnable, "Not burnable");
        require(userBorrowInfo.borrowed >= withdrawUsdcAmountFromEngine, "Exceeds current borrowed amount");
        require(ERC20(usd).transferFrom(msg.sender,address(this), usdRepayAmount), "Transfer asset failed");

        uint baseAssetBalanceBefore = ERC20(baseAsset).balanceOf(address(this));

        ERC20(usd).approve(address(engine), usdRepayAmount);

        IUSDEngine(engine).redeemCollateralForUsd(baseAsset, withdrawUsdcAmountFromEngine, usdRepayAmount);

        uint baseAssetBalanceExpected = baseAssetBalanceBefore.add(withdrawUsdcAmountFromEngine);
        require(baseAssetBalanceExpected == ERC20(baseAsset).balanceOf(address(this)), "Invalid USDC claim to Engine");

        uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
        uint reward = RewardUtil(rewardUtil).calculateReward(userBorrowInfo.baseBorrowed, userBorrowInfo.borrowTime) + userBorrowInfo.reward;
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(accruedInterest);

        uint withdrawAssetAmount = userBorrowInfo.supplied.mul(withdrawUsdcAmountFromEngine).div(userBorrowInfo.borrowed);

        uint repayUsdcAmount = withdrawUsdcAmountFromEngine;

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

        if(userBorrowInfo.baseBorrowed < withdrawUsdcAmountFromEngine) {
            userBorrowInfo.baseBorrowed = 0;
        } else {
            userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.sub(withdrawUsdcAmountFromEngine);
        }
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.sub(withdrawUsdcAmountFromEngine);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAssetAmount);
        userBorrowInfo.borrowTime = block.timestamp;
        userBorrowInfo.reward = 0;
        if(reward > 0) {
            require(ERC20(rewardToken).balanceOf(address(this)) >= reward, "Insuffient balance to pay reward");
            require(ERC20(rewardToken).transfer(msg.sender, reward), "Transfer reward failed");
        }


        (bool success, ) = msg.sender.call{ value: withdrawAssetAmount }("");
        require(success, "Transfer ETH failed");
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

    function claimCReward() public onlyOwner{
        require(lastClaimCometTime + claimPeriod < block.timestamp, "already claim");
        require(treasury != address(0), "invalid treasury");
        lastClaimCometTime = block.timestamp;
        ICometRewards(cometReward).claim(comet, treasury, true);
    }

    receive() external payable {
    }

    
}