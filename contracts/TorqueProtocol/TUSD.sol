// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

    address controller;

    error TUSD__AmountMustBeMoreThanZero();
    error TUSD__BurnAmountExceedsBalance();
    error TUSD__NotZeroAddress();

    constructor() ERC20("Torque USD", "TUSD") Ownable(msg.sender) {}


    function setController(address _controller) external onlyOwner {
      controller = _controller;
    }

    function burn(uint256 _amount) public override {
        require(msg.sender == controller, "you do not have the permission");
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert TUSD__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert TUSD__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external returns (bool) {
        require(msg.sender == controller, "you do not have the permission");
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
