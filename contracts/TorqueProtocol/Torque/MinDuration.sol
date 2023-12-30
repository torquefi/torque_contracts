// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";

contract MinDuration is Ownable {
    uint256 public unlockBlock;
    uint256 public earlyExitFeePercentage = 20;

    event MinDurationVerified(uint256 amount, uint256 when);

    constructor(uint256 _unlockBlock) payable {
        require(block.number < _unlockBlock, "Unlock block should be in the future");
        unlockBlock = _unlockBlock;
    }

    function isDurationMet() external {
        require(block.number >= unlockBlock, "Minimum duration not yet reached, but you can still withdraw.");
        uint256 balanceToTransfer = address(this).balance;
        if (block.number < unlockBlock + 7 * 24 * 60 * 4) {
            uint256 earlyExitFee = (balanceToTransfer * earlyExitFeePercentage) / 100;
            balanceToTransfer -= earlyExitFee;
        }
        owner().transfer(balanceToTransfer);
        emit MinDurationVerified(balanceToTransfer, block.number);
    }

    function setEarlyExitFeePercentage(uint256 _percentage) external onlyOwner {
        require(_percentage <= 100, "Percentage should be <= 100");
        earlyExitFeePercentage = _percentage;
    }
}
