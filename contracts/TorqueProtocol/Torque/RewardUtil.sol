// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract RewardUtil  is UUPSUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize() public initializer {
        __Ownable_init();
    }


    function calculateReward(uint _amount, uint _from) external view returns (uint){
        return 0;
    }
    
}