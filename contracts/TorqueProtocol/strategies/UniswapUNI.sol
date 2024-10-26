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

/// @title UniswapUNI Contract
/// @notice Manages UNI deposits, withdrawals, and liquidity interactions with Uniswap v3
contract UniswapUNI is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public uniToken;                            // UNI token interface
    IERC20 public wethToken;                           // WETH token interface
    ISwapRouter public swapRouter;                     // Uniswap swap router

    address treasury;                                  // Treasury address for fees
    uint256 public performanceFee;                    // Performance fee percentage
    uint24 public poolFee = 100;                      // Pool fee for swaps

    INonfungiblePositionManager public positionManager; // Uniswap position manager
    uint256 public slippage = 20;                     // Slippage for withdrawals
    uint128 public liquiditySlippage = 10;            // Liquidity slippage for increases
    int24 public tickLower = -887220;                 // Lower tick range for positions
    int24 public tickUpper = 887220;                  // Upper tick range for positions
    uint256 public tokenId;                            // Token ID for NFT position
    address public controller;                          // Controller address managing the contract

    bool public poolInitialised = false;               // Status of the pool initialization

    event Deposited(uint256 amount);                  // Event for deposits
    event Withdrawal(uint256 amount);                  // Event for withdrawals

    /// @notice Initializes the UniswapUNI contract
    /// @param _uniToken Address of the UNI token
    /// @param _wethToken Address of the WETH token
    /// @param _positionManager Address of the Uniswap position manager
    /// @param _swapRouter Address of the Uniswap swap router
    /// @param _treasury Address of the treasury
    constructor(
        address _uniToken,
        address _wethToken,
        address _positionManager, 
        address _swapRouter,
        address _treasury
    ) Ownable(msg.sender) {
        uniToken = IERC20(_uniToken);
        wethToken = IERC20(_wethToken);
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);
        treasury = _treasury;
    }

    /// @notice Deposits UNI tokens and provides liquidity
    /// @param amount Amount of UNI to deposit
    function deposit(uint256 amount) external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");
        require(uniToken.transferFrom(msg.sender, address(this), amount), "Transfer Asset Failed");

        uint256 uniToConvert = amount / 2; 
        uint256 uniToKeep = amount.sub(uniToConvert);
        uint256 wethAmount = convertUnitoWETH(uniToConvert); // Convert half UNI to WETH

        // Approve tokens for position manager
        uniToken.approve(address(positionManager), uniToKeep);
        wethToken.approve(address(positionManager), wethAmount);

        uint256 amount0Min = wethAmount.mul(1000 - slippage).div(1000); // Minimum WETH amount
        uint256 amount1Min = uniToKeep.mul(1000 - slippage).div(1000); // Minimum UNI amount

        if (!poolInitialised) {
            INonfungiblePositionManager.MintParams memory params = createMintParams(wethAmount, uniToKeep, amount0Min, amount1Min);
            (tokenId,,,) = positionManager.mint(params); // Mint new position
            poolInitialised = true;
        } else {
            INonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = createIncreaseLiquidityParams(wethAmount, uniToKeep, amount0Min, amount1Min);
            positionManager.increaseLiquidity(increaseLiquidityParams); // Increase liquidity if already initialized
        }
        emit Deposited(amount);
    }

    /// @notice Withdraws liquidity based on the amount and total assets
    /// @param amount Amount of liquidity to withdraw
    /// @param totalAsset Total assets in the pool
    function withdraw(uint128 amount, uint256 totalAsset) external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");
        require(amount > 0, "Invalid amount");

        (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId); // Get liquidity info
        uint256 deadline = block.timestamp + 2 minutes; // Set deadline for transaction

        uint128 liquidtyAmount = uint128(liquidity).mul(amount).div(uint128(totalAsset)); // Calculate liquidity to withdraw
        liquidtyAmount = liquidtyAmount.mul(1000 - liquiditySlippage).div(1000); // Adjust for slippage

        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidtyAmount,
            amount0Min: 0,
            amount1Min: 0,
            deadline: deadline
        });

        (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(decreaseLiquidityParams); // Decrease liquidity
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: uint128(amount0),
            amount1Max: uint128(amount1)
        });

        positionManager.collect(collectParams); // Collect fees

        uint256 convertedUniAmount = convertWETHtoUni(amount0); // Convert WETH to UNI
        amount1 = amount1.add(convertedUniAmount); // Total amount to send
        require(uniToken.transfer(msg.sender, amount1), "Transfer Asset Failed"); // Transfer UNI to user
        emit Withdrawal(amount);
    }

    /// @notice Compounds the earnings from the liquidity positions
    function compound() external {
        require(msg.sender == controller, "Only controller can call this!");
        if (!poolInitialised) {
            return; // No action if the pool is not initialized
        }
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (uint256 wethVal, ) = positionManager.collect(collectParams); // Collect WETH from position
        convertWETHtoUni(wethVal); // Convert WETH to UNI
        uint256 uniAmount = uniToken.balanceOf(address(this)); // Get total UNI balance
        require(uniToken.transfer(msg.sender, uniAmount), "Transfer Asset Failed"); // Transfer UNI to controller
    }

    /// @notice Sets the controller address
    /// @param _controller New controller address
    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    /// @notice Creates mint parameters for the position manager
    /// @param wethAmount Amount of WETH to provide
    /// @param uniToKeep Amount of UNI to keep
    /// @param amount0Min Minimum amount of WETH
    /// @param amount1Min Minimum amount of UNI
    /// @return Mint parameters for position manager
    function createMintParams(uint256 wethAmount, uint256 uniToKeep, uint256 amount0Min, uint256 amount1Min) internal view returns (INonfungiblePositionManager.MintParams memory) {
        return INonfungiblePositionManager.MintParams({
            token0: address(wethToken),
            token1: address(uniToken),
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: wethAmount,
            amount1Desired: uniToKeep,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp + 2 minutes
        });
    }

    /// @notice Creates increase liquidity parameters for the position manager
    /// @param wethAmount Amount of WETH to add
    /// @param uniToKeep Amount of UNI to keep
    /// @param amount0Min Minimum amount of WETH
    /// @param amount1Min Minimum amount of UNI
    /// @return Increase liquidity parameters for position manager
    function createIncreaseLiquidityParams(uint256 wethAmount, uint256 uniToKeep, uint256 amount0Min, uint256 amount1Min) internal view returns (INonfungiblePositionManager.IncreaseLiquidityParams memory) {
        return INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: wethAmount,
            amount1Desired: uniToKeep,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp + 2 minutes
        });
    }

    /// @notice Sets the tick range for liquidity positions
    /// @param _tickLower New lower tick range
    /// @param _tickUpper New upper tick range
    function setTickRange(int24 _tickLower, int24 _tickUpper) external onlyOwner {
        require(_tickLower < _tickUpper, "Invalid tick range");
        tickLower = _tickLower;
        tickUpper = _tickUpper;
    }

    /// @notice Sets the slippage for deposits and withdrawals
    /// @param _slippage New slippage percentage
    function setSlippage(uint256 _slippage) external onlyOwner {
        slippage = _slippage;
    }

    /// @notice Sets the liquidity slippage for increases
    /// @param _slippage New liquidity slippage percentage
    function setLiquiditySlippage(uint128 _slippage) external onlyOwner {
        liquiditySlippage = _slippage;
    }

    /// @notice Sets the treasury address for fee withdrawals
    /// @param _treasury New treasury address
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /// @notice Sets the performance fee for the treasury
    /// @param _performanceFee New performance fee percentage
    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        performanceFee = _performanceFee;
    }

    /// @notice Sets the pool fee for Uniswap
    /// @param _poolFee New pool fee
    function setPoolFee(uint24 _poolFee) external onlyOwner {
        poolFee = _poolFee;
    }

    /// @notice Converts UNI tokens to WETH
    /// @param uniAmount Amount of UNI to convert
    /// @return Amount of WETH received
    function convertUnitoWETH(uint256 uniAmount) internal returns (uint256) {
        uniToken.approve(address(swapRouter), uniAmount);
        ISwapRouter.ExactInputSingleParams memory params =  
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(uniToken),
                tokenOut: address(wethToken),
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: uniAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        return swapRouter.exactInputSingle(params); // Execute swap
    }

    /// @notice Converts WETH to UNI tokens
    /// @param wethAmount Amount of WETH to convert
    /// @return Amount of UNI received
    function convertWETHtoUni(uint256 wethAmount) internal returns (uint256) {
        wethToken.approve(address(swapRouter), wethAmount);
        ISwapRouter.ExactInputSingleParams memory params =  
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(wethToken),
                tokenOut: address(uniToken),
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: wethAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        return swapRouter.exactInputSingle(params); // Execute swap
    }

    /// @notice Fallback function to receive ETH
    receive() external payable {}
}
