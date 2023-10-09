// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

interface IUSDEngine {

    error USDEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error USDEngine__NeedsMoreThanZero();
    error USDEngine__TokenNotAllowed(address token);
    error USDEngine__TransferFailed();
    error USDEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error USDEngine__MintFailed();
    error USDEngine__HealthFactorOk();
    error USDEngine__HealthFactorNotImproved();
    error OracleLib__StalePrice();

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        uint256 indexed amountCollateral,
        address from,
        address to
    ); // if from != to, then it was liquidated
}
