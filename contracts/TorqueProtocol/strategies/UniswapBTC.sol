// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract UniswapBTC is Ownable, ReentrancyGuard {

    using SafeMath for uint256;
    
    IERC20 public wbtcToken;
    IERC20 public wethToken;

    address treasury;
    uint256 performanceFee;
    uint24 poolFee;

    INonfungiblePositionManager positionManager;
    uint256 slippage;
    int24 tickLower;
    int24 tickUpper;
    uint256 tokenId;
    uint256 liquidity;

    event Deposited(uint256 amount);
    event Withdrawal(uint256 amount);

    constructor(
        address _wbtcToken,
        address _wethToken,
        address _positionManager,
        address _treasury,
        uint256 _performanceFee,
        uint24 _poolFee
    ) Ownable(msg.sender) {
        wbtcToken = IERC20(_wbtcToken);
        wethToken = IERC20(_wethToken);
        positionManager = INonfungiblePositionManager(_positionManager);
        treasury = _treasury;
        performanceFee = _performanceFee;
        poolFee = _poolFee;

        // Can set range here 
        tickLower = 0;
        tickUpper = 0;
    }

    function deposit(uint256 amount) external nonReentrant {
        wbtcToken.transferFrom(msg.sender, address(this), amount);
        uint256 wbtcToConvert = amount / 2; 
        uint256 wbtcToKeep = amount - wbtcToConvert;
        uint256 wethAmount = convertwbtctoWETH(wbtcToConvert);
        wbtcToken.approve(address(positionManager), wbtcToKeep);
        wethToken.approve(address(positionManager), wethAmount);
        uint256 amount0Min = wbtcToKeep * (10000 - slippage) / 10000;
        uint256 amount1Min = wethAmount * (10000 - slippage) / 10000;
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(wbtcToken),
            token1: address(wethToken),
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: wbtcToKeep,
            amount1Desired: wethAmount,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp + 2 minutes
        });
        (tokenId, liquidity,,) = positionManager.mint(params);
        emit Deposited(amount);
    }

    function withdraw(uint128 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(liquidity >= amount, "Insufficient liquidity");
        (uint256 expectedwbtcAmount, uint256 expectedWethAmount) = calculateExpectedTokenAmounts(amount);
        uint256 amount0Min = expectedwbtcAmount * (10000 - slippage) / 10000;
        uint256 amount1Min = expectedWethAmount * (10000 - slippage) / 10000;
        amount0Min = expectedwbtcAmount - (expectedwbtcAmount / 200);
        amount1Min = expectedWethAmount - (expectedWethAmount / 200);
        uint256 deadline = block.timestamp + 2 minutes;
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: amount,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: deadline
        });
        (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(decreaseLiquidityParams);
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: uint128(amount0),
            amount1Max: uint128(amount1)
        });
        positionManager.collect(collectParams);
        liquidity -= amount;
        uint256 convertedwbtcAmount = convertWETHtowbtc(amount1);
        amount0 = amount0.add(convertedwbtcAmount);
        uint256 remainingWeth = amount1 - 0/* Amount of WETH converted to wbtc PS CHECK */;
        wbtcToken.transfer(msg.sender, amount0);
        wethToken.transfer(msg.sender, remainingWeth);
        emit Withdrawal(amount);
    }

    function setTickRange(int24 _tickLower, int24 _tickUpper) external onlyOwner {
        require(_tickLower < _tickUpper, "Invalid tick range");
        tickLower = _tickLower;
        tickUpper = _tickUpper;
    }

    function setSlippage(uint256 _slippage) external onlyOwner {
        slippage = _slippage;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        performanceFee = _performanceFee;
    }

    function setPoolFee(uint24 _poolFee) external onlyOwner {
        poolFee = _poolFee;
    }

    function calculateExpectedTokenAmounts(uint256 liquidityAmount) internal view returns (uint256 expectedwbtcAmount, uint256 expectedWethAmount) {
        // Calculate the expected amount of WBTC and WETH tokens to receive
        return (0, 0);
    }

    function convertwbtctoWETH(uint256 wbtcAmount) internal returns (uint256) {
        // Swap WBTC for WETH
        return 0;
    }

    function convertWETHtowbtc(uint256 wethAmount) internal returns (uint256) {
        // Swap WETH for WBTC
        return 0;
    }
}
