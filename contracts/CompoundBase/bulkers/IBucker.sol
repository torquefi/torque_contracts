// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

interface IBucker {
    function invoke(uint[] calldata actions, bytes[] calldata data) external payable;
}