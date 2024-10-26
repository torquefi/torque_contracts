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
import "./interfaces/ITokenDecimals.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract SimpleBorrowAbstract is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    address public comet;
    address public cometReward;
    address public asset;
    address public baseAsset;
    address public bulker;
    address public treasury;
    address public controller;
    
    uint public claimPeriod;
    uint public repaySlippage;
    uint public lastClaimCometTime;

    uint256 public borrowHealth;

    uint256 public decimalAdjust = 1000000000000;
    
    bytes32 public constant ACTION_SUPPLY_ASSET = "ACTION_SUPPLY_ASSET";
    bytes32 public constant ACTION_SUPPLY_ETH = "ACTION_SUPPLY_NATIVE_TOKEN";
    bytes32 public constant ACTION_TRANSFER_ASSET = "ACTION_TRANSFER_ASSET";
    bytes32 public constant ACTION_WITHDRAW_ASSET = "ACTION_WITHDRAW_ASSET";
    bytes32 public constant ACTION_WITHDRAW_ETH = "ACTION_WITHDRAW_NATIVE_TOKEN";
    bytes32 public constant ACTION_CLAIM_REWARD = "ACTION_CLAIM_REWARD";

    /**
     * @notice Initializes the contract with required parameters.
     * @param _initialOwner The address of the initial owner.
     * @param _comet Address for Compound V3.
     * @param _cometReward Address for claiming Comet rewards.
     * @param _asset Address for collateral to be staked (WBTC/WETH).
     * @param _baseAsset Address for the borrowing asset (USDC).
     * @param _bulker Address for the Bulker contract.
     * @param _treasury Address for the fees.
     * @param _controller Address for the controller.
     * @param _repaySlippage Slippage percentage for repayments.
     */
    constructor(
        address _initialOwner,
        address _comet,
        address _cometReward,
        address _asset,
        address _baseAsset,
        address _bulker,
        address _treasury,
        address _controller,
        uint _repaySlippage
    ) {
        Ownable.transferOwnership(_initialOwner);
        comet = _comet;
        cometReward = _cometReward;
        asset = _asset;
        baseAsset = _baseAsset;
        bulker = _bulker;
        treasury = _treasury;
        IComet(_comet).allow(_bulker, true);
        claimPeriod = 86400; // 1 day in seconds
        repaySlippage = _repaySlippage;
        controller = _controller;
    }
    
    uint constant BASE_ASSET_MANTISA = 1e6;
    uint constant PRICE_MANTISA = 1e2;
    uint constant SCALE = 1e18;
    uint constant WITHDRAW_OFFSET = 1e2;
    uint constant TUSD_DECIMAL_OFFSET = 1e12;
    uint constant PRICE_SCALE = 1e8;

    uint public borrowed; // USDC Borrowed 
    uint public supplied; // WBTC Supplied
    uint public borrowTime; // Borrow time

    event UserBorrow(address user, address collateralAddress, uint amount);
    event UserRepay(address user, address collateralAddress, uint repayAmount, uint claimAmount);

    /**
     * @notice Gets the collateral factor for the asset.
     * @return The collateral factor as a percentage.
     */
    function getCollateralFactor() public view returns (uint) {
        IComet icomet = IComet(comet);
        IComet.AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        return info.borrowCollateralFactor;
    }

    /**
     * @notice Gets the borrowable USDC amount based on the supplied asset amount.
     * @param supplyAmount The amount of asset supplied.
     * @return The amount of borrowable USDC.
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
     * @notice Gets the additional borrowable USDC amount.
     * @return The additional borrowable USDC amount.
     */
    function getMoreBorrowableUsdc() public view returns (uint) {
        IComet icomet = IComet(comet);
        IComet.AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint assetDecimal = ITokenDecimals(asset).decimals();
        uint256 totalUSDC = supplied
            .mul(info.borrowCollateralFactor)
            .mul(icomet.getPrice(info.priceFeed))
            .div(PRICE_MANTISA)
            .div(10**assetDecimal)
            .div(SCALE);

        return totalUSDC - borrowed;
    }

    /**
     * @notice Withdraws a specified amount of asset from the contract.
     * @param _address The address to withdraw to.
     * @param withdrawAmount The amount of asset to withdraw.
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
     * @notice Gets the current borrow balance including accrued interest.
     * @return The total borrow balance.
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
     * @notice Calculates the interest on the borrowed amount.
     * @param borrowAmount The amount borrowed.
     * @param _borrowTime The timestamp when the amount was borrowed.
     * @return The calculated interest.
     */
    function calculateInterest(uint borrowAmount, uint _borrowTime) public view returns (uint) {
        IComet icomet = IComet(comet);
        uint totalSecond = block.timestamp - _borrowTime;
        return borrowAmount.mul(icomet.getBorrowRate(icomet.getUtilization())).mul(totalSecond).div(1e18);
    }

    /**
     * @notice Gets the annual percentage rate (APR) for the borrow rate.
     * @return The APR as a percentage.
     */
    function getApr() public view returns (uint) {
        IComet icomet = IComet(comet);
        uint borrowRate = icomet.getBorrowRate(icomet.getUtilization());
        return borrowRate.mul(31536000);
    }

    /**
     * @notice Claims rewards for the caller.
     */
    function claimCReward() public {
        require(msg.sender == controller, "Cannot be called directly");
        ICometRewards(cometReward).claim(comet, address(this), true);
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

    function buildRepayBorrow() pure public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);
        actions[0] = ACTION_SUPPLY_ASSET;
        return actions;
    }

    function buildRepay() pure virtual public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);
        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;
        return actions;
    }
    
    receive() external payable {}
}
