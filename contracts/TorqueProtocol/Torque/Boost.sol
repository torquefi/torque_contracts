// SPDX-License: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../Interfaces/IStargateLPStaking.sol";
import "../Interfaces/ISwapRouter.sol";

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
    IERC20 public stargateInterface;
    ISwapRouter public swapRouter;
    address constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address public Stargate;
    mapping(address => uint256) public totalStack;
    // address[] public stakeHolders;

    mapping(address => mapping(uint256 => UserInfo)) public userInfo;
    mapping(address => mapping(uint256 => bool)) public isStakeHolder;
    mapping(uint256 => address[]) public stakeHolders;
    mapping(address => uint256) public addressToPid;

    // structs and events
    struct UserInfo {
        uint256 amount;
        uint256 lastProcess;
    }

    // constructor and functions
    constructor(address _stargateStakingAddress, address _stargateAddress, address _swapRouter) {
        lpStaking = IStargateLPStaking(_stargateStakingAddress);
        stargateInterface = IERC20(_stargateAddress);
        swapRouter = ISwapRouter(_swapRouter);
    }

    function setPid(address _token, uint256 _pid) public onlyOwner {
        addressToPid[_token] = _pid;
    }

    function deposit(address _token, uint256 _amount) public payable {
        uint256 pid = addressToPid[_token];
        IERC20 tokenInterface = IERC20(_token);
        tokenInterface.transferFrom(_msgSender(), address(this), _amount);
        tokenInterface.approve(address(lpStaking), _amount);
        lpStaking.deposit(pid, _amount);

        UserInfo storage _userInfo = userInfo[_msgSender()][pid];
        if (_userInfo.lastProcess == 0) {
            address[] storage stakes = stakeHolders[pid];
            stakes.push(_msgSender());
        }
        _userInfo.amount = _userInfo.amount.add(_amount);
        _userInfo.lastProcess = block.timestamp;
        totalStack[_token] = totalStack[_token].add(_amount);
    }

    function withdraw(address _token, uint256 _amount) public payable {
        uint256 pid = addressToPid[_token];
        IERC20 tokenInterface = IERC20(_token);
        lpStaking.withdraw(pid, _amount);
        tokenInterface.transfer(_msgSender(), _amount);

        UserInfo storage _userInfo = userInfo[_msgSender()][pid];
        _userInfo.amount = _userInfo.amount.sub(_amount);
        _userInfo.lastProcess = block.timestamp;
        totalStack[_token] = totalStack[_token].sub(_amount);
    }

    function autoCompound(address _token) public {
        IERC20 tokenInterface = IERC20(_token);
        uint256 pid = addressToPid[_token];
        uint256 totalProduction = calculateTotalProduct(pid);
        lpStaking.withdraw(pid, totalStack[_token]);
        uint256 rewardSTG = stargateInterface.balanceOf(address(this));
        // TO-DO: swap STG reward to address
        uint256 tokenReward = swapRewardSTGToToken(_token, rewardSTG);
        address[] memory stakes = stakeHolders[pid];
        for (uint256 i = 0; i < stakes.length; i++) {
            UserInfo storage _userInfo = userInfo[stakes[i]][pid];
            uint256 userProduct = calculateUserProduct(pid, stakes[i]);
            uint256 reward = tokenReward.mul(userProduct).div(totalProduction);
            _userInfo.amount = _userInfo.amount.add(reward);
        }
        totalStack[_token] = totalStack[_token].add(tokenReward);
        tokenInterface.approve(address(lpStaking), totalStack[_token]);
        lpStaking.deposit(pid, totalStack[_token]);
    }

    // internal functions
    function calculateTotalProduct(uint256 _pid) internal view returns (uint256) {
        address[] memory stakes = stakeHolders[_pid];
        uint256 totalProduct = 0;
        for (uint256 i = 0; i < stakes.length; i++) {
            uint256 userProduct = calculateUserProduct(_pid, stakes[i]);
            totalProduct = totalProduct.add(userProduct);
        }
        return totalProduct;
    }

    function calculateUserProduct(uint256 _pid, address _staker) internal view returns (uint256) {
        UserInfo memory _userInfo = userInfo[_staker][_pid];
        uint256 interval = block.timestamp.sub(_userInfo.lastProcess);
        return interval.mul(_userInfo.amount);
    }

    function swapRewardSTGToToken(address _token, uint256 _stgAmount) internal returns (uint256) {
        uint256[] memory amounts;
        stargateInterface.approve(address(swapRouter), _stgAmount);

        if (_token == WETH) {
            address[] memory path = new address[](2);
            path[0] = address(stargateInterface);
            path[1] = address(WETH);
            uint256 _deadline = block.timestamp + 3000;
            amounts = swapRouter.swapExactTokensForTokens(
                _stgAmount,
                _stgAmount, // amount out min for test
                path,
                address(this),
                _deadline
            );
        } else {
            address[] memory path = new address[](3);
            path[0] = address(stargateInterface);
            path[1] = address(WETH);
            path[2] = _token;
            uint256 _deadline = block.timestamp + 3000;
            amounts = swapRouter.swapExactTokensForTokens(
                _stgAmount,
                _stgAmount, // amount out min for test
                path,
                address(this),
                _deadline
            );
        }
        return amounts[amounts.length - 1]; // the last one
    }
}
