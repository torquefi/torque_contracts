// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import "../vToken.sol";

contract UniswapTORQ is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Uniswap V3 position manager
    INonfungiblePositionManager public positionManager;

    // TORQ and WETH token contracts
    IERC20 public torqToken;
    IERC20 public wethToken;

    // vToken contract for this vault
    UniswapTORQ public vaultToken;

    // Treasury and performance fee
    address public treasury;
    uint256 public performanceFee;

    // Uniswap pool details
    uint24 public poolFee;
    int24 public tickLower;
    int24 public tickUpper;

    // Liquidity position details
    uint256 public tokenId;
    uint256 public liquidity;

    // Events
    event LiquidityAdded(uint256 torqAmount, uint256 wethAmount);
    event LiquidityRemoved(uint256 torqAmount, uint256 wethAmount);
    event FeesCompounded();
    event PerformanceFeeClaimed();

    constructor(
        address _torqToken,
        address _wethToken,
        address _positionManager,
        address _vTokenAddress,
        address _treasury,
        uint256 _performanceFee,
        uint24 _poolFee
    ) {
        torqToken = IERC20(_torqToken);
        wethToken = IERC20(_wethToken);
        positionManager = INonfungiblePositionManager(_positionManager);
        vaultToken = UniswapTORQ(_vTokenAddress);
        treasury = _treasury;
        performanceFee = _performanceFee;
        poolFee = _poolFee;

        // Set range to match creation params
        tickLower = 116940;
        tickUpper = 224040;
    }

    function addLiquidity(uint256 torqAmount, uint256 wethAmount) external nonReentrant {
        torqToken.safeTransferFrom(msg.sender, address(this), torqAmount);
        wethToken.safeTransferFrom(msg.sender, address(this), wethAmount);

        torqToken.safeApprove(address(positionManager), torqAmount);
        wethToken.safeApprove(address(positionManager), wethAmount);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(torqToken),
            token1: address(wethToken),
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: torqAmount,
            amount1Desired: wethAmount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 15 minutes
        });

        (tokenId, liquidity,,) = positionManager.mint(params);

        // Mint corresponding vUNITORQ tokens
        vaultToken.mint(msg.sender, calculateVTokenAmount(torqAmount, wethAmount));

        emit LiquidityAdded(torqAmount, wethAmount);
    }

    function removeLiquidity(uint256 liquidityAmount) external nonReentrant {
        require(liquidityAmount > 0, "UniswapTORQ: Invalid liquidity amount");
        require(liquidity >= liquidityAmount, "UniswapTORQ: Insufficient liquidity");

        // Calculate minimum amounts based on max slippage of 0.5%
        uint256 amount0Min = torqAmount - (torqAmount * 0.5 / 100);
        uint256 amount1Min = wethAmount - (wethAmount * 0.5 / 100);

        // Define txn deadline
        uint256 deadline = block.timestamp + 2 minutes;

        // Decrease liquidity
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidityAmount,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: deadline
        });

        (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // Collect the withdrawn assets
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: uint128(amount0),
            amount1Max: uint128(amount1)
        });

        positionManager.collect(collectParams);

        // Update internal liquidity accounting
        liquidity -= liquidityAmount;

        // Burn the corresponding vUNITORQ tokens
        // Calculate amt of vUNITORQ tokens to burn (requires a valuation strategy).
        uint256 burnAmount = calculateVTokenBurnAmount(liquidityAmount);
        vaultToken.burn(address(this), burnAmount);

        // Transfer the collected TORQ and WETH back to the BoostTORQ contract
        torqToken.safeTransfer(msg.sender, amount0); // Transfer TORQ to BoostTORQ
        wethToken.safeTransfer(msg.sender, amount1); // Transfer WETH to BoostTORQ

        emit LiquidityRemoved(torqAmount, wethAmount);
    }

    function calculateVTokenAmount(uint256 torqAmount, uint256 wethAmount) internal view returns (uint256) {
        // Logic to calculate the amount of vUNITORQ tokens to mint based on provided liquidity
        // This might involve a valuation strategy for the liquidity provided
        // ...

        return vTokenAmount;
    }

    function setTickRange(int24 _tickLower, int24 _tickUpper) external onlyOwner {
        require(_newLower < _newUpper, "Invalid tick range");
        tickLower = _tickLower;
        tickUpper = _tickUpper;
    }
}
