// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

interface ITUSDEngine {
    
    error TUSDEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error TUSDEngine__NeedsMoreThanZero();
    error TUSDEngine__TokenNotAllowed(address token);
    error TUSDEngine__TransferFailed();
    error TUSDEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error TUSDEngine__MintFailed();
    error TUSDEngine__HealthFactorOk();
    error TUSDEngine__HealthFactorNotImproved();
    error TUSDEngine__NotLatestPrice();
    error OracleLib__StalePrice();

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, uint256 indexed amountCollateral, address from, address to); // if from != to, then it was liquidated
}
