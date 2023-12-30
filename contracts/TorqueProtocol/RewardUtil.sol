// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RewardUtil is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public torqToken;
    uint256 public torqPerBlock;

    mapping(address => uint256) public lastRewardBlock;
    mapping(address => mapping(address => uint256)) public rewardsClaimed;
    mapping(address => uint256) public rewardSpeed;

    event RewardClaimed(address indexed user, uint256 amount);
    event RewardSpeedUpdated(address indexed torqueContract, uint256 newSpeed);

    constructor(address _torqTokenAddress) {
        require(_torqTokenAddress != address(0), "Invalid TORQ token address");
        torqToken = IERC20(_torqTokenAddress);
    }

    function setRewardSpeed(address torqueContract, uint256 _speed) external onlyOwner {
        rewardSpeed[torqueContract] = _speed;
        emit RewardSpeedUpdated(torqueContract, _speed);
    }

    function calculateReward(address torqueContract, address user) public view returns (uint256) {
        uint256 blocks = block.number - lastRewardBlock[user];
        uint256 userReward = blocks.mul(rewardSpeed[torqueContract]);
        return userReward;
    }

    function claimReward(address torqueContract, address user) external nonReentrant {
        require(user != address(0), "Invalid user address");
        updateReward(torqueContract, user);
        uint256 rewardAmount = rewardsClaimed[torqueContract][user];
        require(torqToken.balanceOf(address(this)) >= rewardAmount, "Insufficient TORQ");
        rewardsClaimed[torqueContract][user] = 0;
        torqToken.transfer(user, rewardAmount);
        emit RewardClaimed(user, rewardAmount);
    }

    function updateReward(address torqueContract, address user) internal {
        uint256 reward = calculateReward(torqueContract, user);
        lastRewardBlock[user] = block.number;
        rewardsClaimed[torqueContract][user] = rewardsClaimed[torqueContract][user].add(reward);
    }
}
