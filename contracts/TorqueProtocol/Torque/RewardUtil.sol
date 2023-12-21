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

contract RewardUtil is Ownable {
    using SafeMath for uint256;

    RewardUtilConfiguration public rewardUtilConfig;

    constructor(address _rewardDistributionConfig) {
        rewardUtilConfig = RewardUtilConfiguration(_rewardUtilConfig);
    }

    function calculateReward(uint _amount, uint _from) external view returns (uint) {
        // Implement logic
    }

    function distributeReward(address user) external onlyOwner {
        // Implement reward distribution logic here based on the configuration
        // Use rewardDistributionConfig parameters for calculations
    }
}
