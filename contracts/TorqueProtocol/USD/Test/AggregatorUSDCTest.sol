// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract AggregatorUSDCTest {
    int256 public _answer = 100000000;
    address immutable owner;

    modifier onlyOwner(address _sender) {
        require(_sender == owner, "Not allowed");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = 1;
        answeredInRound = 1;
        answer = _answer;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
    }

    function updatePrice(int256 _price) public onlyOwner(msg.sender) {
        _answer = _price;
    }
}