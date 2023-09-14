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
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./../Interfaces/IStakingTorque.sol";

contract StakingTorque is ERC20, Ownable, AccessControl, IStakingTorque {
    uint256 public constant TOTAL_SUPPLY = 1000000 ether;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor() ERC20("StakingTorque", "sTORQ") {}

    function mint(address _to, uint256 _amount) public {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) public {
        require(hasRole(BURNER_ROLE, msg.sender), "Caller is not a burner");
        _burn(_from, _amount);
    }

    function grantMintRole(address _minter) public onlyOwner {
        _grantRole(MINTER_ROLE, _minter);
    }

    function revokeMintRole(address _oldMinter) public onlyOwner {
        _revokeRole(MINTER_ROLE, _oldMinter);
    }

    function grantBurnRole(address _burner) public onlyOwner {
        _grantRole(BURNER_ROLE, _burner);
    }

    function revokeBurnRole(address _oldBurner) public onlyOwner {
        _revokeRole(BURNER_ROLE, _oldBurner);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override(ERC20, IStakingTorque) returns (bool) {
        return ERC20.transferFrom(from, to, amount);
    }
}
