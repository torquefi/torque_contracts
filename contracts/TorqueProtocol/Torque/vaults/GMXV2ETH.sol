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

// @dev I imported all GMX interfaces that should be needed to be implemented.

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "./../vToken.sol";

contract GMXV2ETH is Ownable, ReentrancyGuard, IGMXV2ETH {
    using SafeERC20 for IERC20;

    IERC20 public wethGMX;
    IERC20 public gmToken;
    IERC20 public usdcToken;
    address marketAddress;
    // IERC20 public immutable
    address depositVault;
    address withdrawalVault;
    IExchangeRouter public immutable gmxExchange;
    vToken public immutable vTokenInstance;

    constructor(
        address _weth,
        address _gmxExchange,
        address vTokenAddress,
        address _gmToken,
        address _usdcToken,
        address _depositVault,
        address _withdrawalVault
    ) {
        wethGMX = IERC20(_weth);
        gmxExchange = IExchangeRouter(_gmxExchange);
        vTokenInstance = vToken(vTokenAddress);
        gmToken = IERC20(_gmToken);
        usdcToken = IERC20(_usdcToken);
        depositVault = _depositVault;
        withdrawalVault = _withdrawalVault;
    }

    function _depositGMX(
        uint256 _amount
    ) external payable nonReentrant returns (uint256 gmTokenAmount) {
        gmxExchange.sendWnt(depositVault, _amount);
        IExchangeRouter.CreateDepositParams memory params = createDepositParams();
        wethGMX.safeTransferFrom(msg.sender, address(this), _amount);
        wethGMX.approve(depositVault, _amount);
        gmxExchange.createDeposit{ value: _amount }(params);
        vTokenInstance.mint(msg.sender, _amount);
        gmTokenAmount = gmToken.balanceOf(address(this));
    }

    function _withdrawGMX(
        uint256 _amount
    ) external payable nonReentrant returns (uint256 wethAmount, uint256 usdcAmount) {
        gmxExchange.sendTokens(address(gmToken), withdrawalVault, _amount);
        IExchangeRouter.CreateWithdrawalParams memory params = createWithdrawParams();
        gmToken.safeTransferFrom(msg.sender, address(this), _amount);
        gmToken.approve(withdrawalVault, _amount);
        gmxExchange.createWithdrawal(params);
        wethGMX.safeTransfer(msg.sender, _amount);
        vTokenInstance.burn(msg.sender, _amount);
        wethAmount = wethGMX.balanceOf(address(this));
        usdcAmount = usdcToken.balanceOf(address(this));
    }

    function _sendWnt(address _receiver, uint256 _amount) private {
        gmxExchange.sendWnt(_receiver, _amount);
    }

    function _sendTokens(address _token, address _receiver, uint256 _amount) private {
        gmxExchange.sendTokens(_token, _receiver, _amount);
    }

    function createDepositParams()
        internal
        view
        returns (IExchangeRouter.CreateDepositParams memory)
    {
        IExchangeRouter.CreateDepositParams memory depositParams;
        depositParams.callbackContract = address(this);
        depositParams.callbackGasLimit = 0;
        depositParams.executionFee = 0;
        depositParams.initialLongToken = address(wethGMX);
        depositParams.initialShortToken = address(usdcToken);
        depositParams.market = marketAddress;
        depositParams.shouldUnwrapNativeToken = true;
        depositParams.receiver = address(this);
        depositParams.minMarketTokens = 0;

        return depositParams;
    }

    function createWithdrawParams()
        internal
        view
        returns (IExchangeRouter.CreateWithdrawalParams memory)
    {
        IExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.callbackContract = address(this);
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = 0;
        // withdrawParams.initialLongToken = address(weth);
        // withdrawParams.initialShortToken = address(usdcToken);
        withdrawParams.market = marketAddress;
        withdrawParams.shouldUnwrapNativeToken = true;
        withdrawParams.receiver = address(this);
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;

        return withdrawParams;
    }

    function deposit(
        IExchangeRouter.CreateWithdrawalParams calldata params
    ) external override returns (uint256 gmTokenAmount) {}

    function withdraw(
        IExchangeRouter.CreateWithdrawalParams calldata params
    ) external override returns (uint256 wethAmount, uint256 usdcAmount) {}
}
