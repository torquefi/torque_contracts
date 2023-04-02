// SPDX-License: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../Interfaces/IStargateLPStaking.sol";

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

contract Boost is Ownable {
    // variables and mapping
    IStargateLPStaking lpStaking;
    // address[] public stakeHolders;

    mapping(address => mapping(uint256 => UserInfo)) public userInfo;
    mapping(address => mapping(uint256 => bool)) public isStakeHolder;
    mapping(uint256 => address[]) public stakeHolders;

    // structs and events
    struct UserInfo {
        uint256 amount;
        uint256 reward;
        uint256 lastProcess;
    }

    // constructor and functions
    constructor(address _stargateAddress) {
        lpStaking = IStargateLPStaking(_stargateAddress);
    }

    function deposit() public {}

    function withdraw() public {}

    function autoCompound() public {}

    function claimReward() public {}

    // internal functions
    function calculate(uint256 _pid) public view returns (uint256) {}
}
