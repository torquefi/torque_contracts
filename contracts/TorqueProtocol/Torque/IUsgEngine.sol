// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

interface IUsgEngine {

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