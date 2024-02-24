// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RewardUtil is ReentrancyGuard, Ownable { 
    using SafeMath for uint256;

    struct RewardConfig {
        uint256 rewardFactor;
        uint256 torquePool;
    }

    struct UserRewardConfig {
        uint256 rewardAmount;
        uint256 depositAmount;
        uint256 lastRewardBlock;
        bool isActive;
    }

    IERC20 public torqToken;
    address public governor;

    mapping(address => bool) public distributionContract;
    mapping(address => RewardConfig) public rewardConfig; // Distribution Contract --> Reward Config
    mapping(address => mapping(address => UserRewardConfig)) public rewardsClaimed; // Distribution Contract --> User Address --> Rewards 


    event GovernorTransferred(address indexed oldGovernor, address indexed newGovernor);
    event RewardClaimed(address indexed user, address indexed torqueContract, uint256 amount);
    event RewardFactorUpdated(address indexed torqueContract, uint256 newSpeed);
    event TorquePoolUpdated(address torqueContract,uint256 _poolAmount);

    error NotPermitted(address);
    error InvalidTorqueContract(address);

    constructor(address _torqTokenAddress, address _governor) Ownable(msg.sender) {
        require(_torqTokenAddress != address(0), "Invalid TORQ token address");
        torqToken = IERC20(_torqTokenAddress);
        governor = _governor;
    }

    modifier onlyGovernor() {
        if (msg.sender != governor) revert NotPermitted(msg.sender);
        _;
    }

    function userDepositReward(address _userAddress, uint256 _depositAmount) external {
        require(distributionContract[msg.sender], "Unauthorised!");
        _calculateAndUpdateReward(msg.sender, _userAddress);
        rewardsClaimed[msg.sender][_userAddress].depositAmount = rewardsClaimed[msg.sender][_userAddress].depositAmount.add(_depositAmount);
        rewardsClaimed[msg.sender][_userAddress].lastRewardBlock = block.number;
        rewardsClaimed[msg.sender][_userAddress].isActive = true;
    }

    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external {
        require(distributionContract[msg.sender], "Unauthorised!");
        _calculateAndUpdateReward(msg.sender, _userAddress);
        rewardsClaimed[msg.sender][_userAddress].depositAmount = rewardsClaimed[msg.sender][_userAddress].depositAmount.sub(_withdrawAmount);
        if(rewardsClaimed[msg.sender][_userAddress].depositAmount == 0){
            rewardsClaimed[msg.sender][_userAddress].isActive = false;
        }
    }

    function setrewardFactor(address torqueContract, uint256 _rewardFactor) public onlyGovernor() {
        rewardConfig[torqueContract].rewardFactor = _rewardFactor;
        emit RewardFactorUpdated(torqueContract, _rewardFactor);
    }

    function setTorquePool(address _torqueContract, uint256 _poolAmount) public onlyGovernor() {
        rewardConfig[_torqueContract].torquePool = _poolAmount;
        emit TorquePoolUpdated(_torqueContract, _poolAmount);
    }

    function updateReward(address torqueContract, address user) public nonReentrant {
        _calculateAndUpdateReward(torqueContract, user);
    }

    function setDistributionContract(address _address, uint256 _rewardFactor, uint256 _rewardPool) public onlyOwner { // Can update to governor contract later
        if (_rewardFactor == 0) revert InvalidTorqueContract(_address);
        distributionContract[_address] = true;
        setrewardFactor(_address, _rewardFactor);
        setTorquePool(_address, _rewardPool);
    }

    function _calculateAndUpdateReward(address _torqueContract, address _userAddress) internal {
        if(!rewardsClaimed[_torqueContract][_userAddress].isActive){
            return;
        }
        uint256 blocks = block.number - rewardsClaimed[_torqueContract][_userAddress].lastRewardBlock; // 288000 daily blocks
        uint256 userReward = blocks.mul(rewardsClaimed[_torqueContract][_userAddress].depositAmount); // Fix formula
        userReward = userReward.mul(rewardConfig[_torqueContract].torquePool);
        userReward = userReward.div(rewardConfig[_torqueContract].rewardFactor);
        rewardsClaimed[_torqueContract][_userAddress].lastRewardBlock = block.number;
        rewardsClaimed[_torqueContract][_userAddress].rewardAmount = rewardsClaimed[_torqueContract][_userAddress].rewardAmount.add(userReward);
    }

    function claimReward(address _torqueContract) external nonReentrant {
        if (rewardConfig[_torqueContract].rewardFactor == 0) revert InvalidTorqueContract(_torqueContract);
        require(rewardsClaimed[_torqueContract][msg.sender].isActive, "Rewards are not activated!");
        
        updateReward(_torqueContract, msg.sender);
        uint256 rewardAmount = rewardsClaimed[_torqueContract][msg.sender].rewardAmount;
        require(torqToken.balanceOf(address(this)) >= rewardAmount, "Insufficient TORQ");
        rewardsClaimed[_torqueContract][msg.sender].rewardAmount = 0;
        torqToken.transfer(msg.sender, rewardAmount);
        emit RewardClaimed(msg.sender, _torqueContract, rewardAmount);
    }

    function transferGovernor(address newGovernor) external onlyGovernor {
        address oldGovernor = governor;
        governor = newGovernor;
        emit GovernorTransferred(oldGovernor, newGovernor);
    }

    function getRewardConfig(address _torqueContract, address _user) public view returns (UserRewardConfig memory){
        return rewardsClaimed[_torqueContract][_user];
    }
}
