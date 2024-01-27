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
    uint256 public executionFee; 
    address depositVault;
    address withdrawalVault;
    address router;

    IGMXExchangeRouter public exchangeRouter;
    ISwapRouter public swapRouter;

    uint256 public depositedWethAmount;
    uint256 minUSDCAmount = 0;
    uint256 minARBAmount = 1000000000000000000;

    constructor(address payable weth_, address gmToken_, address usdcToken_, address arbToken_, address payable exchangeRouter_, address swapRouter_, address depositVault_, address withdrawalVault_, address router_){
        weth = IWETH9(weth_);
        gmToken = IERC20(gmToken_);
        usdcToken = IERC20(usdcToken_);
        arbToken = IERC20(arbToken_);
        exchangeRouter = IGMXExchangeRouter(exchangeRouter_);
        swapRouter = ISwapRouter(swapRouter_);
        depositVault = depositVault_;
        withdrawalVault = withdrawalVault_;
        router = router_;
        depositedWethAmount = 0;
        executionFee = 1000000000000000;
    }

    function deposit(uint256 _amount) external payable{
        require(msg.value >= executionFee, "You must pay GMX v2 execution fee");
        exchangeRouter.sendWnt{value: executionFee}(address(depositVault), executionFee);
        weth.transferFrom(msg.sender, address(this), _amount);
        weth.approve(address(router), _amount);
        exchangeRouter.sendTokens(address(weth), address(depositVault), _amount);
        IGMXExchangeRouter.CreateDepositParams memory depositParams = createDepositParams();
        exchangeRouter.createDeposit(depositParams);
        depositedWethAmount = depositedWethAmount + _amount;
    }

    function withdraw(uint256 _amount) external payable onlyOwner() {
        require(msg.value >= executionFee, "You must pay GMX v2 execution fee");
        exchangeRouter.sendWnt{value: executionFee}(address(withdrawalVault), executionFee);
        uint256 gmAmountWithdraw = _amount * gmToken.balanceOf(address(this)) / depositedWethAmount;
        gmToken.approve(address(router), gmAmountWithdraw);
        exchangeRouter.sendTokens(address(gmToken), address(withdrawalVault), gmAmountWithdraw);
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams = createWithdrawParams();
        exchangeRouter.createWithdrawal(withdrawParams);
        depositedWethAmount = depositedWethAmount - _amount;
        uint256 usdcAmount = usdcToken.balanceOf(address(this));
        if(usdcAmount > minUSDCAmount){
            swapUSDCtoWETH(usdcAmount);
        }
        uint256 wethAmount = weth.balanceOf(address(this));
        weth.transfer(msg.sender, wethAmount);
    }

    function withdrawETH() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
    }

    function compound() external onlyOwner() {
        uint256 arbAmount = arbToken.balanceOf(address(this));
        if(arbAmount > minARBAmount){
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

    function updateExecutionFee(uint256 _executionFee) public onlyOwner{
        executionFee = _executionFee;
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
        depositParams.receiver = address(this);
        depositParams.callbackContract = address(this);
        depositParams.market = marketAddress;
        depositParams.minMarketTokens = 0;
        depositParams.shouldUnwrapNativeToken = false;
        depositParams.executionFee = executionFee;
        depositParams.callbackGasLimit = 0;
        depositParams.initialLongToken = address(weth);
        depositParams.initialShortToken = address(usdcToken);
        return depositParams;
    }

    function createWithdrawParams() internal view returns (IGMXExchangeRouter.CreateWithdrawalParams memory) {
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.receiver = address(this);
        withdrawParams.callbackContract = address(this);
        withdrawParams.market = marketAddress;
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = executionFee;
        withdrawParams.shouldUnwrapNativeToken = false;
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        return withdrawParams;
    }

    receive() external payable{}
}