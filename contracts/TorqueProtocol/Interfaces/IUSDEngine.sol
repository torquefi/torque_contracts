// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
interface IUSDEngine {

   function getMintableUSD(
        address tokenCollateralAddress,
        address user,
        uint256 amountCollateral
    ) external view returns (uint256, bool);

    function depositCollateralAndMintUsd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountUsdToMint
    ) external payable ;

function getBurnableUSD(
        address tokenCollateralAddress,
        address user,
        uint256 amountUSD
    ) external view returns (uint256, bool) ;

    function redeemCollateralForUsd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountUsdToBurn
    ) external payable;
}