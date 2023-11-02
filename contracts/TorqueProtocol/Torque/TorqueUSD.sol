pragma solidity ^0.8.0;

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

// This contract represents a liquid token minted to users from vehicles (tUSD in this case)

contract TorqueUSD is ERC20, Ownable, ReentrancyGuard {
    
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
    // Event emited when ownership is transferred
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Mapping of approved contracts
    mapping(address => bool) private approvedContracts;

    // Restricts function calls to manager
    modifier onlyManager() {
        require(msg.sender == manager, "TorqueUSD: caller is not the manager");
        _;
    }

    // Restricts function calls to approved contract
    modifier onlyApprovedContract() {
        require(approvedContracts[msg.sender], "TorqueUSD: caller is not an approved contract");
        _;
    }

    // Sets token details and values
    constructor(
        string memory name,
        string memory symbol,
        uint256 cap_,
        address manager_
    ) ERC20(name, symbol) {
        require(cap_ > 0, "TorqueUSD: cap is 0");
        _cap = cap_;
        manager = manager_;
    }

    // Returns the current cap
    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    // Mints new tokens, restricted to approved contracts
    function mint(address to, uint256 amount) public virtual onlyApprovedContract nonReentrant {
        require(totalSupply() + amount <= _cap, "TorqueUSD: cap exceeded");
        _mint(to, amount);
    }

    // Burns tokens, restricted to approved contracts
    function burn(address from, uint256 amount) public virtual onlyApprovedContract nonReentrant {
        require(balanceOf(from) >= amount, "TorqueUSD: insufficient balance");
        _burn(from, amount);
    }

    // Sets a new cap, restricted to contract owner
    function setCap(uint256 newCap) public virtual onlyOwner {
        require(newCap > totalSupply(), "TorqueUSD: new cap must be greater than total supply");
        _cap = newCap;
        
        emit CapChanged(_cap, newCap);
    }

    // Delegate managerial responsibility to a new address, restricted to contract owner
    function delegateResponsibility(address newManager) public virtual onlyOwner {
        require(newManager != address(0), "TorqueUSD: new manager is the zero address");
        manager = newManager;

        emit ResponsibilityDelegated(manager, newManager);
    }

    // Transfer contract ownership, restricted to contract owner
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        require(newOwner != address(0), "TorqueUSD: new owner is the zero address");
        _owner = newOwner;

        emit OwnershipTransferred(_owner, newOwner);
    }

    // Sets a new cap, restricted to the manager
    function setCapByManager(uint256 newCap) public virtual onlyManager {
        require(newCap > totalSupply(), "TorqueUSD: new cap must be greater than total supply");
        _cap = newCap;

        emit CapChanged(_cap, newCap);
    }

    // Approve a contract address, restricted to contract owner
    function addApprovedContract(address contractAddress) external onlyOwner {
        require(contractAddress != address(0), "TorqueUSD: approve zero address");
        approvedContracts[contractAddress] = true;

        emit ContractApproval(contractAddress, true);
    }

    // Remove approval from a contract address, restricted to contract owner
    function removeApprovedContract(address contractAddress) external onlyOwner {
        require(contractAddress != address(0), "TorqueUSD: disapprove zero address");
        approvedContracts[contractAddress] = false;

        emit ContractApproval(contractAddress, false);
    }

    // Check if a contract address is approved
    function isContractApproved(address contractAddress) public view returns (bool) {
        return approvedContracts[contractAddress];
    }
}