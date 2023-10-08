// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDCTest is ERC20 {
    constructor() ERC20("USDC TEST", "USDC") {
        _mint(msg.sender, 1000000 ether);
    }
}
