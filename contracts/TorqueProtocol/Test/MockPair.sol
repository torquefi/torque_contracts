// SPDX-License: MIT

pragma solidity ^0.8.15;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

contract MockPair is ERC20 {
    constructor() ERC20("Torque Pair", "TorqETH") {}

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
