// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

interface IARBBulker {
    function invoke(bytes32[] calldata actions, bytes[] calldata data) external payable ;
}