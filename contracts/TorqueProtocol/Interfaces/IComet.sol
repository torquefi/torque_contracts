// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IComet {
    function supply(address asset, uint amount) external;

    function withdraw(address asset, uint amount) external;
}
