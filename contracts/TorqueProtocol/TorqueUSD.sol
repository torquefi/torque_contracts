// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/// @title TorqueUSD Contract
/// @notice This contract represents the TorqueUSD stablecoin, which is cross-chain compatible using LayerZero's Omnichain Fungible Token (OFT) standard.
/// @dev Extends ERC20Burnable for minting and burning functionalities, OFT for cross-chain compatibility, and Ownable for administrative control.
contract TorqueUSD is ERC20Burnable, OFT, Ownable {

    /// @notice Address of the controller that can mint and burn TorqueUSD
    address public controller;

    /// @notice Error emitted when the amount is zero or negative
    error TorqueUSD__AmountMustBeMoreThanZero();
    /// @notice Error emitted when trying to burn more than the account balance
    error TorqueUSD__BurnAmountExceedsBalance();
    /// @notice Error emitted when a zero address is used as a parameter
    error TorqueUSD__NotZeroAddress();

    /// @notice Initializes the TorqueUSD contract with the LayerZero endpoint
    /// @param _lzEndpoint The LayerZero endpoint address for cross-chain messaging
    constructor(address _lzEndpoint) 
        OFT("Torque USD", "TorqueUSD", _lzEndpoint) 
        Ownable() 
    {}

    /// @notice Sets the controller address that is allowed to mint and burn TorqueUSD
    /// @dev Only the contract owner can call this function
    /// @param _controller The address of the new controller
    function setController(address _controller) external onlyOwner {
        require(_controller != address(0), "Controller cannot be zero address");
        controller = _controller;
    }

    /// @notice Mints TorqueUSD to a specified address
    /// @dev Only the controller can call this function
    /// @param _to The address to receive the minted TorqueUSD
    /// @param _amount The amount of TorqueUSD to mint
    /// @return Returns true if minting is successful
    function mint(address _to, uint256 _amount) external returns (bool) {
        require(msg.sender == controller, "Unauthorized");
        if (_to == address(0)) {
            revert TorqueUSD__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert TorqueUSD__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    /// @notice Burns a specified amount of TorqueUSD from the caller's balance
    /// @dev Only the controller can burn TorqueUSD
    /// @param _amount The amount of TorqueUSD to burn
    function burn(uint256 _amount) public override {
        require(msg.sender == controller, "Unauthorized");
        if (_amount <= 0) {
            revert TorqueUSD__AmountMustBeMoreThanZero();
        }
        uint256 balance = balanceOf(msg.sender);
        if (balance < _amount) {
            revert TorqueUSD__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    /// @notice Internal function to mint TorqueUSD, with cross-chain support
    /// @dev Overrides both OFT and ERC20 _mint functions for compatibility
    /// @param to The address receiving the minted TorqueUSD
    /// @param amount The amount of TorqueUSD to mint
    function _mint(address to, uint256 amount) internal override(OFT, ERC20) {
        super._mint(to, amount);
    }

    /// @notice Internal function to burn TorqueUSD, with cross-chain support
    /// @dev Overrides both OFT and ERC20 _burn functions for compatibility
    /// @param from The address from which TorqueUSD will be burned
    /// @param amount The amount of TorqueUSD to burn
    function _burn(address from, uint256 amount) internal override(OFT, ERC20) {
        super._burn(from, amount);
    }

    /// @notice Handles the debit of TorqueUSD during cross-chain transactions
    /// @dev Overrides the OFT _debitFrom function for cross-chain compatibility
    /// @param _from The address from which TorqueUSD will be debited
    /// @param _amount The amount of TorqueUSD to debit
    function _debitFrom(address _from, uint16, bytes memory, uint256 _amount) internal override {
        _burn(_from, _amount);
    }

    /// @notice Handles the credit of TorqueUSD during cross-chain transactions
    /// @dev Overrides the OFT _creditTo function for cross-chain compatibility
    /// @param _to The address receiving the credited TorqueUSD
    /// @param _amount The amount of TorqueUSD to credit
    function _creditTo(uint16, address _to, uint256 _amount) internal override {
        _mint(_to, _amount);
    }
}
