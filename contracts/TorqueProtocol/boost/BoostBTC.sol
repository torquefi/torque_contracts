// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./strategies/GMXV2BTC.sol";
import "./strategies/UniswapBTC.sol";

/// @title BoostBTC - BTC Yield Aggregation Contract
/// @notice This contract allows users to deposit, withdraw, and compound WBTC, distributing funds between GMX and Uniswap based on allocation settings.
/// @dev Uses Chainlink Automation for periodic upkeep and supports customized Uniswap ranges.
interface RewardUtilTORQ {
    /// @notice Rewards user for depositing WBTC.
    /// @param _userAddress The address of the user depositing WBTC.
    /// @param _depositAmount The amount of WBTC deposited.
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;

    /// @notice Rewards user for withdrawing WBTC.
    /// @param _userAddress The address of the user withdrawing WBTC.
    /// @param _withdrawAmount The amount of WBTC withdrawn.
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
}

/// @title BoostBTC Contract
/// @dev Extends ERC20, Ownable, ReentrancyGuard, and AutomationCompatible.
///      This contract manages WBTC deposits and withdrawals, distributing
///      assets between GMX and Uniswap based on set allocations.
contract BoostBTC is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;

    /// @notice Event emitted when WBTC is deposited.
    /// @param account The address of the depositor.
    /// @param amount The amount of WBTC deposited.
    /// @param shares The number of shares minted to the depositor.
    event Deposited(address indexed account, uint256 amount, uint256 shares);

    /// @notice Event emitted when WBTC is withdrawn.
    /// @param account The address of the withdrawer.
    /// @param amount The amount of WBTC withdrawn.
    /// @param shares The number of shares burned from the withdrawer.
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);

    IERC20 public wbtcToken;           // WBTC token contract
    GMXV2BTC public gmxV2Btc;          // GMX strategy contract
    UniswapBTC public uniswapBtc;      // Uniswap strategy contract
    address public treasury;           // Treasury address for performance fees
    RewardUtilTORQ public rewardUtilTORQ;  // Reward utility contract for TORQ rewards

    uint256 public gmxAllocation;      // Allocation percentage for GMX strategy
    uint256 public uniswapAllocation;  // Allocation percentage for Uniswap strategy
    uint256 public lastCompoundTimestamp; // Timestamp of the last compound
    uint256 public performanceFee = 10;   // Performance fee in basis points (1%)
    uint256 public minWbtcAmount = 20000; // Minimum WBTC amount for treasury transfer
    uint256 public treasuryFee = 0;       // Accumulated treasury fee amount
    uint256 public totalAssetsAmount = 0; // Total amount of WBTC managed by the contract
    uint256 public compoundWbtcAmount = 0; // Amount of WBTC pending for compounding

    /// @notice Constructor initializes the contract with required parameters.
    /// @param _name Name of the ERC20 token representing shares.
    /// @param _symbol Symbol of the ERC20 token representing shares.
    /// @param wBTC The address of the WBTC token.
    /// @param _gmxV2BtcAddress Address of the GMX strategy contract.
    /// @param _uniswapBtcAddress Address of the Uniswap strategy contract.
    /// @param _treasury Address of the treasury for performance fees.
    /// @param _rewardUtilTORQ Address of the TORQ reward utility contract.
    constructor(
        string memory _name, 
        string memory _symbol,
        address wBTC,
        address payable _gmxV2BtcAddress,
        address _uniswapBtcAddress,
        address _treasury,
        address _rewardUtilTORQ
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        wbtcToken = IERC20(wBTC);
        gmxV2Btc = GMXV2BTC(_gmxV2BtcAddress);
        uniswapBtc = UniswapBTC(_uniswapBtcAddress);
        gmxAllocation = 50;
        uniswapAllocation = 50;
        treasury = _treasury;
        rewardUtilTORQ = RewardUtilTORQ(_rewardUtilTORQ);
    }

    /// @notice Deposits WBTC and distributes it based on set allocations.
    /// @param depositAmount Amount of WBTC to deposit.
    /// @param _tickLower The lower tick for Uniswap range orders.
    /// @param _tickUpper The upper tick for Uniswap range orders.
    /// @param _slippage The slippage tolerance for Uniswap deposits.
    /// @dev Requires GMX execution fees to be passed as msg.value.
    function depositBTC(
        uint256 depositAmount, 
        int24 _tickLower, 
        int24 _tickUpper, 
        uint256 _slippage
    ) external payable nonReentrant {
        require(msg.value > 0, "Please pass GMX execution fees");
        require(wbtcToken.balanceOf(address(this)) >= compoundWbtcAmount, "Insufficient compound balance");
        require(wbtcToken.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");
        
        uint256 depositAndCompound = depositAmount.add(compoundWbtcAmount);
        compoundWbtcAmount = 0;

        uint256 uniswapDepositAmount = depositAndCompound.mul(uniswapAllocation).div(100);
        uint256 gmxDepositAmount = depositAndCompound.sub(uniswapDepositAmount);

        // Uniswap deposit with custom tick range and slippage
        if (uniswapDepositAmount > 0) {
            wbtcToken.approve(address(uniswapBtc), uniswapDepositAmount);
            uniswapBtc.depositWithCustomRange(uniswapDepositAmount, _tickLower, _tickUpper, _slippage);
        }

        // GMX deposit
        wbtcToken.approve(address(gmxV2Btc), gmxDepositAmount);
        gmxV2Btc.deposit{value: msg.value}(gmxDepositAmount);

        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares);
        totalAssetsAmount = totalAssetsAmount.add(depositAndCompound);
        rewardUtilTORQ.userDepositReward(msg.sender, shares);

        emit Deposited(msg.sender, depositAmount, shares);
    }

    /// @notice Withdraws WBTC from the contract based on share amount.
    /// @param sharesAmount The amount of shares to redeem for WBTC.
    /// @dev Requires GMX execution fees to be passed as msg.value.
    function withdrawBTC(uint256 sharesAmount) external payable nonReentrant {
        require(msg.value > 0, "Please pass GMX execution fees");
        uint256 withdrawAmount = _convertToAssets(sharesAmount);

        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100);
        uint256 gmxWithdrawAmount = withdrawAmount.sub(uniswapWithdrawAmount);

        _burn(msg.sender, sharesAmount);
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount);

        uint256 prevWbtcAmount = wbtcToken.balanceOf(address(this));

        // Uniswap withdrawal
        if (uniswapWithdrawAmount > 0) {
            uniswapBtc.withdraw(uint128(uniswapWithdrawAmount), totalAssetsAmount.mul(uniswapAllocation).div(100));
        }

        // GMX withdrawal
        gmxV2Btc.withdraw{value: msg.value}(gmxWithdrawAmount, msg.sender);

        uint256 postWbtcAmount = wbtcToken.balanceOf(address(this));
        uint256 wbtcAmount = postWbtcAmount.sub(prevWbtcAmount);

        require(wbtcToken.transfer(msg.sender, wbtcAmount), "Transfer Failed");
        rewardUtilTORQ.userWithdrawReward(msg.sender, sharesAmount);

        emit Withdrawn(msg.sender, wbtcAmount, sharesAmount);
    }

    /// @notice Triggers compounding of accrued fees.
    /// @dev Calls the internal _compoundFees function.
    function compoundFees() external nonReentrant {
        _compoundFees();
    }

    /// @notice Internal function for compounding fees.
    /// @dev Distributes fees to the treasury and compounds remaining WBTC.
    function _compoundFees() internal {
        uint256 prevWbtcAmount = wbtcToken.balanceOf(address(this));
        uniswapBtc.compound();
        gmxV2Btc.compound();
        uint256 postWbtcAmount = wbtcToken.balanceOf(address(this));

        uint256 treasuryAmount = (postWbtcAmount.sub(prevWbtcAmount)).mul(performanceFee).div(1000);
        treasuryFee = treasuryFee.add(treasuryAmount);
        if (treasuryFee >= minWbtcAmount) {
            require(wbtcToken.transfer(treasury, treasuryFee), "Transfer to treasury failed");
            treasuryFee = 0;
        }
        uint256 wbtcAmount = postWbtcAmount.sub(prevWbtcAmount).sub(treasuryAmount);
        compoundWbtcAmount = compoundWbtcAmount.add(wbtcAmount);
        lastCompoundTimestamp = block.timestamp;
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

    /// @notice Sets the minimum WBTC amount for treasury transfers.
    /// @param _minWbtc Minimum amount of WBTC for treasury transfers.
    function setMinWbtc(uint256 _minWbtc) public onlyOwner {
        minWbtcAmount = _minWbtc;
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
        require(wbtcToken.transfer(treasury, treasuryFee), "Treasury withdrawal failed");
        treasuryFee = 0;
    }

    /// @notice Updates the TORQ reward utility contract address.
    /// @param _rewardUtilTORQ New address for the TORQ reward utility contract.
    function updateRewardUtilTORQ(address _rewardUtilTORQ) external onlyOwner {
        rewardUtilTORQ = RewardUtilTORQ(_rewardUtilTORQ);
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
    /// @return The total amount of assets in WBTC.
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
    /// @return The number of decimals (8).
    function decimals() public view override returns (uint8) {
        return 8;
    }

    /// @notice Fallback function to reject any ETH sent to the contract
    receive() external payable {
        revert("Cannot receive ETH");
    }
}
