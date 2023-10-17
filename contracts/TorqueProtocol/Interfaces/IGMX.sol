// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IGMX {
    // TO-DO Research for GMX integration
    function createDeposit(uint256 _amount) external payable returns (uint256);

    function createWithdrawal(uint256 _amount) external payable returns (uint256);
}
