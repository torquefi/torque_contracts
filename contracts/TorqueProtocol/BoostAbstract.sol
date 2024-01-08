// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BoostAbstract is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct BoostInfo {
        address user;
        uint supplied;
        uint supplyTime;
    }

    struct Config {
        uint256 performanceFee;
        address treasury;
    }

    struct Addresses {
        address tTokenContract;
    }

    Config public config;
    Addresses public addresses;

    mapping(address => BoostInfo) public boostInfoMap;

    uint public totalSupplied;
    uint256 public lastCompoundTimestamp;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Compound(uint256 amount);

    constructor(address _tTokenContract, address _treasury) {
        addresses.tTokenContract = _tTokenContract;
        config.treasury = _treasury;
        config.performanceFee = 2000;
    }

    function deposit(uint256 _amount) public virtual;
    function withdraw(uint256 _amount) public virtual;
    function compoundFees() public virtual;

    function _updateTotalSupplied(uint256 _amount, bool _isDeposit) internal {
        if (_isDeposit) {
            totalSupplied = totalSupplied.add(_amount);
        } else {
            totalSupplied = totalSupplied.sub(_amount);
        }
    }
    function _calculateReward(address user) internal virtual returns (uint256);
    function checkUpkeep(bytes calldata) external virtual view returns (bool upkeepNeeded, bytes memory);
    function performUpkeep(bytes calldata) external virtual;
}
