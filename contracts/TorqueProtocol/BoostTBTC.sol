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

import "./strategies/CurveTBTC.sol";
import "./strategies/UniswapTBTC.sol";

interface TORQRewardUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
}

contract BoostTBTC is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;

    event Deposited(address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    
    IERC20 public wbtcToken;
    CurveTBTC public curveTBTC; // 0x186cF879186986A20aADFb7eAD50e3C20cb26CeC
    UniswapTBTC public uniswapTBTC;
    address public treasury;
    TORQRewardUtil public torqRewardUtil;

    uint256 public curveAllocation;
    uint256 public uniswapAllocation;
    uint256 public lastCompoundTimestamp;
    uint256 public performanceFee = 10;
    uint256 public minWbtcAmount = 20000;
    uint256 public treasuryFee = 0;
    uint256 public totalUniSwapAllocation = 0;
    uint256 public totalCurveAllocation = 0;

    uint256 public totalAssetsAmount = 0;
    uint256 public compoundWbtcAmount = 0;

    constructor(
    string memory _name, 
    string memory _symbol,
    address wBTC,
    address _curveTBTCAddress,
    address _uniswapTBTCAddress,
    address _treasury,
    address _torqRewardUtil
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        wbtcToken = IERC20(wBTC);
        curveTBTC = CurveTBTC(_curveTBTCAddress);
        uniswapTBTC = UniswapTBTC(_uniswapTBTCAddress);
        curveAllocation = 50;
        uniswapAllocation = 50;
        treasury = _treasury;
        torqRewardUtil = TORQRewardUtil(_torqRewardUtil);
    }

    function depositBTC(uint256 depositAmount) external nonReentrant() {
        require(wbtcToken.balanceOf(address(this)) >= compoundWbtcAmount, "Insufficient compound balance");
        require(wbtcToken.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");
        uint256 depositAndCompound = depositAmount + compoundWbtcAmount;
        compoundWbtcAmount = 0;
        uint256 uniswapDepositAmount = depositAndCompound.mul(uniswapAllocation).div(100);
        uint256 curveDepositAmount = depositAndCompound.sub(uniswapDepositAmount);
        
        if(uniswapDepositAmount > 0) {
            wbtcToken.approve(address(uniswapTBTC), uniswapDepositAmount);
            uniswapTBTC.deposit(uniswapDepositAmount);
            totalUniSwapAllocation += uniswapDepositAmount;
        }

        wbtcToken.approve(address(curveTBTC), curveDepositAmount);
        curveTBTC.deposit(curveDepositAmount);
        totalCurveAllocation += curveDepositAmount;

        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares);
        totalAssetsAmount = totalAssetsAmount.add(depositAndCompound);
        // torqRewardUtil.userDepositReward(msg.sender, shares);
        emit Deposited(msg.sender, depositAmount, shares);
    }

    function withdrawBTC(uint256 sharesAmount) external nonReentrant() {
        uint256 withdrawAmount = _convertToAssets(sharesAmount);
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100);
        uint256 curveWithdrawAmount = withdrawAmount.sub(uniswapWithdrawAmount);
        _burn(msg.sender, sharesAmount);
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount);

        uint256 prevWbtcAmount = wbtcToken.balanceOf(address(this));
        
        if(uniswapWithdrawAmount > 0) {
            uniswapTBTC.withdraw(uint128(uniswapWithdrawAmount), totalUniSwapAllocation);
            totalUniSwapAllocation -= uniswapWithdrawAmount;
        }
        
        curveTBTC.withdraw(curveWithdrawAmount, totalCurveAllocation);
        totalCurveAllocation -= curveWithdrawAmount;
        
        uint256 postWbtcAmount = wbtcToken.balanceOf(address(this));
        uint256 wbtcAmount = postWbtcAmount - prevWbtcAmount;
        require(wbtcToken.transfer(msg.sender, wbtcAmount), "Transfer Asset Failed");
        // torqRewardUtil.userWithdrawReward(msg.sender, sharesAmount);
        emit Withdrawn(msg.sender, wbtcAmount, sharesAmount);
    }

    function compoundFees() external nonReentrant(){
        _compoundFees();
    }

    function _compoundFees() internal {
        uint256 prevWbtcAmount = wbtcToken.balanceOf(address(this));
        uniswapTBTC.compound(); 
        curveTBTC.compound();
        uint256 postWbtcAmount = wbtcToken.balanceOf(address(this));
        uint256 treasuryAmount = (postWbtcAmount - prevWbtcAmount).mul(performanceFee).div(1000);
        treasuryFee = treasuryFee.add(treasuryAmount);
        if(treasuryFee >= minWbtcAmount){
            require(wbtcToken.transfer(treasury , treasuryFee), "Transfer Asset Failed");
            treasuryFee = 0;
        }
        uint256 wbtcAmount = postWbtcAmount - prevWbtcAmount - treasuryAmount;
        compoundWbtcAmount += wbtcAmount;
        lastCompoundTimestamp = block.timestamp;
    }

    function setAllocation(uint256 _curveAllocation, uint256 _uniswapAllocation) public onlyOwner {
        require(_curveAllocation + _uniswapAllocation == 100, "Allocation has to be exactly 100");
        curveAllocation = _curveAllocation;
        uniswapAllocation = _uniswapAllocation;
    }

    function setMinWbtc(uint256 _minWbtc) public onlyOwner() {
        minWbtcAmount = _minWbtc;
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
        return 8;
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
