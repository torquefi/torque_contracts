// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH9 is IERC20{

    receive() external payable;

    function deposit() external payable;

    function withdraw(uint wad) external;
}