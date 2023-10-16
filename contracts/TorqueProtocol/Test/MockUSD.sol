// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

contract MockUSD is ERC20 {
    constructor() ERC20("Mock Tokenized USD", "mUSD") {}

    function mint(address _tokenIn, uint256 _amount) public {
        IERC20 tokenIn = IERC20(_tokenIn);
        tokenIn.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    function burn(address _tokenOut, uint256 _amount) public {
        IERC20 tokenOut = IERC20(_tokenOut);
        _burn(msg.sender, _amount);
        tokenOut.transfer(msg.sender, _amount);
    }
}
