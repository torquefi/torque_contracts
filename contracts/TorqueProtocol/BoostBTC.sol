// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./strategies/GMXV2BTC.sol";
import "./strategies/UniswapBTC.sol";

contract BoostBTC is AutomationCompatible, ERC4626, ReentrancyGuard, Ownable {
    
    IERC20 public wbtcToken;
    GMXV2BTC public gmxV2Btc;
    UniswapBTC public uniswapBtc;
    Treasury public treasury;

    uint256 public gmxAllocation;
    uint256 public uniswapAllocation;
    uint256 public lastCompoundTimestamp;
    uint256 public performanceFee;

    constructor(
    address _gmxV2BtcAddress,
    address _uniswapBtcAddress,
    IERC20 _asset,
    address _treasury
    ) ERC4626(_asset) {
        gmxV2Btc = GMXV2BTC(_gmxV2BtcAddress);
        uniswapBtc = UniswapBTC(_uniswapBtcAddress);
        gmxAllocation = 50;
        uniswapAllocation = 50;
        treasury = Treasury(_treasury);
    }

    function deposit(uint256 _amount) public override nonReentrant {
        _deposit(_amount);
    }

    function withdraw(uint256 sharesAmount) public override nonReentrant {
        _withdraw(sharesAmount);
    }

    function compoundFees() public override nonReentrant {
        _compoundFees();
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = (block.timestamp >= lastCompoundTimestamp + 12 hours);
    }

    function performUpkeep(bytes calldata) external override {
        if ((block.timestamp >= lastCompoundTimestamp + 12 hours)) {
            _compoundFees();
        }
    }

    function _deposit(uint256 amount) internal override {
        require(amount > 0, "Deposit amount must be greater than zero");
        uint256 gmxAllocationAmount = amount.mul(gmxAllocation).div(100);
        uint256 uniswapAllocationAmount = amount.sub(gmxAllocationAmount);
        wbtcToken.approve(address(gmxV2btcStrat), gmxAllocationAmount);
        gmxV2btcStrat.deposit(gmxAllocationAmount);
        wbtcToken.approve(address(uniswapbtcStrat), uniswapAllocationAmount);
        uniswapbtcStrat.deposit(uniswapAllocationAmount);
        uint256 shares = _convertToShares(amount, Math.Rounding.Floor);
        _mint(msg.sender, shares);
    }

    function _withdraw(uint256 sharesAmount) internal override {
        require(sharesAmount > 0, "Withdraw amount must be greater than zero");
        require(balanceOf(msg.sender) >= sharesAmount, "Insufficient balance");
        uint256 totalBTCAmount = _convertToAssets(sharesAmount, Math.Rounding.Floor);
        uint256 gmxWithdrawAmount = totalBTCAmount.mul(gmxAllocation).div(100);
        uint256 uniswapWithdrawAmount = totalBTCAmount.sub(gmxWithdrawAmount);
        _burn(msg.sender, sharesAmount);
        gmxV2btcStrat.withdraw(gmxWithdrawAmount);
        uniswapbtcStrat.withdraw(uniswapWithdrawAmount);
        wbtcToken.transfer(msg.sender, totalBTCAmount);
    }

    function _compoundFees() internal override {
        uint256 gmxV2btcBalanceBefore = gmxV2btcStrat.balanceOf(address(this));
        uint256 uniswapbtcBalanceBefore = uniswapbtcStrat.balanceOf(address(this));
        uint256 totalBalanceBefore = gmxV2btcBalanceBefore.add(uniswapbtcBalanceBefore);
        gmxV2btcStrat.withdrawGMX();
        uniswapbtcStrat.withdrawuniswap();
        uint256 feeAmount = totalBalanceBefore.mul(performanceFee).div(10000);
        uint256 treasuryFee = performanceFee.mul(performanceFee).div(100);
        uint256 gmxV2btcFee = gmxV2btcStrat.balanceOf(address(this));
        uint256 uniswapbtcFee = uniswapbtcStrat.balanceOf(address(this));
        wbtcToken.transfer(addresses.treasury, treasuryFee);
        uint256 totalBalanceAfter = gmxV2btcFee.add(uniswapbtcFee);
        uint256 gmxV2btcFeeActualPercent = gmxV2btcFee.mul(100).div(totalBalanceAfter);
        uint256 uniswapbtcFeeActualPercent = uniswapbtcFee.mul(100).div(totalBalanceAfter);
        gmxV2btcStrat.deposit();
        uniswapbtcStrat.deposit();
        lastCompoundTimestamp = block.timestamp;
    }

    function setAllocation() public onlyOwner {
        gmxAllocation = _gmxAllocation;
        uniswapAllocation = _uniswapAllocation;
    }

    function setPerformanceFee(uint256 _performanceFee) public onlyOwner {
        performanceFee = _performanceFee;
    }

    function setTreasury(address _treasury) public onlyOwner {
        treasury = Treasury(_treasury);
    }

    function _checkUpkeep(bytes calldata) external virtual view returns (bool upkeepNeeded, bytes memory);
    
    function _performUpkeep(bytes calldata) external virtual;

    receive() external payable {}
}
