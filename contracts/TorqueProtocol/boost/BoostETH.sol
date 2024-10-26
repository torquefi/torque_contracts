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
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IWETH9.sol";

/// @title BoostETH - ETH Yield Aggregation Contract
/// @notice This contract allows users to deposit, withdraw, and compound WETH, distributing assets between GMX and Stargate based on allocations.
contract BoostETH is AutomationCompatible, ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Math for uint256;

    /// @notice Event emitted when WETH is deposited.
    /// @param account The address of the depositor.
    /// @param amount The amount of WETH deposited.
    /// @param shares The number of shares minted to the depositor.
    event Deposited(address indexed account, uint256 amount, uint256 shares);

    /// @notice Event emitted when WETH is withdrawn.
    /// @param account The address of the withdrawer.
    /// @param amount The amount of WETH withdrawn.
    /// @param shares The number of shares burned from the withdrawer.
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);

    IWETH9 public weth; // WETH token contract
    GMXETH public gmxETH; // GMX strategy contract for ETH
    StargateETHER public stargateETHER; // Stargate strategy contract for ETH
    RewardsUtil public rewardUtil; // Rewards utility contract for deposit/withdraw rewards
    address public treasury; // Treasury address for performance fees

    uint256 public gmxAllocation; // Allocation for GMX strategy
    uint256 public stargateAllocation; // Allocation for Stargate strategy
    uint256 public lastCompoundTimestamp; // Timestamp of last compound
    uint256 public performanceFee = 10; // Performance fee in basis points (1%)
    uint256 public minWethAmount = 4000000000000000; // Minimum WETH amount for treasury transfer
    uint256 public compoundWethAmount = 0; // WETH amount pending for compounding
    uint256 public treasuryFee = 0; // Accumulated treasury fee
    uint256 public totalAssetsAmount = 0; // Total WETH under management

    /// @notice Constructor initializes the BoostETH contract with required parameters.
    /// @param _name Name of the ERC20 token representing shares.
    /// @param _symbol Symbol of the ERC20 token representing shares.
    /// @param weth_ Address of the WETH token contract.
    /// @param gmxETH_ Address of the GMX strategy contract.
    /// @param stargateETHER_ Address of the Stargate strategy contract.
    /// @param treasury_ Address of the treasury for performance fees.
    /// @param _rewardUtil Address of the rewards utility contract.
    constructor(
        string memory _name,
        string memory _symbol,
        address payable weth_,
        address payable gmxETH_,
        address payable stargateETHER_,
        address treasury_,
        address _rewardUtil
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        weth = IWETH9(weth_);
        gmxETH = GMXETH(gmxETH_);
        stargateETHER = StargateETHER(stargateETHER_);
        treasury = treasury_;
        rewardUtil = RewardsUtil(_rewardUtil);
        gmxAllocation = 50; // Default allocation for GMX
        stargateAllocation = 50; // Default allocation for Stargate
        lastCompoundTimestamp = block.timestamp;
    }

    /// @notice Deposits WETH and distributes it based on set allocations.
    /// @param depositAmount The amount of WETH to deposit.
    /// @param _tickLower The lower tick for Uniswap range orders.
    /// @param _tickUpper The upper tick for Uniswap range orders.
    /// @param _slippage The slippage tolerance for Uniswap deposits.
    /// @dev Requires GMX execution fees to be passed as msg.value.
    function depositETH(uint256 depositAmount, int24 _tickLower, int24 _tickUpper, uint256 _slippage) external payable nonReentrant {
        require(msg.value > 0, "You must pay GMX execution fee");
        require(weth.balanceOf(address(this)) >= compoundWethAmount, "Insufficient compound balance");
        require(weth.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");

        uint256 depositAndCompound = depositAmount.add(compoundWethAmount);
        compoundWethAmount = 0;

        uint256 stargateDepositAmount = depositAndCompound.mul(stargateAllocation).div(100);
        uint256 gmxDepositAmount = depositAndCompound.sub(stargateDepositAmount);

        if (stargateDepositAmount > 0) {
            weth.approve(address(stargateETHER), stargateDepositAmount);
            stargateETHER.depositWithCustomRange(stargateDepositAmount, _tickLower, _tickUpper, _slippage); // Custom deposit method
        }

        weth.approve(address(gmxETH), gmxDepositAmount);
        gmxETH.deposit{value: msg.value}(gmxDepositAmount);

        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares);
        totalAssetsAmount = totalAssetsAmount.add(depositAndCompound);

        rewardUtil.userDepositReward(msg.sender, depositAmount);

        emit Deposited(msg.sender, depositAmount, shares);
    }

    /// @notice Withdraws WETH from the contract based on share amount.
    /// @param sharesAmount The amount of shares to redeem for WETH.
    /// @dev Requires GMX execution fees to be passed as msg.value.
    function withdrawETH(uint256 sharesAmount) external payable nonReentrant {
        require(msg.value > 0, "You must pay GMX execution fee");

        uint256 withdrawAmount = _convertToAssets(sharesAmount);
        uint256 stargateWithdrawAmount = withdrawAmount.mul(stargateAllocation).div(100);
        uint256 gmxWithdrawAmount = withdrawAmount.sub(stargateWithdrawAmount);

        _burn(msg.sender, sharesAmount);
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount);

        uint256 prevWethAmount = weth.balanceOf(address(this));

        if (stargateWithdrawAmount > 0) {
            stargateETHER.withdraw(stargateWithdrawAmount);
        }

        gmxETH.withdraw{value: msg.value}(gmxWithdrawAmount, msg.sender);

        uint256 postWethAmount = weth.balanceOf(address(this));
        uint256 wethAmount = postWethAmount.sub(prevWethAmount);

        require(weth.transfer(msg.sender, wethAmount), "Transfer Asset Failed");

        rewardUtil.userWithdrawReward(msg.sender, sharesAmount);

        emit Withdrawn(msg.sender, wethAmount, sharesAmount);
    }

    /// @notice Returns the total amount of WETH under management.
    /// @return The total amount of WETH.
    function totalAssets() public view returns (uint256) {
        return totalAssetsAmount;
    }

    /// @notice Converts assets to shares based on total supply.
    /// @param assets The amount of assets to convert.
    /// @return The corresponding number of shares.
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (assets == 0 || supply == 0) ? assets : assets.mulDiv(supply, totalAssets(), Math.Rounding.Down);
    }

    /// @notice Converts shares to assets based on total supply.
    /// @param shares The number of shares to convert.
    /// @return The corresponding amount of assets.
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? shares : shares.mulDiv(totalAssets(), supply, Math.Rounding.Down);
    }

    /// @notice Triggers compounding of accrued fees.
    function compoundFees() external nonReentrant {
        _compoundFees();
    }

    /// @notice Internal function for compounding fees.
    function _compoundFees() internal {
        uint256 prevWethAmount = weth.balanceOf(address(this));
        stargateETHER.compound();
        gmxETH.compound();

        uint256 postWethAmount = weth.balanceOf(address(this));
        uint256 treasuryAmount = (postWethAmount.sub(prevWethAmount)).mul(performanceFee).div(1000);
        treasuryFee = treasuryFee.add(treasuryAmount);

        if (treasuryFee >= minWethAmount) {
            require(weth.transfer(treasury, treasuryFee), "Transfer to treasury failed");
            treasuryFee = 0;
        }

        uint256 wethAmount = postWethAmount.sub(prevWethAmount).sub(treasuryAmount);
        compoundWethAmount = compoundWethAmount.add(wethAmount);
        lastCompoundTimestamp = block.timestamp;
    }

    /// @notice Sets the minimum WETH amount for treasury transfers.
    /// @param _minWeth The minimum amount of WETH for treasury transfers.
    function setMinWeth(uint256 _minWeth) public onlyOwner {
        minWethAmount = _minWeth;
    }

    /// @notice Sets the allocation for GMX and Stargate strategies.
    /// @param _stargateAllocation Percentage allocation for Stargate.
    /// @param _gmxAllocation Percentage allocation for GMX.
    /// @dev The sum of the allocations must equal 100.
    function setAllocation(uint256 _stargateAllocation, uint256 _gmxAllocation) public onlyOwner {
        require(_stargateAllocation + _gmxAllocation == 100, "Allocations must total 100%");
        gmxAllocation = _gmxAllocation;
        stargateAllocation = _stargateAllocation;
    }

    /// @notice Sets the performance fee in basis points.
    /// @param _performanceFee The performance fee in basis points.
    function setPerformanceFee(uint256 _performanceFee) public onlyOwner {
        require(_performanceFee <= 1000, "Fee exceeds max");
        performanceFee = _performanceFee;
    }

    /// @notice Sets the treasury address.
    /// @param _treasury The new treasury address.
    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    /// @notice Withdraws accumulated treasury fees to the treasury address.
    function withdrawTreasuryFees() external onlyOwner {
        require(treasuryFee > 0, "No fees to withdraw");
        require(weth.transfer(treasury, treasuryFee), "Treasury withdrawal failed");
        treasuryFee = 0;
    }

    /// @notice Updates the rewards utility contract address.
    /// @param _rewardUtil The new address for the rewards utility contract.
    function updateRewardsUtil(address _rewardUtil) external onlyOwner {
        rewardUtil = RewardsUtil(_rewardUtil);
    }

    /// @notice Checks if upkeep is needed for compounding.
    /// @return upkeepNeeded True if upkeep is needed, false otherwise.
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = (block.timestamp >= lastCompoundTimestamp + 12 hours);
    }

    /// @notice Performs upkeep if conditions are met.
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

    /// @notice Fallback function to reject any ETH sent to the contract.
    receive() external payable {
        revert("Cannot receive ETH");
    }
}
