// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RewardUtil {
    using SafeMath for uint256;

    struct RewardConfig {
        uint256 rewardSpeed;
        uint256 lastRewardBlock;
    }

    IERC20 public torqToken;
    address public governor;

    mapping(address => RewardConfig) public rewardConfig;
    mapping(address => mapping(address => uint256)) public rewardsClaimed;

    event GovernorTransferred(address indexed oldGovernor, address indexed newGovernor);
    event RewardClaimed(address indexed user, address indexed torqueContract, uint256 amount);
    event RewardSpeedUpdated(address indexed torqueContract, uint256 newSpeed);

    error NotPermitted(address);
    error InvalidTorqueContract(address);

    constructor(address _torqTokenAddress, address _governor) {
        require(_torqTokenAddress != address(0), "Invalid TORQ token address");
        torqToken = IERC20(_torqTokenAddress);
        governor = _governor;
    }

    modifier onlyGovernor() {
        if (msg.sender != governor) revert NotPermitted(msg.sender);
        _;
    }

    function setRewardSpeed(address torqueContract, uint256 _speed) external onlyGovernor {
        rewardConfig[torqueContract].rewardSpeed = _speed;
        emit RewardSpeedUpdated(torqueContract, _speed);
    }

    function claimReward(address torqueContract, address user) external {
        if (rewardConfig[torqueContract].rewardSpeed == 0) revert InvalidTorqueContract(torqueContract);
        updateReward(torqueContract, user);
        uint256 rewardAmount = rewardsClaimed[torqueContract][user];
        require(torqToken.balanceOf(address(this)) >= rewardAmount, "Insufficient TORQ");
        rewardsClaimed[torqueContract][user] = 0;
        torqToken.transfer(user, rewardAmount);
        emit RewardClaimed(user, torqueContract, rewardAmount);
    }

    function updateReward(address torqueContract, address user) internal {
        uint256 blocks = block.number - rewardConfig[torqueContract].lastRewardBlock;
        uint256 userReward = blocks.mul(rewardConfig[torqueContract].rewardSpeed);
        rewardConfig[torqueContract].lastRewardBlock = block.number;
        rewardsClaimed[torqueContract][user] = rewardsClaimed[torqueContract][user].add(userReward);
    }

    function transferGovernor(address newGovernor) external onlyGovernor {
        address oldGovernor = governor;
        governor = newGovernor;
        emit GovernorTransferred(oldGovernor, newGovernor);
    }
}
