// SPDX-License: MIT
pragma solidity ^0.8.15;

import "./../Interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**

********\                                                
\__**  __|                                               
   ** | ******\   ******\   ******\  **\   **\  ******\  
   ** |**  __**\ **  __**\ **  __**\ ** |  ** |**  __**\ 
   ** |** /  ** |** |  \__|** /  ** |** |  ** |******** |
   ** |** |  ** |** |      ** |  ** |** |  ** |**   ____|
   ** |\******  |** |      \******* |\******  |\*******\ 
   \__| \______/ \__|       \____** | \______/  \_______|
                                 ** |                    
                                 ** |                    
                                 \__|                    

 */

contract MockSwap is ISwapRouter {
    constructor() {}

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];
        IERC20 tokenInInterface = IERC20(tokenIn);
        IERC20 tokenOutInterface = IERC20(tokenOut);
        require(block.timestamp <= deadline);
        tokenInInterface.transferFrom(msg.sender, address(this), amountIn);
        tokenOutInterface.transfer(to, amountOutMin);
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOutMin;
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];
        IERC20 tokenInInterface = IERC20(tokenIn);
        IERC20 tokenOutInterface = IERC20(tokenOut);
        require(block.timestamp <= deadline);
        tokenInInterface.transferFrom(msg.sender, address(this), amountInMax);
        tokenOutInterface.transfer(to, amountOut);
        amounts = new uint256[](2);
        amounts[0] = amountInMax;
        amounts[1] = amountOut;
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        address tokenOut = path[path.length - 1];
        require(msg.value >= amountOutMin, "wrong input value");
        require(block.timestamp <= deadline);
        IERC20 tokenOutInterface = IERC20(tokenOut);
        tokenOutInterface.transfer(to, amountOutMin);
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = amountOutMin;
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        address tokenIn = path[0];
        IERC20 tokenInInterface = IERC20(tokenIn);
        require(block.timestamp <= deadline);
        tokenInInterface.transferFrom(msg.sender, address(this), amountInMax);
        (bool success, ) = to.call{ value: amountOut }("");
        require(success, "transfer eth failed");
        amounts = new uint256[](2);
        amounts[0] = amountInMax;
        amounts[1] = amountOut;
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        address tokenIn = path[0];
        IERC20 tokenInInterface = IERC20(tokenIn);
        require(block.timestamp <= deadline);
        tokenInInterface.transferFrom(msg.sender, address(this), amountIn);
        (bool success, ) = to.call{ value: amountOutMin }("");
        require(success, "transfer eth failed");
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOutMin;
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        address tokenOut = path[path.length - 1];
        require(msg.value >= amountOut, "wrong input value");
        require(block.timestamp <= deadline);
        IERC20 tokenOutInterface = IERC20(tokenOut);
        tokenOutInterface.transfer(to, amountOut);
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = amountOut;
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        uint256 length = path.length;
        amounts = new uint256[](length - 1);
        for (uint256 i = 0; i < length; i++) {
            amounts[i] = amountIn;
        }
    }
}
