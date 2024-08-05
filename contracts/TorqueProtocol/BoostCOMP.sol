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

contract BoostCOMP is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;

    event Deposited(address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    
    IERC20 public compToken;
    UniswapCOMP public uniswapComp;
    address public treasury;
    TORQRewardUtil public torqRewardUtil;

    uint256 public gmxAllocation;
    uint256 public uniswapAllocation = 100;
    uint256 public lastCompoundTimestamp;
    uint256 public performanceFee = 10;
    uint256 public minCompAmount = 10000000000000000;
    uint256 public treasuryFee = 0;

    uint256 public totalAssetsAmount = 0;
    uint256 public compoundCompAmount = 0;

    constructor(
    string memory _name, 
    string memory _symbol,
    address COMP,
    address _uniswapCompAddress,
    address _treasury,
    address _torqRewardUtil
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        compToken = IERC20(COMP);
        uniswapComp = UniswapCOMP(_uniswapCompAddress);
        treasury = _treasury;
        torqRewardUtil = TORQRewardUtil(_torqRewardUtil);
    }

    function depositCOMP(uint256 depositAmount) external payable nonReentrant() {
        require(compToken.balanceOf(address(this)) >= compoundCompAmount, "Insufficient compound balance");
        require(compToken.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");
        uint256 uniswapDepositAmount = depositAmount + compoundCompAmount;
        compoundCompAmount = 0;
        compToken.approve(address(uniswapComp), uniswapDepositAmount);
        uniswapComp.deposit(uniswapDepositAmount);

        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares);
        totalAssetsAmount = totalAssetsAmount.add(uniswapDepositAmount);
        torqRewardUtil.userDepositReward(msg.sender, shares);
        emit Deposited(msg.sender, depositAmount, shares);
    }

    function withdrawCOMP(uint256 sharesAmount) external nonReentrant() {
        uint256 withdrawAmount = _convertToAssets(sharesAmount);
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100);
        _burn(msg.sender, sharesAmount);
        uint256 totalUniSwapAllocation = totalAssetsAmount.mul(uniswapAllocation).div(100);
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount);

        uint256 prevCompAmount = compToken.balanceOf(address(this));
        
        if(uniswapWithdrawAmount > 0) {
            uniswapComp.withdraw(uint128(uniswapWithdrawAmount), totalUniSwapAllocation);
        }
        
        uint256 postCompAmount = compToken.balanceOf(address(this));
        uint256 compAmount = postCompAmount - prevCompAmount;
        require(compToken.transfer(msg.sender, compAmount), "Transfer Asset Failed");
        torqRewardUtil.userWithdrawReward(msg.sender, sharesAmount);
        emit Withdrawn(msg.sender, compAmount, sharesAmount);
    }

    function compoundFees() external nonReentrant(){
        _compoundFees();
    }

    function _compoundFees() internal {
        uint256 prevCompAmount = compToken.balanceOf(address(this));
        uniswapComp.compound(); 
        uint256 postCompAmount = compToken.balanceOf(address(this));
        uint256 treasuryAmount = (postCompAmount - prevCompAmount).mul(performanceFee).div(1000);
        treasuryFee = treasuryFee.add(treasuryAmount);
        if(treasuryFee >= minCompAmount){
            require(compToken.transfer(treasury , treasuryFee), "Transfer Asset Failed");
            treasuryFee = 0;
        }
        uint256 compAmount = postCompAmount - prevCompAmount - treasuryAmount;
        compoundCompAmount += compAmount;
        lastCompoundTimestamp = block.timestamp;
    }

    function setMinComp(uint256 _minComp) public onlyOwner() {
        minCompAmount = _minComp;
    }

    function setPerformanceFee(uint256 _performanceFee) public onlyOwner {
        require(_performanceFee <= 1000, "Treasury Fee can't be more than 100%");
        performanceFee = _performanceFee;
    }

    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function withdrawTreasuryFees() external onlyOwner() {
        payable(treasury).transfer(address(this).balance);
    }

    function decimals() public view override returns (uint8) {
        return 18;
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (assets==0 || supply==0) ? assets : assets.mulDiv(supply, totalAssets(), Math.Rounding.Down);
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256){
        uint256 supply = totalSupply();
        return (supply==0) ? shares : shares.mulDiv(totalAssets(), supply, Math.Rounding.Down);
    }

    function totalAssets() public view returns (uint256) {
        return totalAssetsAmount;
    }

    function updateTORQRewardUtil(address _torqRewardUtil) external onlyOwner() {
        torqRewardUtil = TORQRewardUtil(_torqRewardUtil);
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp >= lastCompoundTimestamp + 12 hours);
    }

    function performUpkeep(bytes calldata) external override {
        if ((block.timestamp >= lastCompoundTimestamp + 12 hours)) {
            _compoundFees();
        }
    }

    receive() external payable {}
}
