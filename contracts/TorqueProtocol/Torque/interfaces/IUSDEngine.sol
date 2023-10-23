// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

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