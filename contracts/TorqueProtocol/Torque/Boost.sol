// SPDX-License: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
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
    using SafeMath for uint256;
    // variables and mapping
    IStargateLPStaking lpStaking;
    address constant WETH = "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6";
    // address[] public stakeHolders;

    mapping(address => mapping(uint256 => UserInfo)) public userInfo;
    mapping(address => mapping(uint256 => bool)) public isStakeHolder;
    mapping(uint256 => address[]) public stakeHolders;
    mapping(address => uint256) public addressToPid;

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

    function deposit(address _token, uint256 _amount) public payable {
        uint256 pid = addressToPid[_token];
        IERC20 tokenInterface = IERC20(_token);
        tokenInterface.transferFrom(_msgSender(), address(this), _amount);
        tokenInterface.approve(address(lpStaking), _amount);
        lpStaking.deposit(pid, _amount);
    }

    function withdraw(address _token, uint256 _amount) public payable {
        uint256 pid = addressToPid[_token];
        IERC20 tokenInterface = IERC20(_token);
        lpStaking.withdraw(pid, _amount);
        tokenInterface.transfer(_msgSender(), _amount);
    }

    function autoCompound() public {}

    function claimReward(address _token) public payable {
        uint256 pid = addressToPid[_token];
        UserInfo storage userInfo = userInfo[_msgSender()][pid];
        uint256 reward = userInfo.reward;

        if (_token == WETH) {
            (bool success, ) = _msgSender().call{ value: reward }("");
            require(success, "Failed to transfer ETH");
        }
    }

    // internal functions
    function calculate(uint256 _pid) public view returns (uint256) {}
}
