// SPDX-License: MIT
pragma solidity ^0.8.15;

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

interface IStakingTorque {
    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
