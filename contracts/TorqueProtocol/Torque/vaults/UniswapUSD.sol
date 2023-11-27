// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

/// @dev Must import Uniswap interfaces

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "./../vToken.sol";

contract UniswapUSD is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Logic to supply 25% of deposit as USDC and 25% of deposit as Torque USD to Uniswap V3 0.01 pool
    // Logic for auto-compounding USDC and Torque USD fees to grow the liquidity provider's position
    // Logic to direct performance fee to treasury with 12 hr min duration between calls
}
