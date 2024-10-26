// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./interfaces/IComet.sol";
import "./interfaces/IBulker.sol";
import "./interfaces/ICometRewards.sol";
import "./interfaces/ITUSDEngine.sol";
import "./interfaces/ITokenDecimals.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BorrowAbstract
 * @dev Abstract contract for managing borrowing and collateral interactions
 * within the DeFi ecosystem, utilizing the Comet protocol.
 * This contract allows for asset supply, withdrawal, and management
 * of borrowing dynamics, while enforcing security through ownership and reentrancy guards.
 */
abstract contract BorrowAbstract is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    address public comet; // Address of the Comet protocol for lending and borrowing
    address public cometReward; // Address for claiming rewards from Comet
    address public asset; // Address of the collateral asset (e.g., WBTC or WETH)
    address public baseAsset; // Address of the base asset used for borrowing (e.g., USDC)
    address public bulker; // Address of the Bulker contract for batch operations
    address public engine; // Address of the Torque USD Engine
    address public tusd; // Address of the TUSD token
    address public treasury; // Address for collecting fees and rewards
    address public controller; // Address managing interactions with this contract
    uint public claimPeriod; // Time period between reward claims (in seconds)
    uint public repaySlippage; // Slippage percentage allowed during repayment
    uint public lastClaimCometTime; // Last timestamp when Comet rewards were claimed

    uint256 public borrowHealth; // Health factor of the borrower's position

    uint256 public decimalAdjust = 1000000000000; // Decimal adjustment for calculations

    bytes32 public constant ACTION_SUPPLY_ASSET = "ACTION_SUPPLY_ASSET";
    bytes32 public constant ACTION_SUPPLY_ETH = "ACTION_SUPPLY_NATIVE_TOKEN";
    bytes32 public constant ACTION_TRANSFER_ASSET = "ACTION_TRANSFER_ASSET";
    bytes32 public constant ACTION_WITHDRAW_ASSET = "ACTION_WITHDRAW_ASSET";
    bytes32 public constant ACTION_WITHDRAW_ETH = "ACTION_WITHDRAW_NATIVE_TOKEN";
    bytes32 public constant ACTION_CLAIM_REWARD = "ACTION_CLAIM_REWARD";

    uint256 public LIQUIDATION_THRESHOLD; // Threshold below which a borrow position may be liquidated
    uint256 public PRECISION; // Precision factor for calculations
    uint256 public LIQUIDATION_PRECISION; // Precision for liquidation calculations
    uint256 public MIN_HEALTH_FACTOR; // Minimum health factor required to avoid liquidation

    /**
     * @notice Constructor to initialize the contract with necessary parameters.
     * @param _initialOwner Address of the contract's initial owner.
     * @param _comet Address of the Compound V3 protocol.
     * @param _cometReward Address for claiming Comet rewards.
     * @param _asset Address of the collateral asset (WBTC / WETH).
     * @param _baseAsset Address of the asset to be borrowed (USDC).
     * @param _bulker Address of the Bulker contract.
     * @param _engine Address of the Torque USD Engine.
     * @param _tusd Address of the TUSD token.
     * @param _treasury Address for collecting fees.
     * @param _controller Address of the controller.
     * @param _repaySlippage Slippage percentage for repayments.
     */
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
        address _controller,
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
        IComet(_comet).allow(_bulker, true); // Allow the bulker contract to manage assets
        claimPeriod = 86400; // 1 day in seconds
        repaySlippage = _repaySlippage; // Set repay slippage
        controller = _controller; // Set the controller address
        fetchValues(); // Fetch and set necessary values from the engine
    }

    uint constant BASE_ASSET_MANTISA = 1e6;
    uint constant PRICE_MANTISA = 1e2;
    uint constant SCALE = 1e18;
    uint constant WITHDRAW_OFFSET = 1e2;
    uint constant TUSD_DECIMAL_OFFSET = 1e12;
    uint constant PRICE_SCALE = 1e8;

    uint public baseBorrowed; // TUSD borrowed 
    uint public borrowed; // USDC Borrowed 
    uint public supplied; // WBTC Supplied
    uint public borrowTime; // Borrow time

    event UserBorrow(address user, address collateralAddress, uint amount); // Event emitted on borrow
    event UserRepay(address user, address collateralAddress, uint repayAmount, uint claimAmount); // Event emitted on repayment

    /**
     * @notice Fetch and update critical values from the TUSD engine.
     * @dev Can be called by anyone to refresh the values.
     */
    function fetchValues() public {
        LIQUIDATION_THRESHOLD = ITUSDEngine(engine).getLiquidationThreshold();
        PRECISION = ITUSDEngine(engine).getPrecision();
        LIQUIDATION_PRECISION = ITUSDEngine(engine).getLiquidationPrecision();
        MIN_HEALTH_FACTOR = ITUSDEngine(engine).getMinHealthFactor();
    }

    /**
     * @notice Get the collateral factor for the supplied asset.
     * @return The collateral factor as a uint.
     */
    function getCollateralFactor() public view returns (uint){
        IComet icomet = IComet(comet);
        IComet.AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        return info.borrowCollateralFactor;
    }

    /**
     * @notice Calculate the maximum borrowable amount for the user based on supplied collateral.
     * @return The maximum borrowable amount in USDC.
     */
    function getUserBorrowable() public view returns (uint){
        if(supplied == 0) {
            return 0; 
        }
        uint assetSupplyAmount = supplied;
        uint maxUsdc = getBorrowableUsdc(assetSupplyAmount);
        uint maxTusd = getBorrowableV2(maxUsdc); 
        return maxTusd;
    }

    /**
     * @notice Calculate the maximum borrowable amount in TUSD.
     * @param maxUSDC The maximum USDC borrowable amount.
     * @return The maximum borrowable amount in TUSD.
     */
    function getBorrowableV2(uint maxUSDC) public view returns (uint){
        uint mintable = getMintableToken(maxUSDC, baseBorrowed, 0);
        return mintable;
    }
    
    /**
     * @notice Calculate the maximum borrowable USDC amount based on supplied collateral.
     * @param supplyAmount The amount of collateral supplied.
     * @return The maximum borrowable amount in USDC.
     */
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

    /**
     * @notice Withdraw an amount of asset to the specified address.
     * @param _address The address to withdraw to.
     * @param withdrawAmount The amount to withdraw.
     */
    function withdraw(address _address, uint withdrawAmount) public nonReentrant() {
        require(msg.sender == controller, "Cannot be called directly");
        require(supplied > 0, "User does not have asset");
        if (borrowed > 0) {
            uint accruedInterest = calculateInterest(borrowed, borrowTime);
            borrowed = borrowed.add(accruedInterest);
            borrowTime = block.timestamp;
        }
        IComet icomet = IComet(comet);
        IComet.AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);
        uint assetDecimal = ITokenDecimals(asset).decimals();
        uint minRequireSupplyAmount = borrowed.mul(SCALE).mul(10**assetDecimal).mul(PRICE_MANTISA).div(price).div(uint(info.borrowCollateralFactor).sub(WITHDRAW_OFFSET));
        uint withdrawableAmount = supplied - minRequireSupplyAmount;
        require(withdrawAmount <= withdrawableAmount, "Exceeds asset supply");
        supplied = supplied.sub(withdrawAmount);
        bytes[] memory callData = new bytes[](1);
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, withdrawAmount);
        callData[0] = withdrawAssetCalldata;
        IBulker(bulker).invoke(buildWithdraw(), callData);
        require(IERC20(asset).transfer(_address, withdrawAmount), "Transfer Asset Failed");
    } 
    
    /**
     * @notice Get the total borrow balance including accrued interest.
     * @return The total borrow balance as a uint.
     */
    function borrowBalanceOf() public view returns (uint) {
        if(borrowed == 0) {
            return 0;
        }
        uint borrowAmount = borrowed;
        uint interest = calculateInterest(borrowAmount, borrowTime);
        return borrowAmount + interest;
    }

    /**
     * @notice Calculate the interest accrued on the borrowed amount.
     * @param borrowAmount The amount borrowed.
     * @param _borrowTime The time the amount has been borrowed.
     * @return The interest accrued as a uint.
     */
    function calculateInterest(uint borrowAmount, uint _borrowTime) public view returns (uint) {
        IComet icomet = IComet(comet);
        uint totalSecond = block.timestamp - _borrowTime;
        return borrowAmount.mul(icomet.getBorrowRate(icomet.getUtilization())).mul(totalSecond).div(1e18);
    }

    /**
     * @notice Get the annual percentage rate (APR) for the borrowed amount.
     * @return The APR as a uint.
     */
    function getApr() public view returns (uint) {
        IComet icomet = IComet(comet);
        uint borowRate = icomet.getBorrowRate(icomet.getUtilization());
        return borowRate.mul(31536000);
    }

    /**
     * @notice Claim rewards from the Comet protocol.
     * @dev Only callable by the controller after the claim period.
     */
    function claimCReward() public {
        require(msg.sender == controller, "Cannot be called directly");
        require(lastClaimCometTime + claimPeriod < block.timestamp, "Already claimed");
        require(treasury != address(0), "Invalid treasury");
        lastClaimCometTime = block.timestamp;
        ICometRewards(cometReward).claim(comet, treasury, true);
    }

    /**
     * @notice Build the borrow action for external calls.
     * @return An array of actions to be executed.
     */
    function buildBorrowAction() pure virtual public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);
        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;
        return actions;
    }

    /**
     * @notice Build the withdraw action for external calls.
     * @return An array of actions to be executed.
     */
    function buildWithdraw() pure public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](1);
        actions[0] = ACTION_WITHDRAW_ASSET;
        return actions;
    }

    /**
     * @notice Build the repay action for external calls.
     * @return An array of actions to be executed.
     */
    function buildRepay() pure virtual public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);
        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;
        return actions;
    }

    /**
     * @notice Build the repay borrow action for external calls.
     * @return An array of actions to be executed.
     */
    function buildRepayBorrow() pure public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);
        actions[0] = ACTION_SUPPLY_ASSET;
        return actions;
    }

    /**
     * @notice Calculate the amount of mintable TUSD based on USDC supply.
     * @param _usdcSupply Total USDC supply available for minting TUSD.
     * @param _mintedTUSD Amount of TUSD already minted.
     * @param _toMintTUSD Amount of TUSD intended to be minted.
     * @return The total mintable amount of TUSD.
     */
    function getMintableToken(uint256 _usdcSupply, uint256 _mintedTUSD, uint256 _toMintTUSD) public view returns (uint256) {
        uint256 totalMintable = _usdcSupply.mul(LIQUIDATION_THRESHOLD)
            .mul(PRECISION)
            .mul(decimalAdjust)
            .div(LIQUIDATION_PRECISION)
            .div(MIN_HEALTH_FACTOR);
        require(totalMintable >= _mintedTUSD + _toMintTUSD, "User can not mint more TUSD");
        totalMintable -= _mintedTUSD;
        return totalMintable;
    }

    /**
     * @notice Calculate the amount of TUSD that can be burned based on repayment amount.
     * @param _tUsdRepayAmount Amount of TUSD to repay.
     * @param tUSDBorrowAmount Amount of TUSD borrowed.
     * @param _usdcToBePayed Amount of USDC to be paid.
     * @return The maximum amount of collateral that can be withdrawn.
     */
    function getBurnableToken(uint256 _tUsdRepayAmount, uint256 tUSDBorrowAmount, uint256 _usdcToBePayed) public view returns (uint256) {
        require(tUSDBorrowAmount >= _tUsdRepayAmount, "You have not minted enough TUSD");
        if(tUSDBorrowAmount == 0){
            return _usdcToBePayed;
        }
        else{
            uint256 totalWithdrawableCollateral = _tUsdRepayAmount.mul(LIQUIDATION_PRECISION)
                .mul(MIN_HEALTH_FACTOR)
                .div(LIQUIDATION_THRESHOLD)
                .div(PRECISION)
                .div(decimalAdjust);
            require(totalWithdrawableCollateral <= _usdcToBePayed, "User cannot withdraw more collateral");
            return totalWithdrawableCollateral;
        }
    }
    
    receive() external payable {} // Fallback function to accept ETH deposits
}
