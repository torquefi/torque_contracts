// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title TorqueSwap Contract
/// @notice This contract facilitates single-hop, multi-hop, multi-token swaps, and split swaps using Uniswap V3.
/// @dev It includes both single-token and multi-token swapping functions, integrates with Uniswap V3, and supports a swap fee.
contract TorqueSwap is Ownable {
    /// @notice Uniswap V3 Swap Router contract
    ISwapRouter private constant router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// @notice Address of the treasury where fees are collected
    address public treasury;

    /// @notice Swap fee in basis points (e.g., 100 = 1%)
    uint public TorqueSwapFee = 0;

    /// @notice Constructor to set the initial treasury address
    /// @param _treasury Initial treasury address
    constructor(address _treasury) Ownable() {
        treasury = _treasury;
    }

    /// @notice Swaps a single token to another token using a single-hop on Uniswap V3
    /// @dev Uses Uniswap's exactInputSingle for swapping
    /// @param amountIn The amount of input tokens to swap
    /// @param amountOutMin The minimum output tokens expected after the swap
    /// @param _swapFee The fee tier of the Uniswap pool (e.g., 3000 for 0.3%)
    /// @param _tokenIn The address of the token being swapped from
    /// @param _tokenOut The address of the token being swapped to
    function swapExactInputSingleHop(
        uint amountIn,
        uint amountOutMin,
        uint24 _swapFee,
        address _tokenIn,
        address _tokenOut
    ) external {
        IERC20 tokenIn = IERC20(_tokenIn);

        // Calculate and transfer the swap fee to the treasury
        uint256 swapFeeAmt = (amountIn * TorqueSwapFee) / 1000;
        require(tokenIn.transferFrom(msg.sender, treasury, swapFeeAmt), "Fee transfer failed");

        // Adjust the input amount after fee deduction
        amountIn = amountIn - swapFeeAmt;
        require(tokenIn.transferFrom(msg.sender, address(this), amountIn), "Token transfer failed");

        // Approve Uniswap router to spend the token
        tokenIn.approve(address(router), amountIn);

        // Set up the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: _swapFee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });

        // Perform the swap
        router.exactInputSingle(params);
    }

    /// @notice Swaps a single token to another token using multi-hop on Uniswap V3
    /// @dev Uses Uniswap's exactInput for multi-hop swaps
    /// @param amountIn The amount of input tokens to swap
    /// @param amountOutMin The minimum output tokens expected after the swap
    /// @param path The encoded path of tokens for the swap (tokenIn -> intermediate -> tokenOut)
    /// @param _tokenIn The address of the input token
    function swapExactInputMultiHop(
        uint amountIn,
        uint amountOutMin,
        bytes memory path,
        address _tokenIn
    ) external {
        IERC20 tokenIn = IERC20(_tokenIn);

        // Calculate and transfer the swap fee to the treasury
        uint256 swapFeeAmt = (amountIn * TorqueSwapFee) / 1000;
        require(tokenIn.transferFrom(msg.sender, treasury, swapFeeAmt), "Fee transfer failed");

        // Adjust the input amount after fee deduction
        amountIn = amountIn - swapFeeAmt;
        require(tokenIn.transferFrom(msg.sender, address(this), amountIn), "Token transfer failed");

        // Approve Uniswap router to spend the token
        tokenIn.approve(address(router), amountIn);

        // Set up the swap parameters
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin
        });

        // Perform the swap
        router.exactInput(params);
    }

    /// @notice Swaps multiple tokens into a single output token
    /// @dev Iterates through each input token and performs single-hop swaps to the output token
    /// @param inputTokens Array of input tokens to swap from
    /// @param inputAmounts Array of input token amounts corresponding to each input token
    /// @param outputToken The token to swap into
    /// @param minOutputAmount Minimum amount of output tokens expected
    /// @param swapFees Array of Uniswap pool fees for each input token
    function swapMultipleTokensForSingleToken(
        address[] calldata inputTokens,
        uint256[] calldata inputAmounts,
        address outputToken,
        uint256 minOutputAmount,
        uint24[] calldata swapFees
    ) external {
        require(inputTokens.length == inputAmounts.length, "Mismatched input arrays");
        require(inputTokens.length == swapFees.length, "Mismatched fees arrays");

        uint256 totalOutputAmount = 0;

        // Iterate through each input token and perform swaps
        for (uint256 i = 0; i < inputTokens.length; i++) {
            IERC20 tokenIn = IERC20(inputTokens[i]);
            uint256 amountIn = inputAmounts[i];

            // Calculate and transfer the swap fee to the treasury
            uint256 swapFeeAmt = (amountIn * TorqueSwapFee) / 1000;
            require(tokenIn.transferFrom(msg.sender, treasury, swapFeeAmt), "Fee transfer failed");

            // Adjust the input amount after fee deduction
            amountIn = amountIn - swapFeeAmt;
            require(tokenIn.transferFrom(msg.sender, address(this), amountIn), "Token transfer failed");

            // Approve Uniswap router to spend the token
            tokenIn.approve(address(router), amountIn);

            // Set up the swap parameters
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: inputTokens[i],
                tokenOut: outputToken,
                fee: swapFees[i],
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            // Perform the swap
            uint256 outputAmount = router.exactInputSingle(params);
            totalOutputAmount += outputAmount;
        }

        // Ensure total output meets minimum requirement
        require(totalOutputAmount >= minOutputAmount, "Slippage too high");

        // Transfer the accumulated output to the sender
        IERC20(outputToken).transfer(msg.sender, totalOutputAmount);
    }

    /// @notice Swaps a single token into multiple output tokens
    /// @dev Iterates through each output token and performs single-hop swaps from the input token
    /// @param inputToken The token to swap from
    /// @param inputAmount The total amount of input token to swap
    /// @param outputTokens Array of output tokens to swap into
    /// @param minOutputAmounts Array of minimum amounts expected for each output token
    /// @param swapFees Array of Uniswap pool fees for each output token
    function swapSingleTokenForMultipleTokens(
        address inputToken,
        uint256 inputAmount,
        address[] calldata outputTokens,
        uint256[] calldata minOutputAmounts,
        uint24[] calldata swapFees
    ) external {
        require(outputTokens.length == minOutputAmounts.length, "Mismatched output arrays");
        require(outputTokens.length == swapFees.length, "Mismatched fees arrays");

        IERC20 tokenIn = IERC20(inputToken);

        // Calculate and transfer the swap fee to the treasury
        uint256 swapFeeAmt = (inputAmount * TorqueSwapFee) / 1000;
        require(tokenIn.transferFrom(msg.sender, treasury, swapFeeAmt), "Fee transfer failed");

        // Adjust the input amount after fee deduction
        inputAmount = inputAmount - swapFeeAmt;
        require(tokenIn.transferFrom(msg.sender, address(this), inputAmount), "Token transfer failed");

        // Approve Uniswap router to spend the token
        tokenIn.approve(address(router), inputAmount);

        // Iterate through each output token and perform swaps
        for (uint256 i = 0; i < outputTokens.length; i++) {
            uint256 amountInForSwap = inputAmount / outputTokens.length;

            // Set up the swap parameters
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: inputToken,
                tokenOut: outputTokens[i],
                fee: swapFees[i],
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountInForSwap,
                amountOutMinimum: minOutputAmounts[i],
                sqrtPriceLimitX96: 0
            });

            // Perform the swap
            router.exactInputSingle(params);
        }
    }

    /// @notice Updates the swap fee in basis points
    /// @dev Only the contract owner can call this function
    /// @param _fee The new swap fee in basis points (e.g., 100 = 1%)
    function updateTorqueSwapFee(uint _fee) external onlyOwner {
        TorqueSwapFee = _fee;
    }

    /// @notice Updates the treasury address
    /// @dev Only the contract owner can call this function
    /// @param _treasury The new treasury address
    function updateTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}
