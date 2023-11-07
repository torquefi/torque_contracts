// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

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

// This contract represents a vault receipt token minted to vehicles and burned from them to fetch assets from child vaults.

contract vToken is ERC20, Ownable, ReentrancyGuard {
    // Token supply cap
    uint256 private _cap;
    // Managerial address
    address public manager;

    // Event emitted when a contract is approved or disapproved
    event ContractApproval(address indexed contractAddress, bool approvalStatus);
    // Event emitted when managerial responsibility is transferred
    event ResponsibilityDelegated(address indexed previousManager, address indexed newManager);
    // Event emitted when the cap is adjusted
    event CapChanged(uint256 oldCap, uint256 newCap);

    // Mapping of approved contracts
    mapping(address => bool) private approvedContracts;

    // Restricts function calls to manager
    modifier onlyManager() {
        require(msg.sender == manager, "vToken: caller is not the manager");
        _;
    }

    // Restricts function calls to approved contract
    modifier onlyApprovedContract() {
        require(approvedContracts[msg.sender], "vToken: caller is not an approved contract");
        _;
    }

    // Sets token details and values
    constructor(
        string memory name,
        string memory symbol,
        uint256 cap_,
        address manager_
    ) ERC20(name, symbol) {
        require(cap_ > 0, "vToken: cap is 0");
        _cap = cap_;
        manager = manager_;
    }

    // Returns the current cap
    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    // Mints new tokens, restricted to approved contracts
    function mint(address to, uint256 amount) public virtual onlyApprovedContract nonReentrant {
        require(totalSupply() + amount <= _cap, "vToken: cap exceeded");
        _mint(to, amount);
    }

    // Burns tokens, restricted to approved contracts
    function burn(address from, uint256 amount) public virtual onlyApprovedContract nonReentrant {
        require(balanceOf(from) >= amount, "vToken: insufficient balance");
        _burn(from, amount);
    }

    // Sets a new cap, restricted to contract owner
    function setCap(uint256 newCap) public virtual onlyOwner {
        require(newCap > totalSupply(), "vToken: new cap must be greater than total supply");
        emit CapChanged(_cap, newCap);
        _cap = newCap;
    }

    // Delegate managerial responsibility to a new address, restricted to contract owner
    function delegateResponsibility(address newManager) public virtual onlyOwner {
        require(newManager != address(0), "vToken: new manager is the zero address");
        emit ResponsibilityDelegated(manager, newManager);
        manager = newManager;
    }

    // Transfer contract ownership, restricted to contract owner
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        require(newOwner != address(0), "vToken: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    // Sets a new cap, restricted to the manager
    function setCapByManager(uint256 newCap) public virtual onlyManager {
        require(newCap > totalSupply(), "vToken: new cap must be greater than total supply");
        emit CapChanged(_cap, newCap);
        _cap = newCap;
    }

    // Approve a contract address, restricted to contract owner
    function addApprovedContract(address contractAddress) external onlyOwner {
        require(contractAddress != address(0), "vToken: approve zero address");
        approvedContracts[contractAddress] = true;
        emit ContractApproval(contractAddress, true);
    }

    // Remove approval from a contract address, restricted to contract owner
    function removeApprovedContract(address contractAddress) external onlyOwner {
        require(contractAddress != address(0), "vToken: disapprove zero address");
        approvedContracts[contractAddress] = false;
        emit ContractApproval(contractAddress, false);
    }

    // Check if a contract address is approved
    function isContractApproved(address contractAddress) public view returns (bool) {
        return approvedContracts[contractAddress];
    }
}
