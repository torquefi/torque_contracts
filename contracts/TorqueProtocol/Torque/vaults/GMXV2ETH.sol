pragma solidity ^0.8.0;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "../interfaces/IGMX.sol";
import "../interfaces/IExchangeRouter.sol";
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

import "../vToken.sol";

contract GMXV2ETH is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable weth;
    IExchangeRouter public immutable gmxExchange;
    vToken public immutable vTokenInstance;

    struct CreateDepositParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minMarketTokens;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    struct CreateWithdrawalParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minLongTokenAmount;
        uint256 minShortTokenAmount;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    constructor(IERC20 _weth, IGMX _gmxExchange, address vTokenAddress) {
        weth = _weth;
        gmxExchange = _gmxExchange;
        vTokenInstance = vToken(vTokenAddress);
    }

    function deposit(
        WithdrawalUtils.CreateWithdrawalParams calldata params
    ) external payable nonReentrant {
        weth.safeTransferFrom(msg.sender, address(this), _amount);
        weth.approve(address(gmxExchange), _amount);
        gmxExchange.createDeposit(params);
        vTokenInstance.mint(msg.sender, _amount);
    }

    function withdraw(CreateWithdrawalParams calldata params) external nonReentrant {
        gmxExchange.createDeposit(params);
        weth.safeTransfer(msg.sender, _amount);
        vTokenInstance.burn(msg.sender, _amount);
    }

    function sendWnt() public {}

    function sendTokens() public {}
}
