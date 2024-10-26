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

interface GMXUNI {
    function deposit(uint256 _amount) external payable;
    function withdraw(uint256 _amount, address _userAddress) external payable;
    function compound() external;
}

interface UNIUniswap { 
    function deposit(uint256 _amount) external;
    function withdraw(uint128 withdrawAmount, uint256 totalAllocation) external;
    function compound() external;
}

interface RewardUtilTORQ {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
}

/// @title BoostUNI - UNI Yield Aggregation Contract
/// @notice Manages UNI deposits, withdrawals, and compounding within the GMX and Uniswap protocols.
contract BoostUNI is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;

    event Deposited(address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    
    IERC20 public uniToken; // UNI token interface
    GMXUNI public gmxV2Uni; // GMX v2 UNI contract interface
    UNIUniswap public uniswapUni; // UNI Uniswap contract interface
    address public treasury; // Treasury address for fees
    RewardUtilTORQ public rewardsUtil; // Rewards utility contract interface

    uint256 public gmxAllocation; // Allocation percentage for GMX
    uint256 public uniswapAllocation; // Allocation percentage for Uniswap
    uint256 public lastCompoundTimestamp; // Last timestamp for compounding
    uint256 public performanceFee = 10; // Performance fee percentage
    uint256 public minUniAmount = 1 ether; // Minimum amount of UNI for operations
    uint256 public treasuryFee = 0; // Accumulated treasury fees

    uint256 public totalAssetsAmount = 0; // Total assets managed by the contract
    uint256 public compoundUniAmount = 0; // Amount of UNI available for compounding

    /// @notice Initializes the BoostUNI contract
    /// @param _name Name of the ERC20 token
    /// @param _symbol Symbol of the ERC20 token
    /// @param _uniToken Address of the UNI token
    /// @param _gmxV2UniAddress Address of the GMX v2 UNI contract
    /// @param _uniswapUniAddress Address of the Uniswap UNI contract
    /// @param _treasury Address of the treasury
    /// @param _rewardsUtil Address of the rewards utility contract
    constructor(
        string memory _name, 
        string memory _symbol,
        address _uniToken,
        address payable _gmxV2UniAddress,
        address _uniswapUniAddress,
        address _treasury,
        address _rewardsUtil
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        uniToken = IERC20(_uniToken);
        gmxV2Uni = GMXUNI(_gmxV2UniAddress);
        uniswapUni = UNIUniswap(_uniswapUniAddress);
        gmxAllocation = 100; // Default allocation for GMX
        uniswapAllocation = 0; // Default allocation for Uniswap
        treasury = _treasury;
        rewardsUtil = RewardUtilTORQ(_rewardsUtil);
    }

    /// @notice Deposits UNI into the BoostUNI contract
    /// @param depositAmount Amount of UNI to deposit
    function depositUNI(uint256 depositAmount) external payable nonReentrant {
        require(msg.value > 0, "Please pass GMX execution fees");
        require(uniToken.balanceOf(address(this)) >= compoundUniAmount, "Insufficient compound balance");
        require(uniToken.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");

        uint256 depositAndCompound = depositAmount.add(compoundUniAmount); // Total deposit amount
        compoundUniAmount = 0; // Reset compound amount
       
        uint256 uniswapDepositAmount = depositAndCompound.mul(uniswapAllocation).div(100); // Calculate Uniswap deposit
        uint256 gmxDepositAmount = depositAndCompound.sub(uniswapDepositAmount); // Remaining amount for GMX
        
        if (uniswapDepositAmount > 0) {
            uniToken.approve(address(uniswapUni), uniswapDepositAmount); // Approve Uniswap deposit
            uniswapUni.deposit(uniswapDepositAmount); // Deposit into Uniswap
        }

        uniToken.approve(address(gmxV2Uni), gmxDepositAmount); // Approve GMX deposit
        gmxV2Uni.deposit{value: msg.value}(gmxDepositAmount); // Deposit into GMX

        uint256 shares = _convertToShares(depositAmount); // Calculate shares for the deposit
        _mint(msg.sender, shares); // Mint shares for the user
        totalAssetsAmount = totalAssetsAmount.add(depositAndCompound); // Update total assets
        rewardsUtil.userDepositReward(msg.sender, shares); // Reward user for deposit
        emit Deposited(msg.sender, depositAmount, shares);
    }

    /// @notice Withdraws UNI from the BoostUNI contract
    /// @param sharesAmount Amount of shares to withdraw
    function withdrawUNI(uint256 sharesAmount) external payable nonReentrant {
        require(msg.value > 0, "Please pass GMX execution fees");
        uint256 withdrawAmount = _convertToAssets(sharesAmount); // Calculate withdraw amount
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100); // Calculate Uniswap withdrawal
        uint256 gmxWithdrawAmount = withdrawAmount.sub(uniswapWithdrawAmount); // Remaining amount for GMX
        _burn(msg.sender, sharesAmount); // Burn user's shares

        uint256 totalUniSwapAllocation = totalAssetsAmount.mul(uniswapAllocation).div(100); // Calculate total allocation for Uniswap
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount); // Update total assets

        uint256 prevUniAmount = uniToken.balanceOf(address(this)); // Get previous UNI amount
        
        if (uniswapWithdrawAmount > 0) {
            uniswapUni.withdraw(uint128(uniswapWithdrawAmount), totalUniSwapAllocation); // Withdraw from Uniswap
        }

        gmxV2Uni.withdraw{value: msg.value}(gmxWithdrawAmount, msg.sender); // Withdraw from GMX
        uint256 postUniAmount = uniToken.balanceOf(address(this)); // Get current UNI amount
        uint256 uniAmount = postUniAmount.sub(prevUniAmount); // Amount of UNI received
        require(uniToken.transfer(msg.sender, uniAmount), "Transfer Asset Failed"); // Transfer UNI to user
        rewardsUtil.userWithdrawReward(msg.sender, sharesAmount); // Reward user for withdrawal
        emit Withdrawn(msg.sender, uniAmount, sharesAmount);
    }

    /// @notice Compounds accrued fees from GMX and Uniswap
    function compoundFees() external nonReentrant {
        _compoundFees();
    }

    /// @notice Internal function to handle compounding of fees
    function _compoundFees() internal {
        uint256 prevUniAmount = uniToken.balanceOf(address(this)); // Get previous UNI amount
        uniswapUni.compound(); // Compound fees from Uniswap
        gmxV2Uni.compound(); // Compound fees from GMX
        
        uint256 postUniAmount = uniToken.balanceOf(address(this)); // Get current UNI amount
        uint256 treasuryAmount = (postUniAmount.sub(prevUniAmount)).mul(performanceFee).div(1000); // Calculate treasury fees
        
        treasuryFee = treasuryFee.add(treasuryAmount); // Update treasury fee
        if (treasuryFee >= minUniAmount) {
            require(uniToken.transfer(treasury, treasuryFee), "Transfer Asset Failed"); // Transfer treasury fees
            treasuryFee = 0; // Reset treasury fee
        }
        
        uint256 uniAmount = postUniAmount.sub(prevUniAmount).sub(treasuryAmount); // Amount available for compounding
        compoundUniAmount = compoundUniAmount.add(uniAmount); // Update compounding amount
        lastCompoundTimestamp = block.timestamp; // Update timestamp
    }

    /// @notice Sets the allocation for GMX and Uniswap
    /// @param _gmxAllocation GMX allocation percentage
    /// @param _uniswapAllocation Uniswap allocation percentage
    function setAllocation(uint256 _gmxAllocation, uint256 _uniswapAllocation) public onlyOwner {
        require(_gmxAllocation.add(_uniswapAllocation) == 100, "Allocation has to be exactly 100");
        gmxAllocation = _gmxAllocation;
        uniswapAllocation = _uniswapAllocation;
    }

    /// @notice Sets the minimum UNI amount for operations
    /// @param _minUni Minimum UNI amount
    function setMinUni(uint256 _minUni) public onlyOwner {
        minUniAmount = _minUni;
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
        payable(treasury).transfer(address(this).balance);
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

    /// @notice Updates the rewards utility contract address
    /// @param _rewardsUtil New rewards utility contract address
    function updateRewardsUtil(address _rewardsUtil) external onlyOwner {
        rewardsUtil = RewardsUtil(_rewardsUtil);
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
