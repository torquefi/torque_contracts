// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

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