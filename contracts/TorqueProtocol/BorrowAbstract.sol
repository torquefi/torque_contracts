// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./interfaces/IComet.sol";
import "./interfaces/IWETH9.sol";
import "./interfaces/IBulker.sol";
import "./interfaces/ICometRewards.sol";
import "./interfaces/ITUSDEngine.sol";
import "./interfaces/ITokenDecimals.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract BorrowAbstract is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    address public comet;
    address public cometReward;
    address public asset;
    address public baseAsset;
    address public bulker;
    address public engine;
    address public tusd;
    address public treasury;
    uint public claimPeriod;
    uint public repaySlippage;
    uint public totalBorrow;
    uint public totalSupplied;
    uint public lastClaimCometTime;

    uint256 public decimalAdjust = 1000000000000;
    
    bytes32 public constant ACTION_SUPPLY_ASSET = "ACTION_SUPPLY_ASSET";
    bytes32 public constant ACTION_SUPPLY_ETH = "ACTION_SUPPLY_NATIVE_TOKEN";
    bytes32 public constant ACTION_TRANSFER_ASSET = "ACTION_TRANSFER_ASSET";
    bytes32 public constant ACTION_WITHDRAW_ASSET = "ACTION_WITHDRAW_ASSET";
    bytes32 public constant ACTION_WITHDRAW_ETH = "ACTION_WITHDRAW_NATIVE_TOKEN";
    bytes32 public constant ACTION_CLAIM_REWARD = "ACTION_CLAIM_REWARD";

    constructor(
        address _initialOwner,
        address _comet, // Compound V3 Address
        address _cometReward, // Address for Claiming Comet Rewards
        address _asset, // Collateral to be staked (WBTC / WETH)
        address _baseAsset, // Borrowing Asset (USDC)
        address _bulker, // Bulker Contract
        address _engine, // Torque USD Engine 
        address _tusd, // TUSD Token
        address _treasury, // Fees Address
        uint _repaySlippage // Slippage %
    ) {
        Ownable.transferOwnership(_initialOwner);
        comet = _comet;
        cometReward = _cometReward;
        asset = _asset;
        baseAsset = _baseAsset;
        bulker = _bulker;
        engine = _engine;
        tusd = _tusd;
        treasury = _treasury;
        IComet(_comet).allow(_bulker, true);
        claimPeriod = 86400; // 1 day in seconds
        repaySlippage = _repaySlippage;
    }
    
    uint constant BASE_ASSET_MANTISA = 1e6;
    uint constant PRICE_MANTISA = 1e2;
    uint constant SCALE = 1e18;
    uint constant WITHDRAW_OFFSET = 1e2;
    uint constant TUSD_DECIMAL_OFFSET = 1e12;
    uint constant PRICE_SCALE = 1e8;

    struct BorrowInfo {
        address user; // User Address
        uint baseBorrowed; // TUSD borrowed 
        uint borrowed; // USDC Borrowed 
        uint supplied; // WBTC Supplied
        uint borrowTime; // Borrow time
    }

    mapping(address => BorrowInfo) public borrowInfoMap;

    event UserBorrow(address user, address collateralAddress, uint amount);
    event UserRepay(address user, address collateralAddress, uint repayAmount, uint claimAmount);

    function getCollateralFactor() public view returns (uint){
        IComet icomet = IComet(comet);
        IComet.AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        return info.borrowCollateralFactor;
    }

    function getUserBorrowable(address _user) public view returns (uint){
        BorrowInfo storage userBorrowInfo = borrowInfoMap[_user];
        if(userBorrowInfo.supplied == 0) {
            return 0; 
        }
        uint assetSupplyAmount = userBorrowInfo.supplied;
        uint maxUsdc = getBorrowableUsdc(assetSupplyAmount);
        uint maxTusd = getBorrowableV2(maxUsdc, _user); 
        return maxTusd;
    }

    function getBorrowableV2(uint maxUSDC, address _user) public view returns (uint){
        BorrowInfo storage userBorrowInfo = borrowInfoMap[_user];
        uint mintable = getMintableToken(maxUSDC, userBorrowInfo.baseBorrowed, 0);
        return mintable;
    }
    
    function getBorrowableUsdc(uint supplyAmount) public view returns (uint) {
        IComet icomet = IComet(comet);
        IComet.AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint assetDecimal = ITokenDecimals(asset).decimals();
        return supplyAmount
            .mul(info.borrowCollateralFactor)
            .mul(icomet.getPrice(info.priceFeed))
            .div(PRICE_MANTISA)
            .div(10**assetDecimal)
            .div(SCALE);
    }

    function withdraw(uint withdrawAmount) public nonReentrant {
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        require(userBorrowInfo.supplied > 0, "User does not have asset");
        if (userBorrowInfo.borrowed > 0) {
            uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
            userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(accruedInterest);
            userBorrowInfo.borrowTime = block.timestamp;
        }
        IComet icomet = IComet(comet);
        IComet.AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);
        uint assetDecimal = ITokenDecimals(asset).decimals();
        uint minRequireSupplyAmount = userBorrowInfo.borrowed.mul(SCALE).mul(10**assetDecimal).mul(PRICE_MANTISA).div(price).div(uint(info.borrowCollateralFactor).sub(WITHDRAW_OFFSET));
        uint withdrawableAmount = userBorrowInfo.supplied - minRequireSupplyAmount;
        require(withdrawAmount <= withdrawableAmount, "Exceeds asset supply");
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAmount);
        bytes[] memory callData = new bytes[](1);
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, withdrawAmount);
        callData[0] = withdrawAssetCalldata;
        IBulker(bulker).invoke(buildWithdraw(), callData);
        IERC20(asset).transfer(msg.sender, withdrawAmount);
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

    function getApr() public view returns (uint) {
        IComet icomet = IComet(comet);
        uint borowRate = icomet.getBorrowRate(icomet.getUtilization());
        return borowRate.mul(31536000);
    }

    function claimCReward() public onlyOwner{
        require(lastClaimCometTime + claimPeriod < block.timestamp, "Already claimed");
        require(treasury != address(0), "Invalid treasury");
        lastClaimCometTime = block.timestamp;
        ICometRewards(cometReward).claim(comet, treasury, true);
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

    function getMintableToken(uint256 _usdcSupply, uint256 _mintedTUSD, uint256 _toMintTUSD) public view returns (uint256) {
        uint256 LIQUIDATION_THRESHOLD = ITUSDEngine(engine).getLiquidationThreshold();
        uint256 PRECISION = ITUSDEngine(engine).getPrecision();
        uint256 LIQUIDATION_PRECISION = ITUSDEngine(engine).getLiquidationPrecision();
        uint256 MIN_HEALTH_FACTOR = ITUSDEngine(engine).getMinHealthFactor();
        uint256 totalMintable = _usdcSupply*LIQUIDATION_THRESHOLD/LIQUIDATION_PRECISION;
        totalMintable = totalMintable*PRECISION/MIN_HEALTH_FACTOR;
        totalMintable *= decimalAdjust;
        require(totalMintable >= _mintedTUSD + _toMintTUSD, "User can not mint more TUSD");
        totalMintable -= _mintedTUSD;
        return totalMintable;
    }

    function getBurnableToken(uint256 _tUsdRepayAmount, uint256 tUSDBorrowAmount, uint256 _usdcToBePayed) public view returns (uint256) {
        uint256 LIQUIDATION_THRESHOLD = ITUSDEngine(engine).getLiquidationThreshold();
        uint256 PRECISION = ITUSDEngine(engine).getPrecision();
        uint256 LIQUIDATION_PRECISION = ITUSDEngine(engine).getLiquidationPrecision();
        uint256 MIN_HEALTH_FACTOR = ITUSDEngine(engine).getMinHealthFactor();
        require(tUSDBorrowAmount >= _tUsdRepayAmount, "You have not minted enough TUSD");
        tUSDBorrowAmount -= _tUsdRepayAmount;
        if(tUSDBorrowAmount == 0){
            return _usdcToBePayed;
        }
        else{
            uint256 totalWithdrawableCollateral = tUSDBorrowAmount*LIQUIDATION_PRECISION/LIQUIDATION_THRESHOLD;
            totalWithdrawableCollateral = totalWithdrawableCollateral*MIN_HEALTH_FACTOR/PRECISION;
            totalWithdrawableCollateral /= decimalAdjust;
            require(totalWithdrawableCollateral <= _usdcToBePayed, "User cannot withdraw more collateral");
            totalWithdrawableCollateral = _usdcToBePayed - totalWithdrawableCollateral;
            return totalWithdrawableCollateral;
        }
    }
    
    receive() external payable {}
}