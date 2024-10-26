// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/// @title UniswapBTC - BTC Strategy using Uniswap V3
/// @notice This contract facilitates BTC management using Uniswap V3, enabling deposits, withdrawals, and compounding.
/// @dev Implements functionality for liquidity provision and management of Uniswap V3 positions.
contract UniswapBTC is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public wbtcToken; // WBTC token contract
    IERC20 public tbtcToken; // tBTC token contract
    ISwapRouter public swapRouter; // Uniswap V3 swap router

    address public treasury; // Treasury address for fee collection
    uint256 public performanceFee; // Performance fee percentage
    uint24 public poolFee = 500; // Pool fee for Uniswap V3 swaps

    INonfungiblePositionManager public positionManager; // Uniswap V3 position manager
    uint256 public slippage = 10; // Slippage tolerance for swaps (in basis points)
    uint128 public liquiditySlippage = 10; // Slippage tolerance for liquidity (in basis points)
    int24 public tickLower = -887220; // Lower tick for Uniswap V3 range
    int24 public tickUpper = 887220;  // Upper tick for Uniswap V3 range
    uint256 public tokenId; // Token ID for Uniswap V3 position
    address public controller; // Address of the controller with management rights

    bool public poolInitialised = false; // Indicates whether the liquidity pool is initialized

    /// @notice Event emitted when WBTC is deposited into the Uniswap V3 position.
    /// @param amount The amount of WBTC deposited.
    event Deposited(uint256 amount);

    /// @notice Event emitted when WBTC is withdrawn from the Uniswap V3 position.
    /// @param amount The amount of WBTC withdrawn.
    event Withdrawal(uint256 amount);

    /// @notice Initializes the UniswapBTC contract with required parameters.
    /// @param _wbtcToken Address of the WBTC token.
    /// @param _tbtcToken Address of the tBTC token.
    /// @param _positionManager Address of the Uniswap V3 position manager.
    /// @param _swapRouter Address of the Uniswap V3 swap router.
    /// @param _treasury Address of the treasury.
    constructor(
        address _wbtcToken,
        address _tbtcToken,
        address _positionManager, 
        address _swapRouter,
        address _treasury
    ) Ownable(msg.sender) {
        wbtcToken = IERC20(_wbtcToken);
        tbtcToken = IERC20(_tbtcToken);
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);
        treasury = _treasury;
    }

    /// @notice Deposits WBTC into the Uniswap V3 position.
    /// @param amount The amount of WBTC to deposit.
    /// @dev Requires controller permissions. The function divides WBTC into two parts:
    ///      one is kept as WBTC, the other is swapped to tBTC for liquidity provision.
    function deposit(uint256 amount) external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");
        require(wbtcToken.transferFrom(msg.sender, address(this), amount), "Transfer Asset Failed");

        uint256 wbtcToConvert = amount.div(2); // Convert half to tBTC
        uint256 wbtcToKeep = amount.sub(wbtcToConvert); // Keep half as WBTC
        uint256 tbtcAmount = convertwbtctotbtc(wbtcToConvert);

        // Approve tokens for position manager
        wbtcToken.approve(address(positionManager), wbtcToKeep);
        tbtcToken.approve(address(positionManager), tbtcAmount);

        uint256 amount0Min = wbtcToKeep.mul(1000 - slippage).div(1000);
        uint256 amount1Min = tbtcAmount.mul(1000 - slippage).div(1000);

        // Create or increase liquidity position
        if (!poolInitialised) {
            INonfungiblePositionManager.MintParams memory params = createMintParams(wbtcToKeep, tbtcAmount, amount0Min, amount1Min);
            (tokenId,,,) = positionManager.mint(params);
            poolInitialised = true;
        } else {
            INonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = createIncreaseLiquidityParams(wbtcToKeep, tbtcAmount, amount0Min, amount1Min);
            positionManager.increaseLiquidity(increaseLiquidityParams);
        }

        emit Deposited(amount);
    }

    /// @notice Withdraws WBTC from the Uniswap V3 position based on provided liquidity.
    /// @param amount The amount of WBTC to withdraw.
    /// @param totalAsset The total assets under management by the contract.
    /// @dev Requires controller permissions. Liquidity is decreased proportionally.
    function withdraw(uint128 amount, uint256 totalAsset) external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");
        require(amount > 0, "Invalid amount");

        // Fetch current liquidity
        (,,,,,,,uint128 liquidity,,,,) = positionManager.positions(tokenId);
        uint256 deadline = block.timestamp + 2 minutes;

        // Calculate proportional liquidity to withdraw
        uint128 liquidityAmount = uint128(liquidity).mul(amount).div(uint128(totalAsset));
        liquidityAmount = liquidityAmount.mul(1000 - liquiditySlippage).div(1000);

        // Prepare to decrease liquidity
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidityAmount,
            amount0Min: 0,
            amount1Min: 0,
            deadline: deadline
        });

        // Decrease liquidity and collect tokens
        (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(decreaseLiquidityParams);
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: uint128(amount0),
            amount1Max: uint128(amount1)
        });
        positionManager.collect(collectParams);

        // Convert tBTC to WBTC
        uint256 convertedwbtcAmount = convertTBTCtowbtc(amount1);
        amount0 = amount0.add(convertedwbtcAmount);

        require(wbtcToken.transfer(msg.sender, amount0), "Transfer Asset Failed");

        emit Withdrawal(amount);
    }

    /// @notice Compounds collected fees by converting tBTC to WBTC.
    /// @dev Only callable by the controller.
    function compound() external {
        require(msg.sender == controller, "Only controller can call this!");

        // Collect tokens from Uniswap V3 position
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        (, uint256 tbtcVal) = positionManager.collect(collectParams);

        // Convert collected tBTC to WBTC
        convertTBTCtowbtc(tbtcVal);

        uint256 wbtcAmount = wbtcToken.balanceOf(address(this));
        require(wbtcToken.transfer(msg.sender, wbtcAmount), "Transfer Asset Failed");
    }

    /// @notice Converts WBTC to tBTC using Uniswap V3.
    /// @param wbtcAmount The amount of WBTC to convert.
    /// @return The amount of tBTC received.
    function convertwbtctotbtc(uint256 wbtcAmount) internal returns (uint256) {
        wbtcToken.approve(address(swapRouter), wbtcAmount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(wbtcToken),
            tokenOut: address(tbtcToken),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: wbtcAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        return swapRouter.exactInputSingle(params);
    }

    /// @notice Converts tBTC to WBTC using Uniswap V3.
    /// @param tbtcAmount The amount of tBTC to convert.
    /// @return The amount of WBTC received.
    function convertTBTCtowbtc(uint256 tbtcAmount) internal returns (uint256) {
        tbtcToken.approve(address(swapRouter), tbtcAmount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(tbtcToken),
            tokenOut: address(wbtcToken),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: tbtcAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        return swapRouter.exactInputSingle(params);
    }

    /// @notice Sets the controller address for managing the contract.
    /// @param _controller The new controller address.
    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    /// @notice Allows owner to withdraw any ERC20 token from the contract.
    /// @param _amount The amount to withdraw.
    /// @param _asset The address of the token to withdraw.
    function withdraw(uint256 _amount, address _asset) external onlyOwner {
        IERC20(_asset).transfer(msg.sender, _amount);
    }
}
