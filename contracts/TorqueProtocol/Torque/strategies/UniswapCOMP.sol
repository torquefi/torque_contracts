// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract UniswapCOMP is Ownable, ReentrancyGuard {
    
    struct Config {
        address compToken;
        address wethToken;
        address positionManager;
        address vaultToken;
        address treasury;
        uint256 performanceFee;
        uint24 poolFee;
    }

    struct State {
        INonfungiblePositionManager positionManager;
        IERC20 compToken;
        IERC20 wethToken;
        Uniswapcomp vaultToken;
        address treasury;
        uint256 slippage;
        uint24 poolFee;
        int24 tickLower;
        int24 tickUpper;
        uint256 tokenId;
        uint256 liquidity;
    }

    event Deposited(uint256 amount);
    event Withdrawal(uint256 amount);

    Config public config;
    State public state;

    constructor(
        address _compToken,
        address _wethToken,
        address _positionManager,
        address _treasury,
        uint256 _performanceFee,
        uint24 _poolFee
    ) {
        compToken = IERC20(_compToken);
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
        compToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 compToConvert = amount / 2; 
        uint256 compToKeep = amount - compToConvert;
        uint256 wethAmount = convertcomptoWETH(compToConvert);
        compToken.safeApprove(address(positionManager), compToKeep);
        wethToken.safeApprove(address(positionManager), wethAmount);
        uint256 amount0Min = compToKeep * (10000 - slippage) / 10000;
        uint256 amount1Min = wethAmount * (10000 - slippage) / 10000;
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(compToken),
            token1: address(wethToken),
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: compToKeep,
            amount1Desired: wethAmount,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp + 2 minutes
        });
        (tokenId, liquidity,,) = positionManager.mint(params);
        emit Deposited(compToKeep, wethAmount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(liquidity >= amount, "Insufficient liquidity");
        (uint256 expectedcompAmount, uint256 expectedWethAmount) = calculateExpectedTokenAmounts(amount);
        uint256 amount0Min = expectedcompAmount * (10000 - slippage) / 10000;
        uint256 amount1Min = expectedWethAmount * (10000 - slippage) / 10000;
        uint256 amount0Min = expectedcompAmount - (expectedcompAmount * 0.5 / 100);
        uint256 amount1Min = expectedWethAmount - (expectedWethAmount * 0.5 / 100);
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
        uint256 convertedcompAmount = convertWETHtocomp(amount1);
        amount0 = amount0.add(convertedcompAmount);
        uint256 remainingWeth = amount1 - /* Amount of WETH converted to comp */;
        compToken.safeTransfer(msg.sender, amount0);
        wethToken.safeTransfer(msg.sender, remainingWeth);
        emit Withdrawal(amount0, remainingWeth);
    }

    function setTickRange(int24 _tickLower, int24 _tickUpper) external onlyOwner {
        require(_newLower < _newUpper, "Invalid tick range");
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

    function calculateExpectedTokenAmounts(uint256 liquidityAmount) internal view returns (uint256 expectedcompAmount, uint256 expectedWethAmount) {
        // Calculate the expected amount of COMP and WETH tokens to receive
        return (calculatedcompAmount, calculatedWethAmount);
    }

    function convertcomptoWETH(uint256 compAmount) internal returns (uint256) {
        // Swap COMP for WETH
        return wethAmount;
    }

    function convertWETHtocomp(uint256 wethAmount) internal returns (uint256) {
        // Swap WETH for COMP
        return compAmount;
    }
}
