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

contract Torque is ERC20Burnable, ERC20Permit, ERC20Votes, OFT, Ownable {
    
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint) ERC20Permit(_name) Ownable(_delegate) {
        uint256 initialSupply = 1_000_000_000_000 * 10 ** decimals();
        _mint(_delegate, initialSupply);
        emit Minted(_delegate, initialSupply);
    }

    // Override functions required by Solidity for ERC20Votes, OFT, and ERC20 compatibility.

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes, OFT) {
        super._mint(to, amount);
        emit Minted(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes, OFT) {
        super._burn(account, amount);
        emit Burned(account, amount);
    }
}
