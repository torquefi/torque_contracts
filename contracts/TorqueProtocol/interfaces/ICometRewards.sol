// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

abstract contract ICometRewards {
    struct RewardConfig {
        address token;
        uint64 rescaleFactor;
        bool shouldUpscale;
    }
    struct RewardOwed {
        address token;
        uint owed;
    }

    function claim(address comet, address src, bool shouldAccrue) external virtual;

    function rewardConfig(address) external virtual returns (RewardConfig memory);

    function rewardsClaimed(address _market, address _user) external view virtual returns (uint256);

    function getRewardOwed(
        address _market,
        address _user
    ) external virtual returns (RewardOwed memory);
}
