// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
interface IUSDEngine {

   function getMintableUSG(
        address tokenCollateralAddress,
        address user,
        uint256 amountCollateral
    ) external view returns (uint256, bool);

    function depositCollateralAndMintUsg(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountUsgToMint
    ) external payable ;

function getBurnableUSG(
        address tokenCollateralAddress,
        address user,
        uint256 amountUSG
    ) external view returns (uint256, bool) ;

    function redeemCollateralForUsg(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountUsgToBurn
    ) external payable;
}