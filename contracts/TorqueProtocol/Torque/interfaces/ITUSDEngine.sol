// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface ITUSDEngine {
    function getMintableTUSD(address tokenCollateralAddress, address user, uint256 amountCollateral) external view returns (uint256, bool);
    function getBurnableTUSD(address tokenCollateralAddress, address user, uint256 amountTUSD) external view returns (uint256, bool);
    function getRedeemableCollateral(address tokenCollateralAddress, address user, uint256 amountTUSD) external view returns (uint256, bool);
    function getBorrowableTUSD(address tokenCollateralAddress, address user, uint256 amountCollateral) external view returns (uint256, bool);

    function getLiquidationRate(address tokenCollateralAddress) external view returns (uint256);
    function getInterestRate(address tokenCollateralAddress) external view returns (uint256);
    function getOraclePrice(address tokenCollateralAddress) external view returns (uint256);
    function getOracleDecimals(address tokenCollateralAddress) external view returns (uint256);
    function getOracleAddress(address tokenCollateralAddress) external view returns (address);
    
    function getTUSDMintingFee() external view returns (uint256);
    function getTUSDRedemptionFee() external view returns (uint256);
    function getTUSDRedemptionPenalty() external view returns (uint256);
    function getTUSDInitialCollateralRatio() external view returns (uint256);
    function getTUSDMaxCollateralRatio() external view returns (uint256);
    function getTUSDInitialPrice() external view returns (uint256);
    function getTUSDTargetPrice() external view returns (uint256);
    function getTUSDMaxSwapSlippage() external view returns (uint256);
    function getTUSDMaxSwapSpread() external view returns (uint256);
    function getTUSDMaxDebtBasisPoints() external view returns (uint256);
    function getTUSDMaxReserveFactor() external view returns (uint256);
    function getTUSDMaxLiquidationReward() external view returns (uint256);
    function getTUSDMaxInterestRate() external view returns (uint256);

    function depositCollateralAndMintTusd(address tokenCollateralAddress, uint256 amountCollateral, uint256 amounUSDToMint, address onBehalfUser) external payable;
    function redeemCollateralForTusd(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountTUSDToBurn, address onBehalfUser) external payable;
}
