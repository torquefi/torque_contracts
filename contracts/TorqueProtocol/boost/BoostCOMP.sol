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

import "./strategies/UniswapCOMP.sol";

interface TORQRewardUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
}

/// @title BoostCOMP - COMP Yield Aggregation Contract
/// @notice Manages COMP deposits, withdrawals, and compounding within the Uniswap and GMX protocols.
contract BoostCOMP is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;

    event Deposited(address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    
    IERC20 public compToken;              // COMP token interface
    UniswapCOMP public uniswapComp;      // Uniswap COMP contract interface
    address public treasury;              // Treasury address for fees
    TORQRewardUtil public torqRewardUtil; // Rewards utility contract interface

    uint256 public gmxAllocation;         // Allocation percentage for GMX strategy
    uint256 public uniswapAllocation;     // Allocation percentage for Uniswap strategy
    uint256 public lastCompoundTimestamp; // Last timestamp for compounding
    uint256 public performanceFee = 10;   // Performance fee percentage
    uint256 public minCompAmount = 1 ether; // Minimum amount of COMP for operations
    uint256 public treasuryFee = 0;       // Accumulated treasury fees

    uint256 public totalAssetsAmount = 0; // Total assets managed by the contract
    uint256 public compoundCompAmount = 0; // Amount of COMP available for compounding

    constructor(
        string memory _name, 
        string memory _symbol,
        address COMP,
        address _uniswapCompAddress,
        address _treasury,
        address _torqRewardUtil
    ) ERC20(_name, _symbol) Ownable() {
        compToken = IERC20(COMP);
        uniswapComp = UniswapCOMP(_uniswapCompAddress);
        treasury = _treasury;
        torqRewardUtil = TORQRewardUtil(_torqRewardUtil);
        gmxAllocation = 50; // Default allocation for GMX
        uniswapAllocation = 50; // Default allocation for Uniswap
    }

    /// @notice Deposits COMP and distributes it based on set allocations.
    /// @param depositAmount Amount of COMP to deposit.
    function depositCOMP(uint256 depositAmount) external payable nonReentrant {
        require(compToken.balanceOf(address(this)) >= compoundCompAmount, "Insufficient compound balance");
        require(compToken.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");

        uint256 depositAndCompound = depositAmount.add(compoundCompAmount); // Total deposit amount
        compoundCompAmount = 0; // Reset compound amount

        uint256 uniswapDepositAmount = depositAndCompound.mul(uniswapAllocation).div(100); // Calculate Uniswap deposit
        uint256 gmxDepositAmount = depositAndCompound.sub(uniswapDepositAmount); // Remaining amount for GMX
        
        if (uniswapDepositAmount > 0) {
            compToken.approve(address(uniswapComp), uniswapDepositAmount); // Approve Uniswap deposit
            uniswapComp.deposit(uniswapDepositAmount); // Deposit into Uniswap COMP
        }

        compToken.approve(address(gmxV2Comp), gmxDepositAmount); // Approve GMX deposit
        gmxV2Comp.deposit{value: msg.value}(gmxDepositAmount); // Deposit into GMX

        uint256 shares = _convertToShares(depositAmount); // Calculate shares for the deposit
        _mint(msg.sender, shares); // Mint shares for the user
        totalAssetsAmount = totalAssetsAmount.add(depositAndCompound); // Update total assets
        torqRewardUtil.userDepositReward(msg.sender, shares); // Reward user for deposit
        emit Deposited(msg.sender, depositAmount, shares);
    }

    /// @notice Withdraws COMP from the BoostCOMP contract
    /// @param sharesAmount Amount of shares to withdraw
    function withdrawCOMP(uint256 sharesAmount) external payable nonReentrant {
        require(msg.value > 0, "Please pass GMX execution fees");
        uint256 withdrawAmount = _convertToAssets(sharesAmount); // Calculate withdraw amount
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100); // Calculate Uniswap withdrawal
        uint256 gmxWithdrawAmount = withdrawAmount.sub(uniswapWithdrawAmount); // Remaining amount for GMX
        _burn(msg.sender, sharesAmount); // Burn user's shares

        uint256 totalUniSwapAllocation = totalAssetsAmount.mul(uniswapAllocation).div(100); // Calculate total allocation for Uniswap
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount); // Update total assets

        uint256 prevCompAmount = compToken.balanceOf(address(this)); // Get previous COMP amount
        
        if (uniswapWithdrawAmount > 0) {
            uniswapComp.withdraw(uint128(uniswapWithdrawAmount), totalUniSwapAllocation); // Withdraw from Uniswap
        }

        gmxV2Comp.withdraw{value: msg.value}(gmxWithdrawAmount, msg.sender); // Withdraw from GMX
        uint256 postCompAmount = compToken.balanceOf(address(this)); // Get current COMP amount
        uint256 compAmount = postCompAmount.sub(prevCompAmount); // Amount of COMP received
        require(compToken.transfer(msg.sender, compAmount), "Transfer Asset Failed"); // Transfer COMP to user
        torqRewardUtil.userWithdrawReward(msg.sender, sharesAmount); // Reward user for withdrawal
        emit Withdrawn(msg.sender, compAmount, sharesAmount);
    }

    /// @notice Compounds accrued fees from Uniswap and GMX
    function compoundFees() external nonReentrant {
        _compoundFees();
    }

    /// @notice Internal function to handle compounding of fees
    function _compoundFees() internal {
        uint256 prevCompAmount = compToken.balanceOf(address(this)); // Get previous COMP amount
        uniswapComp.compound(); // Compound fees from Uniswap
        gmxV2Comp.compound(); // Compound fees from GMX
        
        uint256 postCompAmount = compToken.balanceOf(address(this)); // Get current COMP amount
        uint256 treasuryAmount = (postCompAmount.sub(prevCompAmount)).mul(performanceFee).div(1000); // Calculate treasury fees
        
        treasuryFee = treasuryFee.add(treasuryAmount); // Update treasury fee
        if (treasuryFee >= minCompAmount) {
            require(compToken.transfer(treasury, treasuryFee), "Transfer Asset Failed"); // Transfer treasury fees
            treasuryFee = 0; // Reset treasury fee
        }
        
        uint256 compAmount = postCompAmount.sub(prevCompAmount).sub(treasuryAmount); // Amount available for compounding
        compoundCompAmount = compoundCompAmount.add(compAmount); // Update compounding amount
        lastCompoundTimestamp = block.timestamp; // Update timestamp
    }

    /// @notice Sets the allocation for GMX and Uniswap strategies.
    /// @param _gmxAllocation Percentage allocation for GMX.
    /// @param _uniswapAllocation Percentage allocation for Uniswap.
    /// @dev The sum of the allocations must equal 100.
    function setAllocation(uint256 _gmxAllocation, uint256 _uniswapAllocation) public onlyOwner {
        require(_gmxAllocation + _uniswapAllocation == 100, "Allocation must total 100%");
        gmxAllocation = _gmxAllocation;
        uniswapAllocation = _uniswapAllocation;
    }

    /// @notice Sets the minimum COMP amount for treasury transfers.
    /// @param _minComp Minimum amount of COMP for treasury transfers.
    function setMinComp(uint256 _minComp) public onlyOwner {
        minCompAmount = _minComp;
    }

    /// @notice Sets the performance fee in basis points.
    /// @param _performanceFee Performance fee in basis points (max 1000).
    function setPerformanceFee(uint256 _performanceFee) public onlyOwner {
        require(_performanceFee <= 1000, "Fee exceeds max");
        performanceFee = _performanceFee;
    }

    /// @notice Sets the treasury address.
    /// @param _treasury New treasury address.
    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    /// @notice Withdraws accumulated treasury fees to the treasury address.
    function withdrawTreasuryFees() external onlyOwner {
        require(treasuryFee > 0, "No fees to withdraw");
        require(compToken.transfer(treasury, treasuryFee), "Treasury withdrawal failed");
        treasuryFee = 0;
    }

    /// @notice Updates the TORQ reward utility contract address.
    /// @param _rewardUtilTORQ New address for the TORQ reward utility contract.
    function updateRewardUtilTORQ(address _rewardUtilTORQ) external onlyOwner {
        torqRewardUtil = TORQRewardUtil(_rewardUtilTORQ);
    }

    /// @notice Converts assets to shares based on total supply.
    /// @param assets The amount of assets to convert.
    /// @return The corresponding number of shares.
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (assets == 0 || supply == 0) ? assets : assets.mul(supply).div(totalAssets());
    }

    /// @notice Converts shares to assets based on total supply.
    /// @param shares The number of shares to convert.
    /// @return The corresponding amount of assets.
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? shares : shares.mul(totalAssets()).div(supply);
    }

    /// @notice Returns the total amount of assets under management.
    /// @return The total amount of assets in COMP.
    function totalAssets() public view returns (uint256) {
        return totalAssetsAmount;
    }

    /// @notice Checks if upkeep is needed for compounding.
    /// @return upkeepNeeded True if upkeep is needed, false otherwise.
    /// @return performData Empty data payload for upkeep.
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = (block.timestamp >= lastCompoundTimestamp + 12 hours);
    }

    /// @notice Performs upkeep if conditions are met.
    /// @dev Compounds accrued fees.
    function performUpkeep(bytes calldata) external override {
        if (block.timestamp >= lastCompoundTimestamp + 12 hours) {
            _compoundFees();
        }
    }

    /// @notice Returns the number of decimals for the ERC20 token.
    /// @return The number of decimals (18).
    function decimals() public view override returns (uint8) {
        return 18;
    }

    /// @notice Fallback function to reject any ETH sent to the contract
    receive() external payable {
        revert("Cannot receive ETH");
    }
}
