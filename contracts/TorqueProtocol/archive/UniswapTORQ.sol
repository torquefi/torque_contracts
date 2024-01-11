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

contract UniswapTORQ is Ownable, ReentrancyGuard {

    struct Config {
        address torqToken;
        address wethToken;
        address positionManager;
        address vaultToken;
        address treasury;
        uint256 performanceFee;
        uint24 poolFee;
    }

    struct State {
        INonfungiblePositionManager positionManager;
        IERC20 torqToken;
        IERC20 wethToken;
        UniswapTORQ vaultToken;
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
        address _torqToken,
        address _wethToken,
        address _positionManager,
        address _treasury,
        uint256 _performanceFee,
        uint24 _poolFee
    ) {
        torqToken = IERC20(_torqToken);
        wethToken = IERC20(_wethToken);
        positionManager = INonfungiblePositionManager(_positionManager);
        treasury = _treasury;
        performanceFee = _performanceFee;
        poolFee = _poolFee;

        // Set range to match creation params
        tickLower = 116940;
        tickUpper = 224040;
    }

    function deposit(uint256 amount) external nonReentrant {
        torqToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 torqToConvert = amount / 2; 
        uint256 torqToKeep = amount - torqToConvert;
        uint256 wethAmount = convertTORQtoWETH(torqToConvert);
        torqToken.safeApprove(address(positionManager), torqToKeep);
        wethToken.safeApprove(address(positionManager), wethAmount);
        uint256 amount0Min = torqToKeep * (10000 - slippage) / 10000;
        uint256 amount1Min = wethAmount * (10000 - slippage) / 10000;
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(torqToken),
            token1: address(wethToken),
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: torqToKeep,
            amount1Desired: wethAmount,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp + 2 minutes
        });
        (tokenId, liquidity,,) = positionManager.mint(params);
        emit Deposited(torqToKeep, wethAmount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(liquidity >= amount, "Insufficient liquidity");
        (uint256 expectedTorqAmount, uint256 expectedWethAmount) = calculateExpectedTokenAmounts(amount);
        uint256 amount0Min = expectedTorqAmount * (10000 - slippage) / 10000;
        uint256 amount1Min = expectedWethAmount * (10000 - slippage) / 10000;
        amount0Min = expectedTorqAmount - (expectedTorqAmount * 0.5 / 100);
        amount1Min = expectedWethAmount - (expectedWethAmount * 0.5 / 100);
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
        uint256 convertedTorqAmount = convertWETHtoTORQ(amount1);
        amount0 = amount0.add(convertedTorqAmount);
        uint256 remainingWeth = amount1 - 0/* Amount of WETH converted to TORQ  PS CHECK*/;
        torqToken.safeTransfer(msg.sender, amount0);
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

    function calculateExpectedTokenAmounts(uint256 liquidityAmount) internal view returns (uint256 expectedTorqAmount, uint256 expectedWethAmount) {
        // Calculate the expected amount of TORQ and WETH tokens to receive
        return (calculatedTorqAmount, calculatedWethAmount);
    }

    function convertTORQtoWETH(uint256 torqAmount) internal returns (uint256) {
        // Swap TORQ for WETH
        return wethAmount;
    }

    function convertWETHtoTORQ(uint256 wethAmount) internal returns (uint256) {
        // Swap WETH for TORQ
        return torqAmount;
    }
}
