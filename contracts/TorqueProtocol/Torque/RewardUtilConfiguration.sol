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

contract RewardUtilConfiguration is Ownable {
    using SafeMath for uint256;
    
    address public rewardToken;
    uint256 public distributionRate;
    uint256 public vestingPeriod;

    constructor(address _rewardToken, uint256 _distributionRate, uint256 _vestingPeriod) {
        rewardToken = _rewardToken;
        distributionRate = _distributionRate;
        vestingPeriod = _vestingPeriod;
    }

    function updateConfiguration(uint256 _distributionRate, uint256 _vestingPeriod) external onlyOwner {
        distributionRate = _distributionRate;
        vestingPeriod = _vestingPeriod;
    }
}
