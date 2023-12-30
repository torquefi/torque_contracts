// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IGMX {
    function createDeposit(uint256 _amount) external payable returns (uint256);

    function createWithdrawal(uint256 _amount) external payable returns (uint256);
}