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

contract TorqueMultiSwap is Ownable {
    ISwapRouter private constant router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address public treasury;
    uint public TorqueSwapFee = 0;

    constructor(address _treasury) Ownable(msg.sender) {
        treasury = _treasury;
    }

    /// @notice Swap multiple tokens into a single token
    /// @param inputTokens Array of input tokens to swap from
    /// @param inputAmounts Array of input token amounts corresponding to each input token
    /// @param outputToken The token to swap into
    /// @param minOutputAmount Minimum amount of output tokens expected
    /// @param swapFees Array of fees for each Uniswap pool corresponding to each input token
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

        for (uint256 i = 0; i < inputTokens.length; i++) {
            IERC20 tokenIn = IERC20(inputTokens[i]);
            uint256 amountIn = inputAmounts[i];
            uint256 swapFeeAmt = amountIn * TorqueSwapFee / 1000; // Calculating fee in basis points

            // Transfer the fee to the treasury
            require(tokenIn.transferFrom(msg.sender, treasury, swapFeeAmt), "Transfer fee failed");

            // Adjust the input amount after fee deduction
            amountIn = amountIn - swapFeeAmt;
            require(tokenIn.transferFrom(msg.sender, address(this), amountIn), "Token transfer failed");

            // Approve Uniswap router to spend the token
            tokenIn.approve(address(router), amountIn);

            // Define the swap path (inputToken -> outputToken)
            address;
            path[0] = inputTokens[i];
            path[1] = outputToken;

            // Perform the swap
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: inputTokens[i],
                tokenOut: outputToken,
                fee: swapFees[i],
                recipient: address(this), // Contract receives the output
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0, // No minimum to allow for gradual accumulation
                sqrtPriceLimitX96: 0
            });

            uint256[] memory amounts = router.exactInputSingle(params);
            totalOutputAmount += amounts[1]; // Accumulate total output
        }

        // Ensure the total output is above the minimum required
        require(totalOutputAmount >= minOutputAmount, "Slippage too high");

        // Transfer the total output to the user
        IERC20(outputToken).transfer(msg.sender, totalOutputAmount);
    }

    /// @notice Swap a single token into multiple tokens
    /// @param inputToken The token to swap from
    /// @param inputAmount The amount of input token to swap
    /// @param outputTokens Array of output tokens to swap into
    /// @param minOutputAmounts Array of minimum amounts expected for each output token
    /// @param swapFees Array of fees for each Uniswap pool corresponding to each output token
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
        uint256 swapFeeAmt = inputAmount * TorqueSwapFee / 1000; // Calculating fee in basis points

        // Transfer the fee to the treasury
        require(tokenIn.transferFrom(msg.sender, treasury, swapFeeAmt), "Transfer fee failed");

        // Adjust the input amount after fee deduction
        inputAmount = inputAmount - swapFeeAmt;
        require(tokenIn.transferFrom(msg.sender, address(this), inputAmount), "Token transfer failed");

        // Approve Uniswap router to spend the input token
        tokenIn.approve(address(router), inputAmount);

        for (uint256 i = 0; i < outputTokens.length; i++) {
            uint256 amountInForSwap = inputAmount / outputTokens.length; // Split inputAmount evenly
            address;
            path[0] = inputToken;
            path[1] = outputTokens[i];

            // Perform the swap
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: inputToken,
                tokenOut: outputTokens[i],
                fee: swapFees[i],
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountInForSwap,
                amountOutMinimum: minOutputAmounts[i], // Respecting slippage tolerance
                sqrtPriceLimitX96: 0
            });

            router.exactInputSingle(params);
        }
    }

    /// @notice Update the swap fee percentage
    /// @param _fee New fee in basis points (e.g., 100 = 1%)
    function updateTorqueSwapFee(uint _fee) external onlyOwner {
        TorqueSwapFee = _fee;
    }

    /// @notice Update the treasury address
    /// @param _treasury New treasury address
    function updateTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}
