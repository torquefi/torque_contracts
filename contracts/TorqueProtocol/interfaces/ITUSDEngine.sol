// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITUSDEngine {
    // function depositCollateralAndMintTusd(address tokenCollateralAddress, uint256 amountCollateral, uint256 amounUSDToMint, address onBehalfUser) external payable;
    // function redeemCollateralForTusd(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountTUSDToBurn, address onBehalfUser) external payable;
    function getMintableTUSD(address user, uint256 amountCollateral) external view returns (uint256, bool);
    function getBurnableTUSD(address user, uint256 amountTUSD) external view returns (uint256, bool);
    function getAccountInformation(address user) external view returns (uint256 totalTusdMinted, uint256 collateralValueInUsd);
    function getPrecision() external pure returns (uint256);
    function getLiquidationPrecision() external pure returns (uint256);
    function getLiquidationThreshold() external pure returns (uint256);
    function getMinHealthFactor() external pure returns (uint256);
    function depositCollateralAndMintTusd(uint256 amountCollateral, uint256 amountTusdToMint) external;
    function redeemCollateralForTusd(uint256 amountCollateral, uint256 amountTusdToBurn) external ;
    function getCollateralBalanceOfUser(address user) external view returns (uint256);
    function mintTusd(uint256 amountTusdToMint) external;

    // function getLiquidationRate() external view returns (uint256);
    // function getInterestRate() external view returns (uint256);
    // function getOraclePrice() external view returns (uint256);
    // function getOracleDecimals() external view returns (uint256);
    // function getOracleAddress() external view returns (address);
    
    // function getTUSDMintingFee() external view returns (uint256);
    // function getTUSDRedemptionFee() external view returns (uint256);
    // function getTUSDRedemptionPenalty() external view returns (uint256);
    // function getTUSDInitialCollateralRatio() external view returns (uint256);
    // function getTUSDMaxCollateralRatio() external view returns (uint256);
    // function getTUSDInitialPrice() external view returns (uint256);
    // function getTUSDTargetPrice() external view returns (uint256);
    // function getTUSDMaxSwapSlippage() external view returns (uint256);
    // function getTUSDMaxSwapSpread() external view returns (uint256);
    // function getTUSDMaxDebtBasisPoints() external view returns (uint256);
    // function getTUSDMaxReserveFactor() external view returns (uint256);
    // function getTUSDMaxLiquidationReward() external view returns (uint256);
    // function getTUSDMaxInterestRate() external view returns (uint256);
}
