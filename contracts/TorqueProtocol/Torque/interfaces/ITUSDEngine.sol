// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface ITUSDEngine {
    function getMintableTUSD(
        address tokenCollateralAddress,
        address user,
        uint256 amountCollateral
    ) external view returns (uint256, bool);

    function depositCollateralAndMintTusd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amounUSDToMint
    ) external payable;

    function getBurnableTUSD(
        address tokenCollateralAddress,
        address user,
        uint256 amountUSD
    ) external view returns (uint256, bool);

    function redeemCollateralForTusd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountUSDToBurn
    ) external payable;
}
