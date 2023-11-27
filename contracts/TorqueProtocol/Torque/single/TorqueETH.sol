// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IWETH.sol";

interface IGMXV2ETH {
    function handleDeposit(uint256 amount) external;

    function handleWithdrawal(uint256 amount) external returns (uint256);
}

interface IStargateETH {
    function handleDeposit(uint256 amount) external;

    function handleWithdrawal(uint256 amount) external returns (uint256);
}

contract TorqueETH is ERC20, Ownable, ReentrancyGuard {
    IWETH public immutable weth;

    IGMXV2ETH public gmxV2Eth;
    IStargateETH public stargateEth;
    address treasuryAddress;

    event Deposited(address indexed user, uint256 amount, bool isETH);
    event Withdrawn(address indexed user, uint256 amount, bool toETH);
    event PerformanceFeeCaptured(address indexed user, uint256 amount);

    constructor(address wethAddress) ERC20("TorqueETH", "tETH") {
        weth = IWETH(wethAddress);
    }

    function setChildVaults(address _gmxV2Eth, address _stargateEth) external onlyOwner {
        gmxV2Eth = IGMXV2ETH(_gmxV2Eth);
        stargateEth = IStargateETH(_stargateEth);
    }

    uint256 private lastCaptureTime;

    function capturePerformanceFee() public {
        require(
            block.timestamp - lastCaptureTime >= 12 hours,
            "Minimum duration of 12 hours has not passed yet"
        );
        lastCaptureTime = block.timestamp;

        uint256 balanceBefore = weth.balanceOf(address(this));
        // Call the logic for compound Stargate and GMX rewards here
        // ...

        uint256 balanceAfter = weth.balanceOf(address(this));
        uint256 earnings = balanceAfter - balanceBefore;
        uint256 fee = (earnings * 20) / 100;
        weth.transfer(treasuryAddress, fee);

        emit PerformanceFeeCaptured(treasuryAddress, fee);
    }

    // Deposit function handles both ETH and WETH deposits
    function deposit(uint256 amount, bool useETH) external payable nonReentrant {
        require(amount > 0, "Cannot deposit 0");
        if (useETH) {
            require(msg.value == amount, "ETH value sent is not correct");
            weth.deposit{ value: amount }(); // Wrap ETH to WETH
        } else {
            require(msg.value == 0, "Do not send ETH");
            weth.transferFrom(msg.sender, address(this), amount); // Transfer WETH from user
        }

        // Mint tETH to the user as a receipt
        _mint(msg.sender, amount);

        // Distribute WETH to child vaults
        distributeToChildVaults(amount);

        emit Deposited(msg.sender, amount, useETH);
    }

    function distributeToChildVaults(uint256 amount) internal {
        // Logic for distributing deposits to child vaults would go here
        // For example, split the amount between GMXV2ETH and StargateETH
        uint256 half = amount / 2;
        weth.transfer(address(gmxV2Eth), half);
        weth.transfer(address(stargateEth), amount - half);

        gmxV2Eth.handleDeposit(half);
        stargateEth.handleDeposit(amount - half);
    }

    uint256 private lastWithdrawalTime;

    function withdraw(uint256 amount) external nonReentrant {
        require(amount <= balanceOf(msg.sender), "Insufficient balance");
        require(amount > 0, "Cannot withdraw 0");

        // Check if minimum duration of deposit has passed
        require(
            block.timestamp - lastCaptureTime >= 7 days,
            "Minimum duration of 7 days has not passed yet"
        );

        // Burn tETH from user's balance
        _burn(msg.sender, amount);

        // Logic for withdrawing assets from child vaults would go here
        // This involves distributing the withdrawal request across both
        uint256 withdrawnAmount = gmxV2Eth.handleWithdrawal(amount / 2);
        withdrawnAmount += stargateEth.handleWithdrawal(amount - withdrawnAmount);

        // Calculate management fee based on duration of deposit
        uint256 fee = 0;
        if (lastWithdrawalTime != 0) {
            uint256 depositDuration = block.timestamp - lastWithdrawalTime;
            if (depositDuration < 7 days) {
                fee = (withdrawnAmount * 20) / 100; // Early exit fee is 20%
            } else {
                fee = (withdrawnAmount * 2) / 100; // Default fee is 2%
            }
        }
        lastWithdrawalTime = block.timestamp;

        // Transfer management fee to treasury
        weth.transfer(treasuryAddress, fee);

        // Return WETH or ETH to user
        if (block.timestamp - lastCaptureTime < 7 days) {
            // If the user is withdrawing before the minimum duration, they must pay the early exit fee
            weth.transfer(msg.sender, withdrawnAmount - fee);
        } else {
            // If the user is withdrawing after the minimum duration, they don't have to pay the early exit fee
            weth.transfer(msg.sender, withdrawnAmount);
        }

        emit Withdrawn(msg.sender, withdrawnAmount, false);
    }

    // Allow contract to receive ETH
    receive() external payable {
        require(msg.sender == address(weth), "Direct deposit of ETH not allowed");
    }
}
