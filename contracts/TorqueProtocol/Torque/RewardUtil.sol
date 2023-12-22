// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RewardUtilConfiguration.sol";

contract RewardUtil is Ownable, RewardUtilConfiguration {
    using SafeMath for uint256;

    constructor(address _rewardToken, uint256 _distributionRate, uint256 _vestingPeriod)
        RewardUtilConfiguration(_rewardToken, _distributionRate, _vestingPeriod) {}

    function calculateReward(uint _amount, uint _from) external view returns (uint) {
        // Logic using inherited properties (e.g., distributionRate)
        uint reward = _amount.mul(distributionRate).div(100);
        return reward;
    }

    function distributeReward(address user) external onlyOwner {
        // Reward distribution logic here based on the configuration
    }
}
