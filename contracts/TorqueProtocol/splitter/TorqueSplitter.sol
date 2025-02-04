// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IYieldStrategy Interface
 * @notice Interface for yield strategy contracts that the TorqueSplitter will interact with.
 * @dev Allows the TorqueSplitter to deposit into and withdraw from various yield-generating strategies.
 */
interface IYieldStrategy {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
}

/**
 * @title IRewardManager Interface
 * @notice Interface for managing reward tokens within the Torque ecosystem.
 * @dev Updates reward balances upon deposit and withdrawal activities, ensuring accurate reward accrual.
 */
interface IRewardManager {
    function updateDepositRewards(address user, uint256 amount) external;
    function updateWithdrawRewards(address user, uint256 amount) external;
}

/**
 * @title Torque Splitter Contract -- WIP
 * @notice Manages the distribution of funds among various yield strategies and handles interactions with the reward system.
 * @dev Integrates with multiple reward managers to update rewards based on user deposits and withdrawals.
 */
contract TorqueSplitter is Ownable, ReentrancyGuard {
    struct Strategy {
        IYieldStrategy strategy;
        uint256 ratio;
    }

    Strategy[] public strategies;
    IRewardManager public compRewardManager;
    IRewardManager public torqRewardManager;
    IRewardManager public polRewardManager;

    event StrategiesUpdated();
    event DepositMade(address indexed depositor, uint256 amount);
    event WithdrawalMade(address indexed withdrawer, uint256 amount);

    /**
     * @dev Initializes the TorqueSplitter with strategies, ratios, and reward managers.
     * @param _strategies Addresses of the yield strategies.
     * @param _ratios Allocation ratios for each strategy.
     * @param _compRewardManager Address of the COMP reward manager.
     * @param _torqRewardManager Address of the TORQ reward manager.
     * @param _polRewardManager Address of the POL reward manager.
     */
    constructor(
        address[] memory _strategies,
        uint256[] memory _ratios,
        address _compRewardManager,
        address _torqRewardManager,
        address _polRewardManager
    ) {
        require(_strategies.length == _ratios.length, "Mismatched arrays");
        require(_strategies.length <= 8, "Cannot exceed 8 strategies");

        uint256 totalRatio = 0;
        for (uint i = 0; i < _strategies.length; i++) {
            require(_strategies[i] != address(0), "Invalid strategy address");
            strategies.push(Strategy({ strategy: IYieldStrategy(_strategies[i]), ratio: _ratios[i] }));
            totalRatio += _ratios[i];
        }
        require(totalRatio == 100, "Total ratio must sum to 100%");

        compRewardManager = IRewardManager(_compRewardManager);
        torqRewardManager = IRewardManager(_torqRewardManager);
        polRewardManager = IRewardManager(_polRewardManager);
    }

    /**
     * @notice Deposits Ether and distributes it among configured strategies according to their allocation ratios.
     * @dev Also updates deposit rewards for each strategy through the respective reward managers.
     */
    function deposit() external payable nonReentrant {
        require(msg.value > 0, "Deposit must be greater than 0");
        uint256 totalDeposited = msg.value;

        for (uint i = 0; i < strategies.length; i++) {
            uint256 depositAmount = totalDeposited * strategies[i].ratio / 100;
            strategies[i].strategy.deposit{value: depositAmount}();
            compRewardManager.updateDepositRewards(msg.sender, depositAmount);
            torqRewardManager.updateDepositRewards(msg.sender, depositAmount);
            polRewardManager.updateDepositRewards(msg.sender, depositAmount);
        }

        emit DepositMade(msg.sender, totalDeposited);
    }

    /**
     * @notice Allows users to withdraw specified amounts from their respective strategies.
     * @param amounts The amounts to withdraw from each strategy.
     * @dev Updates withdrawal rewards for each strategy through the respective reward managers.
     */
    function withdraw(uint256[] memory amounts) public nonReentrant {
        require(amounts.length == strategies.length, "Mismatched withdrawal array");
        uint256 totalWithdrawn = 0;

        for (uint i = 0; i < strategies.length; i++) {
            strategies[i].strategy.withdraw(amounts[i]);
            compRewardManager.updateWithdrawRewards(msg.sender, amounts[i]);
            torqRewardManager.updateWithdrawRewards(msg.sender, amounts[i]);
            polRewardManager.updateWithdrawRewards(msg.sender, amounts[i]);
            totalWithdrawn += amounts[i];
        }

        emit WithdrawalMade(msg.sender, totalWithdrawn);
    }

    /**
     * @notice Updates the strategies and their corresponding ratios.
     * @param _strategies New list of strategy addresses.
     * @param _ratios New list of allocation ratios.
     * @dev Only callable by the owner. Emits the StrategiesUpdated event upon successful update.
     */
    function updateStrategies(address[] memory _strategies, uint256[] memory _ratios) public onlyOwner {
        require(_strategies.length == _ratios.length, "Mismatched arrays");
        require(_strategies.length <= 8, "Cannot exceed 8 strategies");

        delete strategies;
        uint256 totalRatio = 0;
        for (uint i = 0; i < _strategies.length; i++) {
            require(_strategies[i] != address(0), "Invalid strategy address");
            strategies.push(Strategy({
                strategy: IYieldStrategy(_strategies[i]),
                ratio: _ratios[i]
            }));
            totalRatio += _ratios[i];
        }
        require(totalRatio == 100, "Total ratio must sum to 100%");
        emit StrategiesUpdated();
    }
}
