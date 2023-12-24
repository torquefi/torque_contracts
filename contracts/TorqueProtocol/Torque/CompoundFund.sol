// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "../../../CompoundBase/IComet.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract CompoundFund is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    address public baseAsset;
    address public comet;

    mapping(address => bool) private _governor;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    modifier onlyGovernor() {
        require(
            owner() == msg.sender || _governor[msg.sender] == true,
            "Caller is not the governor"
        );
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(address _comet, address _baseAsset) public initializer {
        comet = _comet;
        baseAsset = _baseAsset;
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    function setGovernor(address governor, bool active) public onlyOwner {
        _governor[governor] = active;
    }

    function deposit(uint amount) public nonReentrant onlyGovernor {
        require(
            ERC20(baseAsset).transferFrom(msg.sender, address(this), amount),
            "transfer token fail"
        );
        ERC20(baseAsset).approve(comet, amount);
        IComet(comet).supply(baseAsset, amount);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint withdrawAmount) public nonReentrant onlyGovernor {
        require(ERC20(baseAsset).transfer(msg.sender, withdrawAmount), "transfer token fail");
        emit Withdraw(msg.sender, withdrawAmount);
    }

    function totalAsset() public view returns (uint256) {
        return IComet(comet).balanceOf(address(this));
    }
}
