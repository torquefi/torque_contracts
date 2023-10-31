// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ICometReward {
    function claim(address comet, address src, bool shouldAccrue) external;
}