// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IExchangeRouter.sol";

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

interface IGMXV2ETH {
    function deposit(IExchangeRouter.CreateDepositParams calldata params) external returns (uint256 gmTokenAmount);

    function withdraw(IExchangeRouter.CreateWithdrawalParams calldata params) external returns (uint256 wethAmount, uint256 usdcAmount);
}
