// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TUSD is ERC20Burnable, Ownable {
    error TUSD__AmountMustBeMoreThanZero();
    error TUSD__BurnAmountExceedsBalance();
    error TUSD__NotZeroAddress();

    constructor(address initialOwner) ERC20("Torque USD", "TUSD") Ownable(initialOwner) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert TUSD__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert TUSD__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert TUSD__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert TUSD__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
