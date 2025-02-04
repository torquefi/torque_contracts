# TorqueSplitter Contract

## Overview

The `TorqueSplitter` is a smart contract that strategically allocates user deposits among various yield-generating strategies. It also handles interactions with a reward management system to distribute multiple types of tokens (COMP, TORQ, POL) based on user activities such as deposits and withdrawals.

## Key Features

- **Multiple Yield Strategies**: Funds are distributed across strategies based on predefined allocations.
- **Dynamic Reward Management**: Integrates with multiple reward contracts to handle rewards for deposits and withdrawals.
- **Token Rewards**: Users can accrue rewards in three types of tokens: COMP, TORQ, and POL, which are managed through separate reward manager contracts.
- **Flexible Strategy Management**: Allows the owner to update strategy allocations dynamically to optimize returns.

## Contract Interfaces

### IYieldStrategy

- **deposit(uint256 amount)**: Deposits funds into the yield-generating strategy.
- **withdraw(uint256 amount)**: Withdraws funds from the strategy.

### IRewardManager

- **updateDepositRewards(address user, uint256 amount)**: Updates the reward balance for a user upon deposit.
- **updateWithdrawRewards(address user, uint256 amount)**: Updates the reward balance for a user upon withdrawal.

## Contract Deployment

### Constructor Parameters

- `_strategies`: Array of addresses for the yield strategies.
- `_ratios`: Allocation ratios corresponding to each strategy.
- `_rewardManager`: Addresses of the reward manager contracts for COMP, TORQ, and POL.

Ensure that the sum of all ratios in `_ratios` is 100.

## Functions

### Public and External

- **deposit()**: Allows users to deposit ETH, which is then allocated across strategies based on the set ratios.
- **withdraw(uint256[] amounts)**: Allows users to withdraw their funds from each strategy. Withdrawals are flexible, permitting partial or complete withdrawals from selected strategies.
- **updateStrategies(address[] _strategies, uint256[] _ratios)**: Updates the strategies and their ratios (onlyOwner). This function allows the contract owner to adjust strategies based on performance or other criteria dynamically.

## Events

- **StrategiesUpdated**: Emitted when the strategies are updated.
- **DepositMade**: Emitted when a deposit is made.
- **WithdrawalMade**: Emitted when a withdrawal is made.

## Security Features

- **ReentrancyGuard**: Protects against reentrancy attacks.
- **Ownable**: Restricts the execution of certain functions to the owner of the contract, ensuring controlled access to critical functionalities.

## Setup and Testing

Deploy the contract using Remix, Truffle, or Hardhat with the constructor parameters set according to your strategy setup. Ensure to test on testnets (e.g., Rinkeby, Ropsten) before deploying to the mainnet to verify functionality and security.

## Additional Notes

Adjusting strategies or allocations post-deployment involves not only updating the strategies via `updateStrategies` but also manually migrating funds to align with new ratios, ensuring the new allocations reflect the updated investment goals.