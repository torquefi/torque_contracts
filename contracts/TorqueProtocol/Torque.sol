// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/// @title Torque (TORQ) Token Contract
/// @notice This contract represents the Torque token, an ERC-20 compliant token with burning, voting, and LayerZero omnichain functionality.
/// @dev Inherits from ERC20Burnable, ERC20Permit, ERC20Votes, and OFT to provide extended functionality.
contract Torque is ERC20Burnable, ERC20Permit, ERC20Votes, OFT, Ownable {
    
    /// @notice Emitted when tokens are minted.
    /// @param to The address receiving the minted tokens.
    /// @param amount The amount of tokens minted.
    event Minted(address indexed to, uint256 amount);

    /// @notice Emitted when tokens are burned.
    /// @param from The address from which the tokens were burned.
    /// @param amount The amount of tokens burned.
    event Burned(address indexed from, uint256 amount);

    /// @notice Constructor to initialize the Torque token contract.
    /// @param _name The name of the token (e.g., "Torque Token").
    /// @param _symbol The symbol of the token (e.g., "TORQ").
    /// @param _lzEndpoint The LayerZero endpoint address for omnichain functionality.
    /// @param _delegate The initial owner and delegate for the contract.
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint) ERC20Permit(_name) Ownable(_delegate) {
        // Set the initial supply to 1 trillion tokens, with standard decimals (18).
        uint256 initialSupply = 1_000_000_000_000 * 10 ** decimals();

        // Mint the initial supply to the delegate address.
        _mint(_delegate, initialSupply);

        // Emit a Minted event to log the initial minting.
        emit Minted(_delegate, initialSupply);
    }

    // --- Overrides required by Solidity for ERC20Votes, OFT, and ERC20 compatibility ---

    /// @notice Handles actions required after token transfers.
    /// @dev Ensures compatibility with ERC20Votes and OFT extensions.
    /// @param from The address sending the tokens.
    /// @param to The address receiving the tokens.
    /// @param amount The amount of tokens transferred.
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    /// @notice Mints new tokens to a specified address.
    /// @dev Overrides the _mint function to integrate ERC20Votes and OFT functionality.
    /// @param to The address to receive the newly minted tokens.
    /// @param amount The amount of tokens to mint.
    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes, OFT) {
        super._mint(to, amount);
        emit Minted(to, amount);
    }

    /// @notice Burns tokens from a specified address.
    /// @dev Overrides the _burn function to integrate ERC20Votes and OFT functionality.
    /// @param account The address from which the tokens are burned.
    /// @param amount The amount of tokens to burn.
    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes, OFT) {
        super._burn(account, amount);
        emit Burned(account, amount);
    }
}
