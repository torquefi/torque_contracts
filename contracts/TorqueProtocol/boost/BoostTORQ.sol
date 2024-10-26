// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./strategies/UniswapTORQ.sol";

interface RewardUtilTORQ {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
}

/// @title BoostTORQ - TORQ Yield Aggregation Contract
/// @notice Manages TORQ deposits, withdrawals, and compounding within the Uniswap and GMX protocols.
contract BoostTORQ is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;

    event Deposited(address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    
    IERC20 public torqToken;                // TORQ token interface
    UniswapTORQ public uniswapTorq;        // Uniswap TORQ contract interface
    address public treasury;                // Treasury address for fees
    RewardUtilTORQ public torqRewardUtil;   // Rewards utility contract interface

    uint256 public gmxAllocation;           // Allocation percentage for GMX
    uint256 public uniswapAllocation = 100; // Allocation percentage for Uniswap
    uint256 public lastCompoundTimestamp;   // Last timestamp for compounding
    uint256 public performanceFee = 10;     // Performance fee percentage
    uint256 public minTorqAmount = 10e24;   // Minimum amount of TORQ for operations
    uint256 public treasuryFee = 0;         // Accumulated treasury fees

    uint256 public totalAssetsAmount = 0;   // Total assets managed by the contract
    uint256 public compoundTorqAmount = 0;  // Amount of TORQ available for compounding

    /// @notice Initializes the BoostTORQ contract
    /// @param _name Name of the ERC20 token
    /// @param _symbol Symbol of the ERC20 token
    /// @param TORQ Address of the TORQ token
    /// @param _uniswapTorqAddress Address of the Uniswap TORQ contract
    /// @param _treasury Address of the treasury
    /// @param _torqRewardUtil Address of the rewards utility contract
    constructor(
        string memory _name, 
        string memory _symbol,
        address TORQ,
        address _uniswapTorqAddress,
        address _treasury,
        address _torqRewardUtil
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        torqToken = IERC20(TORQ);
        uniswapTorq = UniswapTORQ(_uniswapTorqAddress);
        treasury = _treasury;
        torqRewardUtil = RewardUtilTORQ(_torqRewardUtil);
    }

    /// @notice Deposits TORQ into the BoostTORQ contract
    /// @param depositAmount Amount of TORQ to deposit
    function depositTORQ(uint256 depositAmount) external payable nonReentrant {
        require(torqToken.balanceOf(address(this)) >= compoundTorqAmount, "Insufficient compound balance");
        require(torqToken.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");

        uint256 uniswapDepositAmount = depositAmount + compoundTorqAmount; // Total deposit amount
        compoundTorqAmount = 0; // Reset compound amount
        
        // Approve tokens for the Uniswap TORQ contract
        torqToken.approve(address(uniswapTorq), uniswapDepositAmount);
        uniswapTorq.deposit(uniswapDepositAmount); // Deposit into Uniswap TORQ

        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares); // Mint shares for the user
        totalAssetsAmount = totalAssetsAmount.add(uniswapDepositAmount); // Update total assets
        torqRewardUtil.userDepositReward(msg.sender, shares); // Reward user for deposit
        emit Deposited(msg.sender, depositAmount, shares);
    }

    /// @notice Withdraws TORQ from the BoostTORQ contract
    /// @param sharesAmount Amount of shares to withdraw
    function withdrawTORQ(uint256 sharesAmount) external nonReentrant {
        uint256 withdrawAmount = _convertToAssets(sharesAmount);
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100); // Calculate Uniswap withdrawal
        _burn(msg.sender, sharesAmount); // Burn user's shares
        uint256 totalUniSwapAllocation = totalAssetsAmount.mul(uniswapAllocation).div(100); // Calculate total allocation for Uniswap
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount); // Update total assets

        uint256 prevTorqAmount = torqToken.balanceOf(address(this));
        
        if (uniswapWithdrawAmount > 0) {
            uniswapTorq.withdraw(uint128(uniswapWithdrawAmount), totalUniSwapAllocation); // Withdraw from Uniswap
        }
        
        uint256 postTorqAmount = torqToken.balanceOf(address(this));
        uint256 torqAmount = postTorqAmount - prevTorqAmount; // Amount of TORQ received
        require(torqToken.transfer(msg.sender, torqAmount), "Transfer Asset Failed"); // Transfer TORQ to user
        torqRewardUtil.userWithdrawReward(msg.sender, sharesAmount); // Reward user for withdrawal
        emit Withdrawn(msg.sender, torqAmount, sharesAmount);
    }

    /// @notice Compounds accrued fees from Uniswap
    function compoundFees() external nonReentrant {
        _compoundFees();
    }

    /// @notice Internal function to handle compounding of fees
    function _compoundFees() internal {
        uint256 prevTorqAmount = torqToken.balanceOf(address(this));
        uniswapTorq.compound(); // Compound fees from Uniswap
        
        uint256 postTorqAmount = torqToken.balanceOf(address(this));
        uint256 treasuryAmount = (postTorqAmount - prevTorqAmount).mul(performanceFee).div(1000); // Calculate treasury fees
        
        treasuryFee = treasuryFee.add(treasuryAmount); // Update treasury fee
        if (treasuryFee >= minTorqAmount) {
            require(torqToken.transfer(treasury, treasuryFee), "Transfer Asset Failed"); // Transfer treasury fees
            treasuryFee = 0; // Reset treasury fee
        }
        
        uint256 torqAmount = postTorqAmount - prevTorqAmount - treasuryAmount; // Amount available for compounding
        compoundTorqAmount += torqAmount; // Update compounding amount
        lastCompoundTimestamp = block.timestamp; // Update timestamp
    }

    /// @notice Sets the minimum TORQ amount for operations
    /// @param _minTorq Minimum TORQ amount
    function setMinTorq(uint256 _minTorq) public onlyOwner {
        minTorqAmount = _minTorq;
    }

    /// @notice Sets the performance fee percentage
    /// @param _performanceFee Performance fee percentage
    function setPerformanceFee(uint256 _performanceFee) public onlyOwner {
        require(_performanceFee <= 1000, "Treasury Fee can't be more than 100%");
        performanceFee = _performanceFee;
    }

    /// @notice Sets the treasury address
    /// @param _treasury New treasury address
    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    /// @notice Withdraws accumulated treasury fees
    function withdrawTreasuryFees() external onlyOwner {
        payable(treasury).transfer(address(this).balance); // Transfer all balance to treasury
    }

    /// @notice Converts assets to shares based on the current total supply
    /// @param assets Amount of assets to convert
    /// @return shares Number of shares corresponding to the asset amount
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (assets == 0 || supply == 0) ? assets : assets.mulDiv(supply, totalAssets(), Math.Rounding.Down);
    }

    /// @notice Converts shares to assets based on the current total supply
    /// @param shares Amount of shares to convert
    /// @return assets Number of assets corresponding to the share amount
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? shares : shares.mulDiv(totalAssets(), supply, Math.Rounding.Down);
    }

    /// @notice Returns the total assets managed by the contract
    /// @return Total assets amount
    function totalAssets() public view returns (uint256) {
        return totalAssetsAmount;
    }

    /// @notice Updates the TORQ rewards utility contract address
    /// @param _torqRewardUtil New TORQ rewards utility contract address
    function updateTORQRewardUtil(address _torqRewardUtil) external onlyOwner {
        torqRewardUtil = TORQRewardUtil(_torqRewardUtil);
    }

    /// @notice Check if upkeep is needed for automation
    /// @param data Additional data for upkeep check
    /// @return upkeepNeeded Boolean indicating if upkeep is needed
    /// @return performData Additional data for performing upkeep
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp >= lastCompoundTimestamp + 12 hours);
    }

    /// @notice Performs upkeep for automating compounding fees
    /// @param data Additional data for performing upkeep
    function performUpkeep(bytes calldata data) external override {
        if (block.timestamp >= lastCompoundTimestamp + 12 hours) {
            _compoundFees();
        }
    }

    /// @notice Fallback function to receive ETH
    receive() external payable {}
}
