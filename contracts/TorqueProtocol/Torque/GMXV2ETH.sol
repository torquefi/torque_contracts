pragma solidity ^0.8.0;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "../interfaces/IGMX.sol";
import "..interfaces/IDeposit.sol";
import "..interfaces/IDepositCallback.sol";
import "..interfaces/IDepositHandler.sol";
import "..interfaces/IEvent.sol";
import "..interfaces/IRouter.sol";
import "..interfaces/IWETH.sol";
import "..interfaces/IWithdraw.sol";
import "..interfaces/IWithdrawCallback.sol";

// @dev I imported all GMX interfaces that should be needed to be implemented.

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/token/ERC20/extensions/ERC4626.sol";

import "./vToken.sol";

contract GMXV2ETH is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable weth;
    IGMX public immutable gmxExchange;
    vToken public immutable vTokenInstance;

    constructor(IERC20 _weth, IGMX _gmxExchange, address vTokenAddress) {
        weth = _weth;
        gmxExchange = _gmxExchange;
        vTokenInstance = vToken(vTokenAddress);
    }

    function deposit(uint256 _amount) external nonReentrant {
        weth.safeTransferFrom(msg.sender, address(this), _amount);
        weth.approve(address(gmxExchange), _amount);
        gmxExchange.deposit(_amount);
        vTokenInstance.mint(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external nonReentrant {
        gmxExchange.withdraw(_amount);
        weth.safeTransfer(msg.sender, _amount);
        vTokenInstance.burn(msg.sender, _amount);
    }
}