// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./../interfaces/IGMX.sol";
import "./../interfaces/IExchangeRouter.sol";
import "./../interfaces/IGMXV2ETH.sol";

contract GMXV2BTC is Ownable, ReentrancyGuard, IGMXV2ETH {
    IERC20 public wbtcGMX;
    IERC20 public gmToken;
    IERC20 public usdcToken;
    address marketAddress;
    address depositVault;
    address withdrawalVault;
    
    IExchangeRouter public immutable gmxExchange;

    constructor(
        address _wbtc,
        address _gmxExchange,
        address _gmToken,
        address _usdcToken,
        address _depositVault,
        address _withdrawalVault
    ) {
        wbtcGMX = IERC20(_wbtc);
        gmxExchange = IExchangeRouter(_gmxExchange);
        gmToken = IERC20(_gmToken);
        usdcToken = IERC20(_usdcToken);
        depositVault = _depositVault;
        withdrawalVault = _withdrawalVault;
    }

    function _deposit(uint256 _amount) internal payable returns (uint256 gmTokenAmount) {
        gmxExchange.sendWnt(depositVault, _amount);
        IExchangeRouter.CreateDepositParams memory params = createDepositParams();
        wbtcGMX.safeTransferFrom(msg.sender, address(this), _amount);
        wbtcGMX.approve(depositVault, _amount);
        gmxExchange.createDeposit{ value: _amount }(params);
        gmTokenAmount = gmToken.balanceOf(address(this));
    }

    function _withdraw(uint256 _amount) internal returns (uint256 wbtcAmount, uint256 usdcAmount) {
        gmxExchange.sendTokens(address(gmToken), withdrawalVault, _amount);
        IExchangeRouter.CreateWithdrawalParams memory params = createWithdrawParams();
        gmToken.safeTransferFrom(msg.sender, address(this), _amount);
        gmToken.approve(withdrawalVault, _amount);
        gmxExchange.createWithdrawal(params);
        wbtcAmount = wbtcGMX.balanceOf(address(this));
        usdcAmount = usdcToken.balanceOf(address(this));
        wbtcGMX.safeTransfer(msg.sender, wbtcAmount);
        // usdcToken.safeTransfer(msg.sender, usdcAmount); // user is expecting WBTC
        // Convert USDC to WBTC before process continues
    }

    function _sendWnt(address _receiver, uint256 _amount) private {
        gmxExchange.sendWnt(_receiver, _amount);
    }

    function _sendTokens(address _token, address _receiver, uint256 _amount) private {
        gmxExchange.sendTokens(_token, _receiver, _amount);
    }

    function createDepositParams() internal view returns (IExchangeRouter.CreateDepositParams memory) {
        IExchangeRouter.CreateDepositParams memory depositParams;
        depositParams.callbackContract = address(this);
        depositParams.callbackGasLimit = 0;
        depositParams.executionFee = 0;
        depositParams.initialLongToken = address(wbtcGMX);
        depositParams.initialShortToken = address(usdcToken);
        depositParams.market = marketAddress;
        depositParams.shouldUnwrapNativeToken = true;
        depositParams.receiver = address(this);
        depositParams.minMarketTokens = 0;
        return depositParams;
    }

    function createWithdrawParams() internal view returns (IExchangeRouter.CreateWithdrawalParams memory) {
        IExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.callbackContract = address(this);
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = 0;
        // withdrawParams.initialLongToken = address(wbtc);
        // withdrawParams.initialShortToken = address(usdcToken);
        withdrawParams.market = marketAddress;
        withdrawParams.shouldUnwrapNativeToken = true;
        withdrawParams.receiver = address(this);
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        return withdrawParams;
    }
}
