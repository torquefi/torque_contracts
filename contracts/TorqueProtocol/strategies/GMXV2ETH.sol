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
import "../interfaces/IWETH9.sol";

contract GMXV2ETH is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWETH9 public weth;
    IERC20 public gmToken;
    IERC20 public usdcToken;
    IERC20 public arbToken;

    address public marketAddress = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
    address depositVault;
    address withdrawalVault;

    IGMXExchangeRouter public exchangeRouter;
    ISwapRouter public swapRouter;

    uint256 depositedWethAmount;

    constructor(address payable weth_, address gmToken_, address usdcToken_, address arbToken_, address exchangeRouter_, address swapRouter_, address depositVault_, address withdrawalVault_){
        weth = IWETH9(weth_);
        gmToken = IERC20(gmToken_);
        usdcToken = IERC20(usdcToken_);
        arbToken = IERC20(arbToken_);
        exchangeRouter = IGMXExchangeRouter(exchangeRouter_);
        swapRouter = ISwapRouter(swapRouter_);
        depositVault = depositVault_;
        withdrawalVault = withdrawalVault_;
        depositedWethAmount = 0;
    }

    function deposit(uint256 _amount) external {
        exchangeRouter.sendWnt(depositVault, _amount);
        IGMXExchangeRouter.CreateDepositParams memory depositParams = createDepositParams();
        weth.transferFrom(msg.sender, address(this), _amount);
        weth.approve(depositVault, _amount);
        exchangeRouter.createDeposit{value: _amount}(depositParams);
        depositedWethAmount = depositedWethAmount + _amount;
    }

    function withdraw(uint256 _amount) external onlyOwner() {
        uint256 gmAmountWithdraw = _amount * gmToken.balanceOf(address(this)) / depositedWethAmount;
        depositedWethAmount = depositedWethAmount - _amount;
        exchangeRouter.sendTokens(address(gmToken), withdrawalVault, gmAmountWithdraw);
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams = createWithdrawParams();
        gmToken.approve(withdrawalVault, gmAmountWithdraw);
        exchangeRouter.createWithdrawal(withdrawParams);
        uint256 usdcAmount = usdcToken.balanceOf(address(this));
        if(usdcAmount > 0){
            swapUSDCtoWETH(usdcAmount);
        }
        uint256 wethAmount = weth.balanceOf(address(this));
        weth.transfer(msg.sender, wethAmount);
    }

    function compound() external onlyOwner() {
        uint256 arbAmount = arbToken.balanceOf(address(this));
        if(arbAmount > 0){
            swapARBtoWETH(arbAmount);
            uint256 wethAmount = weth.balanceOf(address(this));
            weth.transfer(msg.sender, wethAmount);
        }
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

    function swapARBtoWETH(uint256 arbAmount) internal returns (uint256 amountOut){
        arbToken.approve(address(swapRouter), arbAmount);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(arbToken),
                tokenOut: address(weth),
                fee: 0,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: arbAmount,
                amountOutMinimum:0,
                sqrtPriceLimitX96: 0
            });
        return swapRouter.exactInputSingle(params);
    }

    function createDepositParams() internal view returns (IGMXExchangeRouter.CreateDepositParams memory) {
        IGMXExchangeRouter.CreateDepositParams memory depositParams;
        depositParams.callbackContract = address(this);
        depositParams.callbackGasLimit = 200000;
        depositParams.executionFee = 0;
        depositParams.initialLongToken = address(weth);
        depositParams.initialShortToken = address(usdcToken);
        depositParams.market = marketAddress;
        depositParams.shouldUnwrapNativeToken = true;
        depositParams.receiver = address(this);
        depositParams.minMarketTokens = 0;
        return depositParams;
    }

    function createWithdrawParams() internal view returns (IGMXExchangeRouter.CreateWithdrawalParams memory) {
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.callbackContract = address(this);
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = 0;
        withdrawParams.market = marketAddress;
        withdrawParams.shouldUnwrapNativeToken = true;
        withdrawParams.receiver = address(this);
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        return withdrawParams;
    }
}