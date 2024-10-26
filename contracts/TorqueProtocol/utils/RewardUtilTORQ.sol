// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title RewardUtilTORQ
/// @notice This contract handles the reward distribution within the Torque ecosystem based on user deposits and borrowings.
/// @dev The contract manages rewards for users who interact with various Torque contracts.
contract RewardUtilTORQ is ReentrancyGuard, Ownable { 
    using SafeMath for uint256;

    /// @notice Struct representing the reward configuration for each Torque contract
    /// @param rewardFactor The factor used to calculate rewards for deposits
    /// @param torquePool The total reward pool allocated for the contract
    /// @param borrowFactor The factor used to calculate rewards for borrowings
    struct RewardConfig {
        uint256 rewardFactor;
        uint256 torquePool;
        uint256 borrowFactor; 
    }

    /// @notice Struct representing user's reward details
    /// @param rewardAmount The total reward accumulated by the user
    /// @param depositAmount The total amount deposited by the user
    /// @param borrowAmount The total amount borrowed by the user
    /// @param lastRewardBlock The block number when the last reward was updated
    /// @param isActive Indicates if the user is actively earning rewards
    struct UserRewardConfig {
        uint256 rewardAmount;
        uint256 depositAmount;
        uint256 borrowAmount;
        uint256 lastRewardBlock;
        bool isActive;
    }

    /// @notice The Torque Token (TORQ) used for rewards
    IERC20 public torqToken;
    /// @notice The address of the governor managing the reward distribution
    address public governor;
    /// @notice Indicates whether claims are paused
    bool public claimsPaused = false;

    /// @notice Maps an address to a boolean indicating if it is a valid Torque contract
    mapping(address => bool) public isTorqueContract;
    /// @notice Maps each Torque contract to its reward configuration
    mapping(address => RewardConfig) public rewardConfig;
    /// @notice Maps each user to their reward information for each Torque contract
    mapping(address => mapping(address => UserRewardConfig)) public rewardsClaimed;

    /// @notice Emitted when the governor is transferred
    /// @param oldGovernor The previous governor's address
    /// @param newGovernor The new governor's address
    event GovernorTransferred(address indexed oldGovernor, address indexed newGovernor);

    /// @notice Emitted when a reward is claimed by a user
    /// @param user The address of the user claiming the reward
    /// @param torqueContract The Torque contract from which the reward is claimed
    /// @param amount The amount of reward claimed
    event RewardClaimed(address indexed user, address indexed torqueContract, uint256 amount);

    /// @notice Emitted when the reward factor is updated
    /// @param torqueContract The Torque contract for which the factor is updated
    /// @param rewardFactor The new reward factor
    event RewardFactorUpdated(address indexed torqueContract, uint256 rewardFactor);

    /// @notice Emitted when the borrow factor is updated
    /// @param torqueContract The Torque contract for which the factor is updated
    /// @param borrowFactor The new borrow factor
    event BorrowFactorUpdated(address indexed torqueContract, uint256 borrowFactor);

    /// @notice Emitted when the Torque pool is updated
    /// @param torqueContract The Torque contract for which the pool is updated
    /// @param poolAmount The new reward pool amount
    event TorquePoolUpdated(address torqueContract, uint256 poolAmount);

    /// @notice Emitted when a new Torque contract is added
    /// @param torqueContract The newly added Torque contract
    /// @param poolAmount The reward pool allocated to the contract
    /// @param rewardFactor The reward factor for the contract
    /// @param borrowFactor The borrow factor for the contract
    event TorqueContractAdded(address torqueContract, uint256 poolAmount, uint256 rewardFactor, uint256 borrowFactor);

    /// @notice Error for unauthorized actions
    /// @param sender The address attempting the unauthorized action
    error NotPermitted(address sender);

    /// @notice Error for invalid Torque contracts
    /// @param contractAddr The address of the invalid contract
    error InvalidTorqueContract(address contractAddr);

    /// @notice Constructor to initialize the contract with the TORQ token and governor
    /// @param _torqTokenAddress The address of the TORQ token
    /// @param _governor The initial governor address
    constructor(address _torqTokenAddress, address _governor) Ownable(msg.sender) {
        require(_torqTokenAddress != address(0), "Invalid TORQ token address");
        torqToken = IERC20(_torqTokenAddress);
        governor = _governor;
    }

    /// @notice Modifier to restrict function calls to the governor only
    modifier onlyGovernor() {
        if (msg.sender != governor) revert NotPermitted(msg.sender);
        _;
    }

    /// @notice Updates user's reward information upon deposit
    /// @param _userAddress The address of the user
    /// @param _depositAmount The amount of the deposit
    function userDepositReward(address _userAddress, uint256 _depositAmount) external {
        require(isTorqueContract[msg.sender], "Unauthorized!");
        updateReward(msg.sender, _userAddress);
        rewardsClaimed[msg.sender][_userAddress].depositAmount = rewardsClaimed[msg.sender][_userAddress].depositAmount.add(_depositAmount);
        rewardsClaimed[msg.sender][_userAddress].lastRewardBlock = block.number;
        rewardsClaimed[msg.sender][_userAddress].isActive = true;
    }

    /// @notice Updates user's reward information upon borrow
    /// @param _userAddress The address of the user
    /// @param _borrowAmount The amount of the borrow
    function userDepositBorrowReward(address _userAddress, uint256 _borrowAmount) external {
        require(isTorqueContract[msg.sender], "Unauthorized!");
        updateReward(msg.sender, _userAddress);
        rewardsClaimed[msg.sender][_userAddress].borrowAmount = rewardsClaimed[msg.sender][_userAddress].borrowAmount.add(_borrowAmount);
        rewardsClaimed[msg.sender][_userAddress].lastRewardBlock = block.number;
        rewardsClaimed[msg.sender][_userAddress].isActive = true;
    }

    /// @notice Allows users to withdraw deposited rewards
    /// @param _userAddress The address of the user
    /// @param _withdrawAmount The amount to withdraw
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external {
        require(isTorqueContract[msg.sender], "Unauthorized!");
        require(_withdrawAmount <= rewardsClaimed[msg.sender][_userAddress].depositAmount, "Cannot withdraw more than deposit!");
        updateReward(msg.sender, _userAddress);
        rewardsClaimed[msg.sender][_userAddress].depositAmount = rewardsClaimed[msg.sender][_userAddress].depositAmount.sub(_withdrawAmount);
        if (rewardsClaimed[msg.sender][_userAddress].depositAmount == 0 && rewardsClaimed[msg.sender][_userAddress].borrowAmount == 0) {
            rewardsClaimed[msg.sender][_userAddress].isActive = false;
        }
    }

    /// @notice Allows users to withdraw borrowed rewards
    /// @param _userAddress The address of the user
    /// @param _withdrawBorrowAmount The amount to withdraw from borrowed rewards
    function userWithdrawBorrowReward(address _userAddress, uint256 _withdrawBorrowAmount) external {
        require(isTorqueContract[msg.sender], "Unauthorized!");
        require(_withdrawBorrowAmount <= rewardsClaimed[msg.sender][_userAddress].borrowAmount, "Cannot withdraw more than borrow!");
        updateReward(msg.sender, _userAddress);
        rewardsClaimed[msg.sender][_userAddress].borrowAmount = rewardsClaimed[msg.sender][_userAddress].borrowAmount.sub(_withdrawBorrowAmount);
        if (rewardsClaimed[msg.sender][_userAddress].depositAmount == 0 && rewardsClaimed[msg.sender][_userAddress].borrowAmount == 0) {
            rewardsClaimed[msg.sender][_userAddress].isActive = false;
        }
    }

    /// @notice Updates the reward factor for a Torque contract
    /// @param torqueContract The address of the Torque contract
    /// @param _rewardFactor The new reward factor
    function setRewardFactor(address torqueContract, uint256 _rewardFactor) public onlyGovernor {
        rewardConfig[torqueContract].rewardFactor = _rewardFactor;
        emit RewardFactorUpdated(torqueContract, _rewardFactor);
    }

    /// @notice Updates the reward pool for a Torque contract
    /// @param _torqueContract The address of the Torque contract
    /// @param _poolAmount The new reward pool amount
    function setTorquePool(address _torqueContract, uint256 _poolAmount) public onlyGovernor {
        rewardConfig[_torqueContract].torquePool = _poolAmount;
        emit TorquePoolUpdated(_torqueContract, _poolAmount);
    }

    /// @notice Updates the borrow factor for a Torque contract
    /// @param _torqueContract The address of the Torque contract
    /// @param _borrowFactor The new borrow factor
    function setBorrowFactor(address _torqueContract, uint256 _borrowFactor) public onlyGovernor {
        rewardConfig[_torqueContract].borrowFactor = _borrowFactor;
        emit BorrowFactorUpdated(_torqueContract, _borrowFactor);
    }

    /// @notice Updates the reward for a user on a specified contract
    /// @param torqueContract The Torque contract
    /// @param user The address of the user
    function updateReward(address torqueContract, address user) internal nonReentrant {
        _calculateAndUpdateReward(torqueContract, user);
    }

    /// @notice Changes the address of the TORQ token
    /// @param _torqueToken The new TORQ token address
    function updateTorqueToken(address _torqueToken) external onlyGovernor {
        torqToken = IERC20(_torqueToken);
    }

    /// @notice Adds a new Torque contract for reward distribution
    /// @param _address The address of the new Torque contract
    /// @param _rewardPool The reward pool allocated to the contract
    /// @param _rewardFactor The reward factor for the contract
    /// @param _borrowFactor The borrow factor for the contract
    function addTorqueContract(address _address, uint256 _rewardPool, uint256 _rewardFactor, uint256 _borrowFactor) public onlyOwner {
        if (_rewardFactor == 0) revert InvalidTorqueContract(_address);
        isTorqueContract[_address] = true;
        rewardConfig[_address].rewardFactor = _rewardFactor;
        rewardConfig[_address].borrowFactor = _borrowFactor;
        rewardConfig[_address].torquePool = _rewardPool;

        emit TorqueContractAdded(_address, _rewardPool, _rewardFactor, _borrowFactor);
    }

    /// @notice Calculates and updates borrow rewards for a user
    /// @param _torqueContract The Torque contract
    /// @param _userAddress The user's address
    function _calculateAndUpdateBorrowReward(address _torqueContract, address _userAddress) internal {
        uint256 blocks = block.number - rewardsClaimed[_torqueContract][_userAddress].lastRewardBlock;
        uint256 userReward = blocks.mul(rewardsClaimed[_torqueContract][_userAddress].borrowAmount);
        userReward = userReward.mul(rewardConfig[_torqueContract].torquePool);
        userReward = userReward.div(rewardConfig[_torqueContract].borrowFactor);
        rewardsClaimed[_torqueContract][_userAddress].rewardAmount = rewardsClaimed[_torqueContract][_userAddress].rewardAmount.add(userReward);
    }

    /// @notice Calculates and updates rewards for a user based on deposits and borrows
    /// @param _torqueContract The Torque contract
    /// @param _userAddress The user's address
    function _calculateAndUpdateReward(address _torqueContract, address _userAddress) internal {
        if (!rewardsClaimed[_torqueContract][_userAddress].isActive) return;

        uint256 blocks = block.number - rewardsClaimed[_torqueContract][_userAddress].lastRewardBlock;
        uint256 userReward = blocks.mul(rewardsClaimed[_torqueContract][_userAddress].depositAmount);
        userReward = userReward.mul(rewardConfig[_torqueContract].torquePool);
        userReward = userReward.div(rewardConfig[_torqueContract].rewardFactor);

        if (rewardConfig[_torqueContract].borrowFactor > 0 && rewardsClaimed[_torqueContract][_userAddress].borrowAmount > 0) {
            _calculateAndUpdateBorrowReward(_torqueContract, _userAddress);
        }

        rewardsClaimed[_torqueContract][_userAddress].lastRewardBlock = block.number;
        rewardsClaimed[_torqueContract][_userAddress].rewardAmount = rewardsClaimed[_torqueContract][_userAddress].rewardAmount.add(userReward);
    }

    /// @notice Calculates borrow reward for a user
    /// @param _torqueContract The Torque contract
    /// @param _userAddress The user's address
    /// @return userReward The calculated borrow reward
    function _calculateBorrowReward(address _torqueContract, address _userAddress) internal view returns (uint256) {
        uint256 blocks = block.number - rewardsClaimed[_torqueContract][_userAddress].lastRewardBlock;
        uint256 userReward = blocks.mul(rewardsClaimed[_torqueContract][_userAddress].borrowAmount);
        userReward = userReward.mul(rewardConfig[_torqueContract].torquePool);
        userReward = userReward.div(rewardConfig[_torqueContract].borrowFactor);
        return userReward;
    }

    /// @notice Calculates the total reward for a user including deposit and borrow rewards
    /// @param _torqueContract The Torque contract
    /// @param _userAddress The user's address
    /// @return The total calculated reward
    function _calculateReward(address _torqueContract, address _userAddress) public view returns (uint256) {
        uint256 blocks = block.number - rewardsClaimed[_torqueContract][_userAddress].lastRewardBlock;
        uint256 userReward = blocks.mul(rewardsClaimed[_torqueContract][_userAddress].depositAmount); 
        userReward = userReward.mul(rewardConfig[_torqueContract].torquePool);
        userReward = userReward.div(rewardConfig[_torqueContract].rewardFactor);
        uint256 borrowReward;

        if (rewardConfig[_torqueContract].borrowFactor > 0 && rewardsClaimed[_torqueContract][_userAddress].borrowAmount > 0) {
            borrowReward = _calculateBorrowReward(_torqueContract, _userAddress);
        }

        return borrowReward + userReward + rewardsClaimed[_torqueContract][_userAddress].rewardAmount;
    }

    /// @notice Claims rewards for a user across multiple Torque contracts
    /// @param _torqueContract An array of Torque contracts to claim rewards from
    function claimReward(address[] memory _torqueContract) external {
        require(!claimsPaused, "Claims are paused!");
        uint256 rewardAmount = 0;

        for (uint i = 0; i < _torqueContract.length; i++) {
            updateReward(_torqueContract[i], msg.sender);
            rewardAmount = rewardAmount.add(rewardsClaimed[_torqueContract[i]][msg.sender].rewardAmount);
            rewardsClaimed[_torqueContract[i]][msg.sender].rewardAmount = 0;
        }

        require(torqToken.balanceOf(address(this)) >= rewardAmount, "Insufficient TORQ");
        require(rewardAmount > 0, "No rewards found!");
        require(torqToken.transfer(msg.sender, rewardAmount), "Transfer failed");
    }

    /// @notice Transfers the governor role to a new address
    /// @param newGovernor The new governor address
    function transferGovernor(address newGovernor) external onlyGovernor {
        address oldGovernor = governor;
        governor = newGovernor;
        emit GovernorTransferred(oldGovernor, newGovernor);
    }

    /// @notice Pauses or unpauses reward claims
    /// @param _pause Boolean indicating whether to pause or unpause claims
    function pauseClaims(bool _pause) external onlyGovernor {
        claimsPaused = _pause;
    }

    /// @notice Allows the owner to withdraw TORQ tokens from the contract
    /// @param _amount The amount of TORQ to withdraw
    function withdrawTorque(uint256 _amount) external onlyOwner {
        require(torqToken.transfer(msg.sender, _amount), "Transfer failed");
    }

    /// @notice Gets the reward configuration for a user in a specific Torque contract
    /// @param _torqueContract The Torque contract
    /// @param _user The user's address
    /// @return UserRewardConfig The user's reward configuration
    function getRewardConfig(address _torqueContract, address _user) public view returns (UserRewardConfig memory) {
        return rewardsClaimed[_torqueContract][_user];
    }
}
