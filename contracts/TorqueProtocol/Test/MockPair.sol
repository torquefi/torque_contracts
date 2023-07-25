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
    constructor() ERC20("Torque Pair", "TorqETH") {
        _mint(msg.sender, 100000000 ether);
    }

    function mint(address _receiver, uint256 _amount) public {
        _mint(_receiver, _amount);
    }
}
