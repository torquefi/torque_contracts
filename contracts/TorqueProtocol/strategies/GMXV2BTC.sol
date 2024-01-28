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
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./../interfaces/IGMX.sol";
import "../interfaces/IGMXExchangeRouter.sol";

contract GMXV2BTC is Ownable, ReentrancyGuard {
    IERC20 public wbtcGMX;
    IERC20 public gmToken;
    IERC20 public usdcToken;
    IERC20 public arbToken;

    address marketAddress;
    address depositVault;
    address withdrawalVault;
    address router;

    uint256 public depositedBTCAmount;
    uint256 public executionFee; 
    uint256 minUSDCAmount = 0;
    
    IGMXExchangeRouter public immutable gmxExchange;
    ISwapRouter public immutable swapRouter;
    
    address private constant UNISWAP_V3_ROUTER = 0x2f5e87C9312fa29aed5c179E456625D79015299c;

    constructor(
        address _wbtc,
        address gmToken_, 
        address usdcToken_, 
        address arbToken_, 
        address payable exchangeRouter_, 
        address swapRouter_, 
        address depositVault_, 
        address withdrawalVault_, 
        address router_) Ownable(msg.sender) {
            wbtcGMX = IERC20(_wbtc);
            gmToken = IERC20(gmToken_);
            usdcToken = IERC20(usdcToken_);
            arbToken = IERC20(arbToken_);
            gmxExchange = IGMXExchangeRouter(exchangeRouter_);
            swapRouter = ISwapRouter(swapRouter_);
            depositVault = depositVault_;
            withdrawalVault = withdrawalVault_;
            router = router_;
            executionFee = 1000000000000000;
    }

    function deposit(uint256 _amount) external payable {
        require(msg.value >= executionFee, "You must pay GMX v2 execution fee");
        gmxExchange.sendWnt{value: executionFee}(address(depositVault), executionFee);
        wbtcGMX.transferFrom(msg.sender, address(this), _amount);
        wbtcGMX.approve(address(router), _amount);
        gmxExchange.sendTokens(address(wbtcGMX), address(depositVault), _amount);
        IGMXExchangeRouter.CreateDepositParams memory depositParams = createDepositParams();
        gmxExchange.createDeposit(depositParams);
        depositedBTCAmount = depositedBTCAmount + _amount;
    }

    function withdraw(uint256 _amount) external payable onlyOwner() {
        require(msg.value >= executionFee, "You must pay GMX v2 execution fee");
        gmxExchange.sendWnt{value: executionFee}(address(withdrawalVault), executionFee);
        uint256 gmAmountWithdraw = _amount * gmToken.balanceOf(address(this)) / depositedBTCAmount;
        gmToken.approve(address(router), gmAmountWithdraw);
        gmxExchange.sendTokens(address(gmToken), address(withdrawalVault), gmAmountWithdraw);
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams = createWithdrawParams();
        gmxExchange.createWithdrawal(withdrawParams);
        depositedBTCAmount = depositedBTCAmount - _amount;
        uint256 usdcAmount = usdcToken.balanceOf(address(this));
        if(usdcAmount > minUSDCAmount){
            swapUSDCtoWETH(usdcAmount);
        }
        uint256 btcAmount = wbtcGMX.balanceOf(address(this));
        wbtcGMX.transfer(msg.sender, btcAmount);
    }

    function _sendWnt(address _receiver, uint256 _amount) private {
        gmxExchange.sendWnt(_receiver, _amount);
    }

    function _sendTokens(address _token, address _receiver, uint256 _amount) private {
        gmxExchange.sendTokens(_token, _receiver, _amount);
    }

    function createDepositParams() internal view returns (IGMXExchangeRouter.CreateDepositParams memory) {
        IGMXExchangeRouter.CreateDepositParams memory depositParams;
        depositParams.callbackContract = address(this);
        depositParams.callbackGasLimit = 0;
        depositParams.executionFee = executionFee;
        depositParams.initialLongToken = address(wbtcGMX);
        depositParams.initialShortToken = address(usdcToken);
        depositParams.market = marketAddress;
        depositParams.shouldUnwrapNativeToken = false;
        depositParams.receiver = address(this);
        depositParams.minMarketTokens = 0;
        return depositParams;
    }

    function createWithdrawParams() internal view returns (IGMXExchangeRouter.CreateWithdrawalParams memory) {
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.callbackContract = address(this);
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = executionFee;
        withdrawParams.market = marketAddress;
        withdrawParams.shouldUnwrapNativeToken = false;
        withdrawParams.receiver = address(this);
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        return withdrawParams;
    }

    function swapUSDCtoWBTC(uint256 usdcAmount) internal {
        usdcToken.approve(address(swapRouter), usdcAmount);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdcToken),
                tokenOut: address(wbtcGMX),
                fee: 500, // Uniswap V3 0.05 WBTC/WETH pool
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: usdcAmount,
                amountOutMinimum: 99,
                sqrtPriceLimitX96: 0
            });

        swapRouter.exactInputSingle(params);
    }

    function updateExecutionFee(uint256 _executionFee) public onlyOwner{
        executionFee = _executionFee;
    }

    function swapUSDCtoWETH(uint256 usdcAmount) internal {
        usdcToken.approve(address(swapRouter), usdcAmount);
        ISwapRouter.ExactInputSingleParams memory params =  
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdcToken),
                tokenOut: address(wbtcGMX),
                fee: 0,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: usdcAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        swapRouter.exactInputSingle(params);
    }

    receive() external payable{}
}
