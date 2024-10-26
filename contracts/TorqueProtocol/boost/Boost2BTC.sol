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

import "./strategies/CurveBTC.sol";
import "./strategies/UniswapBTC.sol";

/// @title Boost2BTC - 2BTC Yield Aggregation Contract
/// @notice This contract manages WBTC deposits and distributes them between Curve and Uniswap strategies.
/// @dev Implements Chainlink Automation for periodic upkeep and compounding of accrued fees.
contract Boost2BTC is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;

    /// @notice Emitted when WBTC is deposited into the contract.
    /// @param account The address of the depositor.
    /// @param amount The amount of WBTC deposited.
    /// @param shares The number of shares minted to the depositor.
    event Deposited(address indexed account, uint256 amount, uint256 shares);

    /// @notice Emitted when WBTC is withdrawn from the contract.
    /// @param account The address of the withdrawer.
    /// @param amount The amount of WBTC withdrawn.
    /// @param shares The number of shares burned from the withdrawer.
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    
    IERC20 public wbtcToken;          // WBTC token contract
    CurveTBTC public curveTBTC;       // Curve strategy contract
    UniswapTBTC public uniswapTBTC;   // Uniswap strategy contract
    address public treasury;          // Treasury address for performance fees
    RewardsUtil public rewardUtilTORQ; // TORQ reward utility contract
    RewardsUtil public rewardUtilARB;  // ARB reward utility contract

    uint256 public curveAllocation;    // Allocation for Curve strategy (in percentage)
    uint256 public uniswapAllocation;  // Allocation for Uniswap strategy (in percentage)
    uint256 public lastCompoundTimestamp; // Timestamp of the last compound action
    uint256 public performanceFee = 10;   // Performance fee in basis points (1%)
    uint256 public minWbtcAmount = 20000; // Minimum WBTC for treasury transfer
    uint256 public treasuryFee = 0;       // Accumulated treasury fee amount
    uint256 public totalUniSwapAllocation = 0; // Total WBTC allocated to Uniswap
    uint256 public totalCurveAllocation = 0; // Total WBTC allocated to Curve
    uint256 public totalAssetsAmount = 0; // Total WBTC under management
    uint256 public compoundWbtcAmount = 0; // WBTC available for compounding

    /// @notice Initializes the Boost2BTC contract with required parameters.
    /// @param _name Name of the ERC20 token representing shares.
    /// @param _symbol Symbol of the ERC20 token representing shares.
    /// @param wBTC Address of the WBTC token.
    /// @param _curveTBTCAddress Address of the Curve strategy contract.
    /// @param _uniswapTBTCAddress Address of the Uniswap strategy contract.
    /// @param _treasury Address of the treasury for performance fees.
    /// @param _rewardUtilTORQ Address of the TORQ reward utility contract.
    /// @param _rewardUtilARB Address of the ARB reward utility contract.
    constructor(
        string memory _name, 
        string memory _symbol,
        address wBTC,
        address _curveTBTCAddress,
        address _uniswapTBTCAddress,
        address _treasury,
        address _rewardUtilTORQ,
        address _rewardUtilARB
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        wbtcToken = IERC20(wBTC);
        curveTBTC = CurveTBTC(_curveTBTCAddress);
        uniswapTBTC = UniswapTBTC(_uniswapTBTCAddress);
        rewardUtilTORQ = RewardsUtil(_rewardUtilTORQ);
        rewardUtilARB = RewardsUtil(_rewardUtilARB);
        curveAllocation = 50;
        uniswapAllocation = 50;
        treasury = _treasury;
    }

    /// @notice Deposits WBTC and allocates it between Curve and Uniswap based on set allocations.
    /// @param depositAmount Amount of WBTC to deposit.
    /// @dev Requires the caller to have sufficient WBTC balance. Updates the internal allocations.
    function depositBTC(uint256 depositAmount) external nonReentrant {
        require(wbtcToken.balanceOf(address(this)) >= compoundWbtcAmount, "Insufficient compound balance");
        require(wbtcToken.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");

        uint256 depositAndCompound = depositAmount + compoundWbtcAmount;
        compoundWbtcAmount = 0;

        uint256 uniswapDepositAmount = depositAndCompound.mul(uniswapAllocation).div(100);
        uint256 curveDepositAmount = depositAndCompound.sub(uniswapDepositAmount);

        // Allocate to Uniswap strategy
        if (uniswapDepositAmount > 0) {
            wbtcToken.approve(address(uniswapTBTC), uniswapDepositAmount);
            uniswapTBTC.deposit(uniswapDepositAmount);
            totalUniSwapAllocation += uniswapDepositAmount;
        }

        // Allocate to Curve strategy
        if (curveDepositAmount > 0) {
            wbtcToken.approve(address(curveTBTC), curveDepositAmount);
            curveTBTC.deposit(curveDepositAmount);
            totalCurveAllocation += curveDepositAmount;
        }

        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares);
        totalAssetsAmount = totalAssetsAmount.add(depositAndCompound);

        rewardUtilTORQ.userDepositReward(msg.sender, depositAmount);
        rewardUtilARB.userDepositReward(msg.sender, depositAmount);

        emit Deposited(msg.sender, depositAmount, shares);
    }

    /// @notice Withdraws WBTC from the contract by burning user's shares.
    /// @param sharesAmount The amount of shares to redeem for WBTC.
    function withdrawBTC(uint256 sharesAmount) external nonReentrant {
        uint256 withdrawAmount = _convertToAssets(sharesAmount);
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100);
        uint256 curveWithdrawAmount = withdrawAmount.sub(uniswapWithdrawAmount);

        _burn(msg.sender, sharesAmount);
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount);

        uint256 prevWbtcAmount = wbtcToken.balanceOf(address(this));

        // Withdraw from Uniswap strategy
        if (uniswapWithdrawAmount > 0) {
            uniswapTBTC.withdraw(uint128(uniswapWithdrawAmount), totalUniSwapAllocation);
            totalUniSwapAllocation -= uniswapWithdrawAmount;
        }

        // Withdraw from Curve strategy
        if (curveWithdrawAmount > 0) {
            curveTBTC.withdraw(curveWithdrawAmount, totalCurveAllocation);
            totalCurveAllocation -= curveWithdrawAmount;
        }

        uint256 postWbtcAmount = wbtcToken.balanceOf(address(this));
        uint256 wbtcAmount = postWbtcAmount.sub(prevWbtcAmount);
        require(wbtcToken.transfer(msg.sender, wbtcAmount), "Transfer Asset Failed");

        rewardUtilTORQ.userWithdrawReward(msg.sender, sharesAmount);
        rewardUtilARB.userWithdrawReward(msg.sender, sharesAmount);

        emit Withdrawn(msg.sender, wbtcAmount, sharesAmount);
    }

    /// @notice Compounds accrued fees and updates internal balances.
    /// @dev Distributes fees to the treasury and compounds the remaining WBTC.
    function compoundFees() external nonReentrant {
        _compoundFees();
    }

    /// @notice Internal function for compounding fees.
    /// @dev Calculates and transfers performance fees to the treasury.
    function _compoundFees() internal {
        uint256 prevWbtcAmount = wbtcToken.balanceOf(address(this));
        uniswapTBTC.compound(); 
        curveTBTC.compound();
        uint256 postWbtcAmount = wbtcToken.balanceOf(address(this));

        uint256 treasuryAmount = (postWbtcAmount.sub(prevWbtcAmount)).mul(performanceFee).div(1000);
        treasuryFee = treasuryFee.add(treasuryAmount);
        
        if (treasuryFee >= minWbtcAmount) {
            require(wbtcToken.transfer(treasury, treasuryFee), "Transfer to treasury failed");
            treasuryFee = 0;
        }

        uint256 wbtcAmount = postWbtcAmount.sub(prevWbtcAmount).sub(treasuryAmount);
        compoundWbtcAmount += wbtcAmount;
        lastCompoundTimestamp = block.timestamp;
    }

    /// @notice Sets the allocation percentages for Curve and Uniswap strategies.
    /// @param _curveAllocation Allocation percentage for Curve strategy.
    /// @param _uniswapAllocation Allocation percentage for Uniswap strategy.
    /// @dev The sum of allocations must equal 100%.
    function setAllocation(uint256 _curveAllocation, uint256 _uniswapAllocation) public onlyOwner {
        require(_curveAllocation + _uniswapAllocation == 100, "Allocation must total 100%");
        curveAllocation = _curveAllocation;
        uniswapAllocation = _uniswapAllocation;
    }

    /// @notice Updates the TORQ and ARB reward utility contract addresses.
    /// @param _rewardUtilTORQ New address for TORQ reward utility.
    /// @param _rewardUtilARB New address for ARB reward utility.
    function updateRewardsUtil(address _rewardUtilTORQ, address _rewardUtilARB) external onlyOwner {
        rewardUtilTORQ = RewardsUtil(_rewardUtilTORQ);
        rewardUtilARB = RewardsUtil(_rewardUtilARB);
    }

    /// @notice Sets the minimum WBTC amount required for treasury transfers.
    /// @param _minWbtc New minimum WBTC amount for treasury transfers.
    function setMinWbtc(uint256 _minWbtc) public onlyOwner {
        minWbtcAmount = _minWbtc;
    }

    /// @notice Sets the performance fee for compounding.
    /// @param _performanceFee New performance fee in basis points.
    /// @dev The maximum allowed performance fee is 10% (1000 basis points).
    function setPerformanceFee(uint256 _performanceFee) public onlyOwner {
        require(_performanceFee <= 1000, "Fee exceeds max");
        performanceFee = _performanceFee;
    }

    /// @notice Sets the treasury address for performance fee transfers.
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

    /// @notice Converts assets to shares based on the total supply.
    /// @param assets The amount of assets to convert.
    /// @return The corresponding number of shares.
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (assets == 0 || supply == 0) ? assets : assets.mulDiv(supply, totalAssets(), Math.Rounding.Down);
    }

    /// @notice Converts shares to assets based on the total supply.
    /// @param shares The number of shares to convert.
    /// @return The corresponding amount of assets.
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? shares : shares.mulDiv(totalAssets(), supply, Math.Rounding.Down);
    }

    /// @notice Returns the total amount of WBTC under management.
    /// @return The total amount of WBTC managed by the contract.
    function totalAssets() public view returns (uint256) {
        return totalAssetsAmount;
    }

    /// @notice Checks if upkeep is needed for compounding based on the last timestamp.
    /// @return upkeepNeeded True if upkeep is needed, false otherwise.
    /// @return performData Empty data payload for upkeep.
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = (block.timestamp >= lastCompoundTimestamp + 12 hours);
    }

    /// @notice Performs upkeep if the compounding interval has passed.
    function performUpkeep(bytes calldata) external override {
        if (block.timestamp >= lastCompoundTimestamp + 12 hours) {
            _compoundFees();
        }
    }

    /// @notice Fallback function to reject any ETH sent to the contract.
    receive() external payable {
        revert("Cannot receive ETH");
    }
}
