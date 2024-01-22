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
import "../interfaces/IWETH9.sol";

import "../../UniswapContracts/ISwapRouter.sol";

contract StargateETH is Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWETH9 public weth;
    IERC20 public wethSTG;
    IERC20 public arbToken;
    IStargateRouterETH public routerETH;
    IStargateLPStakingTime public lpStakingTime;
    IStargateRouter public router;
    ISwapRouter public swapRouter;
    
    constructor(address payable weth_, address wethSTG_, address arbToken_, address routerETH_, address lpStakingTime_, address router_, address swapRouter_){
        weth = IWETH9(weth_);
        wethSTG = IERC20(wethSTG_);
        arbToken = IERC20(arbToken_);
        routerETH = IStargateRouterETH(routerETH_);
        lpStakingTime = IStargateLPStakingTime(lpStakingTime_);
        router = IStargateRouter(router_);
        swapRouter = ISwapRouter(swapRouter_);
    }

    function deposit(uint256 _amount) payable external {
        weth.transferFrom(msg.sender, address(this), _amount);
        weth.withdraw(_amount);
        routerETH.addLiquidity{value: _amount}();
        wethSTG.approve(address(lpStakingTime), _amount);
        lpStakingTime.deposit(2, _amount);
    }

    function withdraw(uint256 _amount) external {
        lpStakingTime.withdraw(2, _amount);
        wethSTG.approve(address(router), _amount);
        router.instantRedeemLocal(13, _amount, address(this));
        weth.approve(address(msg.sender), _amount);
    }

    function swapARBtoWETH(uint256 arbAmount) internal {
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
        swapRouter.exactInputSingle(params);
    }
}