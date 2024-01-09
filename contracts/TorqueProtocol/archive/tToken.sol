// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract tToken is ERC20, Ownable(msg.sender), ReentrancyGuard {
    uint256 private _cap;
    address public manager;

    event ContractApproval(address indexed contractAddress, bool approvalStatus);
    event ResponsibilityDelegated(address indexed previousManager, address indexed newManager);
    event CapChanged(uint256 oldCap, uint256 newCap);

    mapping(address => bool) private approvedContracts;

    modifier onlyManager() {
        require(msg.sender == manager, "Caller is not the manager");
        _;
    }

    modifier onlyApprovedContract() {
        require(approvedContracts[msg.sender], "Caller is not an approved contract");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        uint256 cap_,
        address manager_
    ) ERC20(name, symbol) {
        require(cap_ > 0, "Cap is 0");
        _cap = cap_;
        manager = manager_;
    }

    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    function mint(address to, uint256 amount) public virtual onlyApprovedContract nonReentrant {
        require(totalSupply() + amount <= _cap, "Cap exceeded");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public virtual onlyApprovedContract nonReentrant {
        require(balanceOf(from) >= amount, "Insufficient balance");
        _burn(from, amount);
    }

    function setCap(uint256 newCap) public virtual onlyOwner {
        require(newCap > totalSupply(), "New cap must be greater than total supply");
        _cap = newCap;

        emit CapChanged(_cap, newCap);
    }

    function delegateResponsibility(address newManager) public virtual onlyOwner {
        require(newManager != address(0), "New manager is the zero address");
        manager = newManager;

        emit ResponsibilityDelegated(manager, newManager);
    }

    function setCapByManager(uint256 newCap) public virtual onlyManager {
        require(newCap > totalSupply(), "New cap must be greater than total supply");
        _cap = newCap;

        emit CapChanged(_cap, newCap);
    }

    function addApprovedContract(address contractAddress) external onlyOwner {
        require(contractAddress != address(0), "Approve zero address");
        approvedContracts[contractAddress] = true;

        emit ContractApproval(contractAddress, true);
    }

    function removeApprovedContract(address contractAddress) external onlyOwner {
        require(contractAddress != address(0), "Disapprove zero address");
        approvedContracts[contractAddress] = false;

        emit ContractApproval(contractAddress, false);
    }

    function isContractApproved(address contractAddress) public view returns (bool) {
        return approvedContracts[contractAddress];
    }
}
