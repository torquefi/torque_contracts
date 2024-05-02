// SPDX-License-Identifier: UNLICENSED
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

contract MarketMaker is Ownable {
    ISwapRouter private constant router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address public treasury = 0x0f773B3d518d0885DbF0ae304D87a718F68EEED5;
    uint public TorqueSwapFee = 10;

    constructor() Ownable(msg.sender) {}

    function swapExactInputSingleHop(uint amountIn, uint amountOutMin, uint24 _swapFee, address _tokenIn, address _tokenOut)
        external
    {
        IERC20 tokenIn = IERC20(_tokenIn);
        
        uint256 swapFeeAmt = amountIn*TorqueSwapFee/1000;
        if(swapFeeAmt!=0){
            require(tokenIn.transferFrom(msg.sender, treasury, swapFeeAmt), "TX Failed!");
        }
        
        amountIn = amountIn - swapFeeAmt;
        require(tokenIn.transferFrom(msg.sender, address(this), amountIn), "TX Failed!");
        
        tokenIn.approve(address(router), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: _swapFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });
        router.exactInputSingle(params);
    }

    function swapExactInputMultiHop(uint amountIn, uint amountOutMin, bytes memory path ,address _tokenIn) external {
        IERC20 tokenIn = IERC20(_tokenIn);
        uint256 swapFeeAmt = amountIn*TorqueSwapFee/1000;
        if(swapFeeAmt!=0){
            require(tokenIn.transferFrom(msg.sender, treasury, swapFeeAmt), "TX Failed!");
        }
        
        amountIn = amountIn - swapFeeAmt;
        require(tokenIn.transferFrom(msg.sender, address(this), amountIn), "TX Failed!");

        tokenIn.approve(address(router), amountIn);

        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin
            });

        router.exactInput(params);
    }

    function updateTorqueSwapFee(uint _fee) external onlyOwner {
        TorqueSwapFee = _fee;
    }

    function updateTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function encoderPath(address _tokenInput, uint24 poolFee1, address _tokenIntermediate, uint24 poolFee2, address _tokenOutput) public pure returns (bytes memory) {
        return abi.encodePacked(_tokenInput, poolFee1, _tokenIntermediate, poolFee2, _tokenOutput);
    }
}
