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

/// @title UniswapLINK Contract
/// @notice Manages LINK deposits, withdrawals, and liquidity interactions with Uniswap v3
contract UniswapLINK is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public linkToken;                     // LINK token interface
    IERC20 public wethToken;                      // WETH token interface
    ISwapRouter public swapRouter;                // Uniswap swap router

    address treasury;                             // Treasury address for fees
    uint256 performanceFee;                       // Performance fee percentage
    uint24 poolFee = 100;                        // Pool fee for swaps

    INonfungiblePositionManager positionManager; // Uniswap position manager
    uint256 slippage = 20;                       // Slippage for withdrawals
    uint128 liquiditySlippage = 10;              // Liquidity slippage for increases
    int24 tickLower = -887220;                   // Lower tick range for positions
    int24 tickUpper = 887220;                    // Upper tick range for positions
    uint256 tokenId;                             // Token ID for NFT position
    address controller;                           // Controller address managing the contract

    bool poolInitialised = false;                 // Status of the pool initialization

    event Deposited(uint256 amount);              // Event for deposits
    event Withdrawal(uint256 amount);              // Event for withdrawals

    /// @notice Initializes the UniswapLINK contract
    /// @param _linkToken Address of the LINK token
    /// @param _wethToken Address of the WETH token
    /// @param _positionManager Address of the Uniswap position manager
    /// @param _swapRouter Address of the Uniswap swap router
    /// @param _treasury Address of the treasury
    constructor(
        address _linkToken,
        address _wethToken,
        address _positionManager, 
        address _swapRouter,
        address _treasury
    ) Ownable(msg.sender) {
        linkToken = IERC20(_linkToken);
        wethToken = IERC20(_wethToken);
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);
        treasury = _treasury;
    }

    /// @notice Deposits LINK tokens and provides liquidity
    /// @param amount Amount of LINK to deposit
    function deposit(uint256 amount) external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");
        require(linkToken.transferFrom(msg.sender, address(this), amount), "Transfer Asset Failed");
        
        uint256 linkToConvert = amount / 2; 
        uint256 linkToKeep = amount.sub(linkToConvert);
        uint256 wethAmount = convertLinktoWETH(linkToConvert); // Convert half LINK to WETH

        // Approve tokens for position manager
        linkToken.approve(address(positionManager), linkToKeep);
        wethToken.approve(address(positionManager), wethAmount);

        uint256 amount0Min = wethAmount.mul(1000 - slippage).div(1000); // Minimum WETH amount
        uint256 amount1Min = linkToKeep.mul(1000 - slippage).div(1000); // Minimum LINK amount

        if (!poolInitialised) {
            INonfungiblePositionManager.MintParams memory params = createMintParams(linkToKeep, wethAmount, amount0Min, amount1Min);
            (tokenId,,,) = positionManager.mint(params); // Mint new position
            poolInitialised = true;
        } else {
            INonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = createIncreaseLiquidityParams(wethAmount, linkToKeep, amount0Min, amount1Min);
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

        uint256 convertedLinkAmount = convertWETHtoLink(amount0); // Convert WETH to LINK
        amount1 = amount1.add(convertedLinkAmount); // Total amount to send
        require(linkToken.transfer(msg.sender, amount1), "Transfer Asset Failed"); // Transfer LINK to user
        emit Withdrawal(amount);
    }

    /// @notice Compounds the earnings from the liquidity positions
    function compound() external {
        require(msg.sender == controller, "Only controller can call this!");
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (uint256 wethVal, ) = positionManager.collect(collectParams); // Collect WETH from position
        convertWETHtoLink(wethVal); // Convert WETH to LINK
        uint256 linkAmount = linkToken.balanceOf(address(this)); // Get total LINK balance
        require(linkToken.transfer(msg.sender, linkAmount), "Transfer Asset Failed"); // Transfer LINK to controller
    }

    /// @notice Sets the controller address
    /// @param _controller New controller address
    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    /// @notice Creates mint parameters for the position manager
    /// @param linkToKeep Amount of LINK to keep
    /// @param wethAmount Amount of WETH to provide
    /// @param amount0Min Minimum amount of WETH
    /// @param amount1Min Minimum amount of LINK
    /// @return Mint parameters for position manager
    function createMintParams(uint256 linkToKeep, uint256 wethAmount, uint256 amount0Min, uint256 amount1Min) internal view returns (INonfungiblePositionManager.MintParams memory) {
        return INonfungiblePositionManager.MintParams({
            token0: address(wethToken),
            token1: address(linkToken),
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: wethAmount,
            amount1Desired: linkToKeep,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp + 2 minutes
        });
    }

    /// @notice Creates increase liquidity parameters for the position manager
    /// @param wethAmount Amount of WETH to provide
    /// @param linkToKeep Amount of LINK to keep
    /// @param amount0Min Minimum amount of WETH
    /// @param amount1Min Minimum amount of LINK
    /// @return Increase liquidity parameters for position manager
    function createIncreaseLiquidityParams(uint256 wethAmount, uint256 linkToKeep, uint256 amount0Min, uint256 amount1Min) internal view returns (INonfungiblePositionManager.IncreaseLiquidityParams memory) {
        return INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: wethAmount,
            amount1Desired: linkToKeep,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp + 2 minutes
        });
    }

    /// @notice Sets the tick range for the liquidity position
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

    /// @notice Converts LINK tokens to WETH
    /// @param linkAmount Amount of LINK to convert
    /// @return Amount of WETH received
    function convertLinktoWETH(uint256 linkAmount) internal returns (uint256) {
        linkToken.approve(address(swapRouter), linkAmount);
        ISwapRouter.ExactInputSingleParams memory params =  
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(linkToken),
                tokenOut: address(wethToken),
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: linkAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        return swapRouter.exactInputSingle(params); // Execute swap
    }

    /// @notice Converts WETH to LINK tokens
    /// @param wethAmount Amount of WETH to convert
    /// @return Amount of LINK received
    function convertWETHtoLink(uint256 wethAmount) internal returns (uint256) {
        wethToken.approve(address(swapRouter), wethAmount);
        ISwapRouter.ExactInputSingleParams memory params =  
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(wethToken),
                tokenOut: address(linkToken),
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
