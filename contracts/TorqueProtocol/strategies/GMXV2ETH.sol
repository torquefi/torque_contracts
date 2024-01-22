// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../UniswapContracts/ISwapRouter.sol";
import "../interfaces/IGMXExchangeRouter.sol";

contract GMXV2ETH is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public weth;
    IERC20 public gmToken;
    IERC20 public usdcToken;

    address marketAddress;
    address depositVault;
    address withdrawalVault;

    IGMXExchangeRouter public exchangeRouter;
    ISwapRouter public swapRouter;

    constructor(address weth_, address gmToken_, address usdcToken_, address exchangeRouter_, address swapRouter_, address depositVault_, address withdrawalVault_){
        weth = IERC20(weth_);
        gmToken = IERC20(gmToken_);
        usdcToken = IERC20(usdcToken_);
        exchangeRouter = IGMXExchangeRouter(exchangeRouter_);
        swapRouter = ISwapRouter(swapRouter_);
        depositVault = depositVault_;
        withdrawalVault = withdrawalVault_;
    }

    function deposit(uint256 _amount) external {
        IGMXExchangeRouter.CreateDepositParams memory depositParams;
        depositParams.callbackContract = address(this);
        depositParams.callbackGasLimit = 0;
        depositParams.executionFee = 0;
        depositParams.initialLongToken = address(weth);
        depositParams.initialShortToken = address(usdcToken);
        depositParams.market = marketAddress;
        depositParams.shouldUnwrapNativeToken = true;
        depositParams.receiver = address(this);
        depositParams.minMarketTokens = 0;
        weth.safeTransferFrom(msg.sender, address(this), _amount);
        weth.approve(depositVault, _amount);
        exchangeRouter.createDeposit{value: _amount}(depositParams);
        uint256 gmAmount = gmToken.balanceOf(address(this));
        gmToken.safeTransfer(msg.sender, gmAmount);
    }

    function withdraw(uint256 _amount) external {
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.callbackContract = address(this);
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = 0;
        withdrawParams.market = marketAddress;
        withdrawParams.shouldUnwrapNativeToken = true;
        withdrawParams.receiver = address(this);
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        gmToken.safeTransferFrom(msg.sender, address(this), _amount);
        gmToken.approve(withdrawalVault, _amount);
        exchangeRouter.createWithdrawal(withdrawParams);
        uint256 usdcAmount = usdcToken.balanceOf(address(this));
        swapUSDCtoWETH(usdcAmount);
        uint256 wethAmount = weth.balanceOf(address(this));
        weth.safeTransfer(msg.sender, wethAmount);
    }

    function swapUSDCtoWETH(uint256 usdcAmount) internal {
        usdcToken.approve(address(swapRouter), usdcAmount);
        ISwapRouter.ExactInputSingleParams memory params =  
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdcToken),
                tokenOut: address(weth),
                fee: 0,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: usdcAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        swapRouter.exactInputSingle(params);
    }
}