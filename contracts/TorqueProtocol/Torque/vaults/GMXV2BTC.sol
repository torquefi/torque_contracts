// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./../interfaces/IGMX.sol";
import "./../interfaces/IExchangeRouter.sol";
// import "./..interfaces/IDeposit.sol";
// import "./..interfaces/IDepositCallback.sol";
// import "./..interfaces/IDepositHandler.sol";
// import "./..interfaces/IEvent.sol";
// import "./..interfaces/IRouter.sol";
// import "./..interfaces/IWETH.sol";
// import "./..interfaces/IWithdraw.sol";
// import "./..interfaces/IWithdrawCallback.sol";
import "./../interfaces/IGMXV2ETH.sol";

// @dev should implement the above GMX interfaces

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "./../vToken.sol";

contract GMXV2BTC is ERC4626, Ownable, ReentrancyGuard, IGMXV2ETH {
    using SafeERC20 for IERC20;

    // Logic to supply WBTC deposits to GMX V2 pool
    // Logic for auto-compounding fees to grow LPs position
    // Logic to direct performance fee to treasury

}
