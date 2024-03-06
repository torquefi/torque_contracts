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

import "./strategies/GMXV2BTC.sol";
import "./strategies/UniswapBTC.sol";

interface RewardsUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
}

contract BoostBTC is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;
    
    IERC20 public wbtcToken;
    GMXV2BTC public gmxV2Btc;
    UniswapBTC public uniswapBtc;
    address public treasury;
    RewardsUtil public rewardsUtil;

    uint256 public gmxAllocation;
    uint256 public uniswapAllocation;
    uint256 public lastCompoundTimestamp;
    uint256 public performanceFee = 10;
    uint256 public minWbtcAmount = 20000;
    uint256 public treasuryFee = 0;

    uint256 public totalAssetsAmount = 0;
    uint256 public compoundWbtcAmount = 0;

    constructor(
    string memory _name, 
    string memory _symbol,
    address wBTC,
    address payable _gmxV2BtcAddress,
    address _uniswapBtcAddress,
    address _treasury,
    address _rewardsUtil
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        wbtcToken = IERC20(wBTC);
        gmxV2Btc = GMXV2BTC(_gmxV2BtcAddress);
        uniswapBtc = UniswapBTC(_uniswapBtcAddress);
        gmxAllocation = 50;
        uniswapAllocation = 50;
        treasury = _treasury;
        rewardsUtil = RewardsUtil(_rewardsUtil);
    }

    function depositBTC(uint256 depositAmount) external payable nonReentrant() {
        require(msg.value > 0, "Please pass GMX execution fees");
        require(wbtcToken.balanceOf(address(this)) >= compoundWbtcAmount, "Insufficient compound balance");
        wbtcToken.transferFrom(msg.sender, address(this), depositAmount);
        uint256 depositAndCompound = depositAmount + compoundWbtcAmount;
        compoundWbtcAmount = 0;
        uint256 uniswapDepositAmount = depositAndCompound.mul(uniswapAllocation).div(100);
        uint256 gmxDepositAmount = depositAndCompound.sub(uniswapDepositAmount);
        wbtcToken.approve(address(uniswapBtc), uniswapDepositAmount);
        uniswapBtc.deposit(uniswapDepositAmount);

        wbtcToken.approve(address(gmxV2Btc), gmxDepositAmount);
        gmxV2Btc.deposit{value: msg.value}(gmxDepositAmount);

        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares);
        totalAssetsAmount = totalAssetsAmount.add(depositAndCompound);
        rewardsUtil.userDepositReward(msg.sender, shares);
    }

    function withdrawBTC(uint256 sharesAmount) external payable nonReentrant() {
        require(msg.value > 0, "Please pass GMX execution fees");
        uint256 withdrawAmount = _convertToAssets(sharesAmount);
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100);
        uint256 gmxWithdrawAmount = withdrawAmount.sub(uniswapWithdrawAmount);
        _burn(msg.sender, sharesAmount);
        uint256 totalUniSwapAllocation = totalAssetsAmount.mul(uniswapAllocation).div(100);
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount);

        uint256 prevWbtcAmount = wbtcToken.balanceOf(address(this));
        uniswapBtc.withdraw(uint128(uniswapWithdrawAmount), totalUniSwapAllocation);
        gmxV2Btc.withdraw{value: msg.value}(gmxWithdrawAmount, msg.sender);
        uint256 postWbtcAmount = wbtcToken.balanceOf(address(this));
        uint256 wbtcAmount = postWbtcAmount - prevWbtcAmount;
        wbtcToken.transfer(msg.sender, wbtcAmount);
        rewardsUtil.userWithdrawReward(msg.sender, sharesAmount);
    }

    function compoundFees() external nonReentrant(){
        _compoundFees();
    }

    function _compoundFees() internal {
        uint256 prevWbtcAmount = wbtcToken.balanceOf(address(this));
        uniswapBtc.compound(); 
        gmxV2Btc.compound();
        uint256 postWbtcAmount = wbtcToken.balanceOf(address(this));
        uint256 treasuryAmount = (postWbtcAmount - prevWbtcAmount).mul(performanceFee).div(1000);
        treasuryFee = treasuryFee.add(treasuryAmount);
        if(treasuryFee >= minWbtcAmount){
            wbtcToken.transfer(treasury , treasuryFee);
            treasuryFee = 0;
        }
        uint256 wbtcAmount = postWbtcAmount - prevWbtcAmount - treasuryAmount;
        compoundWbtcAmount += wbtcAmount;
        lastCompoundTimestamp = block.timestamp;
    }

    function setAllocation(uint256 _gmxAllocation, uint256 _uniswapAllocation) public onlyOwner {
        require(_gmxAllocation + _uniswapAllocation == 100, "Allocation has to be exactly 100");
        gmxAllocation = _gmxAllocation;
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

    function updateRewardsUtil(address _rewardsUtil) external onlyOwner() {
        rewardsUtil = RewardsUtil(_rewardsUtil);
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
