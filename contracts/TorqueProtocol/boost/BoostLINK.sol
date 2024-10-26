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

interface GMXLINK {
    function deposit(uint256 _amount) external payable;
    function withdraw(uint256 _amount, address _userAddress) external payable;
    function compound() external;
}

interface LINKUniswap { 
    function deposit(uint256 _amount) external;
    function withdraw(uint128 withdrawAmount, uint256 totalAllocation) external;
    function compound() external;
}

interface RewardsUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
}

/// @title BoostLINK - LINK Yield Aggregation Contract
/// @notice Manages LINK deposits, withdrawals, and compounding within the GMX and Uniswap protocols.
contract BoostLINK is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;

    event Deposited(address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    
    IERC20 public linkToken;            // LINK token interface
    GMXLINK public gmxV2Link;          // GMX v2 LINK contract interface
    LINKUniswap public uniswapLink;    // LINK Uniswap contract interface
    address public treasury;            // Treasury address for fees
    RewardsUtil public rewardsUtil;     // Rewards utility contract interface

    uint256 public gmxAllocation;       // Allocation percentage for GMX
    uint256 public uniswapAllocation;   // Allocation percentage for Uniswap
    uint256 public lastCompoundTimestamp; // Last timestamp for compounding
    uint256 public performanceFee = 10; // Performance fee percentage
    uint256 public minLinkAmount = 1 ether; // Minimum amount of LINK for operations
    uint256 public treasuryFee = 0;     // Accumulated treasury fees

    uint256 public totalAssetsAmount = 0; // Total assets managed by the contract
    uint256 public compoundLinkAmount = 0; // Amount of LINK available for compounding

    /// @notice Initializes the BoostLINK contract
    /// @param _name Name of the ERC20 token
    /// @param _symbol Symbol of the ERC20 token
    /// @param _linkToken Address of the LINK token
    /// @param _gmxV2LinkAddress Address of the GMX v2 LINK contract
    /// @param _uniswapLinkAddress Address of the Uniswap LINK contract
    /// @param _treasury Address of the treasury
    /// @param _rewardsUtil Address of the rewards utility contract
    constructor(
        string memory _name, 
        string memory _symbol,
        address _linkToken,
        address payable _gmxV2LinkAddress,
        address _uniswapLinkAddress,
        address _treasury,
        address _rewardsUtil
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        linkToken = IERC20(_linkToken);
        gmxV2Link = GMXLINK(_gmxV2LinkAddress);
        uniswapLink = LINKUniswap(_uniswapLinkAddress);
        gmxAllocation = 100; // Default allocation for GMX
        uniswapAllocation = 0; // Default allocation for Uniswap
        treasury = _treasury;
        rewardsUtil = RewardsUtil(_rewardsUtil);
    }

    /// @notice Deposits LINK into the BoostLINK contract
    /// @param depositAmount Amount of LINK to deposit
    function depositLINK(uint256 depositAmount) external payable nonReentrant {
        require(msg.value > 0, "Please pass GMX execution fees");
        require(linkToken.balanceOf(address(this)) >= compoundLinkAmount, "Insufficient compound balance");
        require(linkToken.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");
        
        uint256 depositAndCompound = depositAmount.add(compoundLinkAmount);
        compoundLinkAmount = 0; // Reset compound amount
       
        uint256 uniswapDepositAmount = depositAndCompound.mul(uniswapAllocation).div(100);
        uint256 gmxDepositAmount = depositAndCompound.sub(uniswapDepositAmount);
        
        if (uniswapDepositAmount > 0) {
            linkToken.approve(address(uniswapLink), uniswapDepositAmount);
            uniswapLink.deposit(uniswapDepositAmount);
        }

        linkToken.approve(address(gmxV2Link), gmxDepositAmount);
        gmxV2Link.deposit{value: msg.value}(gmxDepositAmount);

        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares);
        
        totalAssetsAmount = totalAssetsAmount.add(depositAndCompound);
        rewardsUtil.userDepositReward(msg.sender, shares);
        emit Deposited(msg.sender, depositAmount, shares);
    }

    /// @notice Withdraws LINK from the BoostLINK contract
    /// @param sharesAmount Amount of shares to withdraw
    function withdrawLINK(uint256 sharesAmount) external payable nonReentrant {
        require(msg.value > 0, "Please pass GMX execution fees");
        uint256 withdrawAmount = _convertToAssets(sharesAmount);
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100);
        uint256 gmxWithdrawAmount = withdrawAmount.sub(uniswapWithdrawAmount);
        _burn(msg.sender, sharesAmount);
        
        uint256 totalUniSwapAllocation = totalAssetsAmount.mul(uniswapAllocation).div(100);
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount);
        uint256 prevLinkAmount = linkToken.balanceOf(address(this));

        if (uniswapWithdrawAmount > 0) {
            uniswapLink.withdraw(uint128(uniswapWithdrawAmount), totalUniSwapAllocation);
        }

        gmxV2Link.withdraw{value: msg.value}(gmxWithdrawAmount, msg.sender);
        uint256 postLinkAmount = linkToken.balanceOf(address(this));
        uint256 linkAmount = postLinkAmount.sub(prevLinkAmount);
        
        require(linkToken.transfer(msg.sender, linkAmount), "Transfer Asset Failed");
        rewardsUtil.userWithdrawReward(msg.sender, sharesAmount);
        emit Withdrawn(msg.sender, linkAmount, sharesAmount);
    }

    /// @notice Compounds accrued fees from GMX and Uniswap
    function compoundFees() external nonReentrant {
        _compoundFees();
    }

    /// @notice Internal function to handle compounding of fees
    function _compoundFees() internal {
        uint256 prevLinkAmount = linkToken.balanceOf(address(this));
        uniswapLink.compound(); 
        gmxV2Link.compound();
        
        uint256 postLinkAmount = linkToken.balanceOf(address(this));
        uint256 treasuryAmount = (postLinkAmount.sub(prevLinkAmount)).mul(performanceFee).div(1000);
        
        treasuryFee = treasuryFee.add(treasuryAmount);
        if (treasuryFee >= minLinkAmount) {
            require(linkToken.transfer(treasury, treasuryFee), "Transfer Asset Failed");
            treasuryFee = 0; // Reset treasury fee
        }
        
        uint256 linkAmount = postLinkAmount.sub(prevLinkAmount).sub(treasuryAmount);
        compoundLinkAmount = compoundLinkAmount.add(linkAmount);
        lastCompoundTimestamp = block.timestamp;
    }

    /// @notice Sets the allocation for GMX and Uniswap
    /// @param _gmxAllocation GMX allocation percentage
    /// @param _uniswapAllocation Uniswap allocation percentage
    function setAllocation(uint256 _gmxAllocation, uint256 _uniswapAllocation) public onlyOwner {
        require(_gmxAllocation.add(_uniswapAllocation) == 100, "Allocation has to be exactly 100");
        gmxAllocation = _gmxAllocation;
        uniswapAllocation = _uniswapAllocation;
    }

    /// @notice Sets the minimum LINK amount for operations
    /// @param _minLink Minimum LINK amount
    function setMinLink(uint256 _minLink) public onlyOwner {
        minLinkAmount = _minLink;
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
    function checkUpkeep(bytes calldata data) external view override returns (bool upkeepNeeded, bytes memory performData) {
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
