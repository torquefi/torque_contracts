// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
import "../interfaces/IStargateRouter.sol";
import "../utils/LPStakingTime.sol";
import "../interfaces/IWETH9.sol";

import "../interfaces/ISwapRouter.sol";

/// @title StargateETH Contract
/// @notice Manages deposits, withdrawals, and compounding for WETH in the Stargate protocol.
contract StargateETH is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Wrapped ETH (WETH) token interface
    IWETH9 public weth;
    /// @notice WETH Staked Stargate (WETHSTG) token interface
    IERC20 public wethSTG;
    /// @notice Arbitrum token interface
    IERC20 public arbToken;
    /// @notice Stargate Router for ETH operations
    IStargateRouterETH public routerETH;
    /// @notice LP Staking Time interface for managing staking
    LPStakingTime public lpStakingTime;
    /// @notice Stargate Router interface
    IStargateRouter public router;
    /// @notice Swap Router for token swaps
    ISwapRouter public swapRouter;

    /// @notice Total WETH deposited in the contract
    uint256 public depositedWethAmount;
    /// @notice Address of the controller responsible for calling specific functions
    address public controller;
    /// @notice Minimum ARB amount for operations
    uint256 public minARBAmount = 1 ether;

    /// @notice Initializes the StargateETH contract
    /// @param weth_ WETH token address
    /// @param wethSTG_ WETH Staked Stargate token address
    /// @param arbToken_ ARB token address
    /// @param routerETH_ Stargate Router ETH address
    /// @param lpStakingTime_ LP Staking Time address
    /// @param router_ Stargate Router address
    /// @param swapRouter_ Swap Router address
    constructor(
        address payable weth_,
        address wethSTG_,
        address arbToken_,
        address payable routerETH_,
        address lpStakingTime_,
        address router_,
        address swapRouter_
    ) Ownable(msg.sender) {
        weth = IWETH9(weth_);
        wethSTG = IERC20(wethSTG_);
        arbToken = IERC20(arbToken_);
        routerETH = IStargateRouterETH(routerETH_);
        lpStakingTime = LPStakingTime(lpStakingTime_);
        router = IStargateRouter(router_);
        swapRouter = ISwapRouter(swapRouter_);
        depositedWethAmount = 0;
    }

    /// @notice Deposits WETH into the Stargate protocol
    /// @param _amount Amount of WETH to deposit
    function deposit(uint256 _amount) external {
        require(msg.sender == controller, "Only Controller can call this");
        require(weth.transferFrom(msg.sender, address(this), _amount), "Transfer Asset Failed");
        
        weth.withdraw(_amount);
        routerETH.addLiquidityETH{value: _amount}();

        uint256 wethSTGAmount = wethSTG.balanceOf(address(this));
        wethSTG.approve(address(lpStakingTime), wethSTGAmount);
        lpStakingTime.deposit(2, wethSTGAmount);
        
        depositedWethAmount = depositedWethAmount.add(_amount);
    }

    /// @notice Withdraws WETH from the Stargate protocol
    /// @param _amount Amount of WETH to withdraw
    function withdraw(uint256 _amount) external {
        require(msg.sender == controller, "Only Controller can call this");

        (uint256 realWethSTGDepositedAmount, ) = lpStakingTime.userInfo(2, address(this));
        uint256 withdrawAmount = _amount.mul(realWethSTGDepositedAmount).div(depositedWethAmount);
        
        lpStakingTime.withdraw(2, withdrawAmount);
        wethSTG.approve(address(router), withdrawAmount);
        
        uint256 withdrawETHAmount = router.instantRedeemLocal(13, withdrawAmount, address(this));
        weth.deposit{value: withdrawETHAmount}();
        
        require(weth.transfer(msg.sender, withdrawETHAmount), "Transfer Asset Failed");
        depositedWethAmount = depositedWethAmount.sub(_amount);
    }

    /// @notice Compounds ARB rewards into WETH
    function compound() external {
        require(msg.sender == controller, "Only Controller can call this");

        lpStakingTime.deposit(2, 0);
        uint256 arbAmount = arbToken.balanceOf(address(this));
        if (arbAmount > minARBAmount) {
            swapARBtoWETH(arbAmount);
            uint256 wethAmount = weth.balanceOf(address(this));
            require(weth.transfer(msg.sender, wethAmount), "Transfer Asset Failed");
        }
    }

    /// @notice Sets the controller address
    /// @param _controller The new controller address
    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    /// @notice Internal function to swap ARB to WETH
    /// @param arbAmount The amount of ARB to swap
    /// @return amountOut The amount of WETH received
    function swapARBtoWETH(uint256 arbAmount) internal returns (uint256 amountOut) {
        arbToken.approve(address(swapRouter), arbAmount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(arbToken),
            tokenOut: address(weth),
            fee: 0,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: arbAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        return swapRouter.exactInputSingle(params);
    }

    /// @notice Fallback function to receive ETH
    receive() external payable {}
}
