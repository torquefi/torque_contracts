// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./RewardUtil.sol";
import "./MinDuration.sol";

abstract contract BoostAbstract is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;

    // struct BoostInfo {
    //     address user;
    //     uint supplied;
    //     uint supplyTime;
    //     uint reward;
    // }

    // mapping(address => BoostInfo) public boostInfoMap;

    // uint public totalSupplied;
    
    function _authorizeUpgrade(address) internal override onlyOwner {}

    IERC20 public rewardToken;
    uint256 public rewardPerBlock;
    uint256 public lastRewardBlock;
    MinDuration public minDurationContract;

    function initialize(address _rewardToken, uint256 _rewardPerBlock) public onlyOwner {
        rewardToken = IERC20(_rewardToken);
        rewardPerBlock = _rewardPerBlock;
        lastRewardBlock = block.number;
        minDurationContract = new MinDuration(_minDurationUnlockBlock);
        _initializeBoost();
    }

    function _initializeBoost() internal virtual;

    function _deposit(uint256 _amount) internal virtual;

    function _withdraw(uint256 _amount) internal virtual;

    function _compoundFees() internal virtual;

    function _calculateUserReward(address _user) internal view virtual returns (uint256);

    function _updateReward(address _user) internal virtual;

    function _checkWithdraw(uint256 _amount) internal virtual {
        require(tTokenAmount > 0, "Withdraw amount must be greater than zero");
        require(tTokenContract.balanceOf(msg.sender) >= tTokenAmount, "Insufficient tToken balance");
        require(minDurationContract.isDurationMet(), "Minimum duration not yet reached");
    }
}
