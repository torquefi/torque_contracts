// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

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

import "../interfaces/IStargateLPStakingTime.sol";
import "../interfaces/IStargateRouterETH.sol";
import "../../StargateContracts/interfaces/IStargateRouter.sol";
import "../../StargateContracts/LPStakingTime.sol";
import "../interfaces/IWETH9.sol";

import "../../UniswapContracts/ISwapRouter.sol";

contract StargateETH is Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWETH9 public weth;
    IERC20 public wethSTG;
    IERC20 public arbToken;
    IStargateRouterETH public routerETH;
    LPStakingTime public lpStakingTime;
    IStargateRouter public router;
    ISwapRouter public swapRouter;

    uint256 public depositedWethAmount;
    uint256 minARBAmount = 1000000000000000000;
    
    constructor(address payable weth_, address wethSTG_, address arbToken_, address payable routerETH_, address lpStakingTime_, address router_, address swapRouter_){
        weth = IWETH9(weth_);
        wethSTG = IERC20(wethSTG_);
        arbToken = IERC20(arbToken_);
        routerETH = IStargateRouterETH(routerETH_);
        lpStakingTime = LPStakingTime(lpStakingTime_);
        router = IStargateRouter(router_);
        swapRouter = ISwapRouter(swapRouter_);
        depositedWethAmount = 0;
    }

    function deposit(uint256 _amount) external {
        weth.transferFrom(msg.sender, address(this), _amount);
        weth.withdraw(_amount);
        routerETH.addLiquidityETH{value: _amount}();
        uint256 wethSTGAmount = wethSTG.balanceOf(address(this));
        wethSTG.approve(address(lpStakingTime), wethSTGAmount);
        lpStakingTime.deposit(2, wethSTGAmount);
        depositedWethAmount = depositedWethAmount + _amount;
    }

    function withdraw(uint256 _amount) external onlyOwner() {
        (uint256 realWethSTGDepositedAmount, ) = lpStakingTime.userInfo(2, address(this));
        uint256 withdrawAmount = _amount * realWethSTGDepositedAmount / depositedWethAmount;
        lpStakingTime.withdraw(2, withdrawAmount);
        wethSTG.approve(address(router), withdrawAmount);
        router.instantRedeemLocal(13, withdrawAmount, address(this));
        uint256 wethAmount = weth.balanceOf(address(this));
        weth.transfer(address(msg.sender), wethAmount);
        depositedWethAmount = depositedWethAmount - _amount;
    }

    function compound() external onlyOwner() {
        lpStakingTime.deposit(2, 0);
        uint256 arbAmount = arbToken.balanceOf(address(this));
        if(arbAmount > minARBAmount){
            swapARBtoWETH(arbAmount);
            uint256 wethAmount = weth.balanceOf(address(this));
            weth.transfer(msg.sender, wethAmount);
        }
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

    receive() external payable{}
}