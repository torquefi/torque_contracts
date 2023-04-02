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

contract Boost {
    // variables and mapping
    address public stargateAddress;

    // structs and events
    // constructor and functions
    constructor(address _stargateAddress) {
        stargateAddress = _stargateAddress;
    }

    function deposit() public {}

    function withdraw() public {}

    function autoYield() public {}

    function claimReward() public {}
}
