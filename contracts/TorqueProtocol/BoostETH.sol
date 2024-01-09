// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

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

import "./interfaces/IStargateLPStaking.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IGMX.sol";

import "./strategies/StargateETH.sol";
import "./strategies/GMXV2ETH.sol";

contract BoostETH is AutomationCompatible, ERC4626, ReentrancyGuard, Ownable {

    IERC20 public wethToken;
    GMXV2ETH public gmxV2Eth;
    StargateETH public stargateETH;
    Treasury public treasury;

    uint256 public gmxAllocation;
    uint256 public stargateAllocation;
    uint256 public lastCompoundTimestamp;
    uint256 public performanceFee;

    constructor(
    address _gmxV2EthAddress,
    address _stargateEthAddress,
    IERC20 _asset,
    address _treasury
    ) ERC4626(_asset) {
        gmxV2Eth = GMXV2ETH(_gmxV2EthAddress);
        stargateEth = StargateETH(_stargateEthAddress);
        gmxAllocation = 50;
        stargateAllocation = 50;
        treasury = Treasury(_treasury);
    }

    function deposit() external payable override nonReentrant {
        _deposit(msg.value);
    }

    function withdraw(uint256 sharesAmount) external override nonReentrant {
        _withdraw(sharesAmount);
    }

    function compoundFees() external override nonReentrant {
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

    function _deposit(uint256 amount) internal {
        require(amount > 0, "Deposit amount must be greater than zero");
        wethToken.deposit{value: amount}();
        uint256 gmxAllocationAmount = amount.mul(gmxAllocation).div(100);
        uint256 stargateAllocationAmount = amount.sub(gmxAllocationAmount);
        wethToken.approve(address(gmxV2Eth), gmxAllocationAmount);
        gmxV2Eth.deposit(gmxAllocationAmount);
        wethToken.approve(address(stargateETH), stargateAllocationAmount);
        stargateETH.deposit(stargateAllocationAmount);
        uint256 shares = _convertToShares(amount, Math.Rounding.Floor);
        _mint(msg.sender, shares);
    }

    function _withdraw(uint256 sharesAmount) internal {
        require(sharesAmount > 0, "Withdraw amount must be greater than zero");
        require(balanceOf(msg.sender) >= sharesAmount, "Insufficient share balance");
        uint256 totalETHAmount = _convertToAssets(sharesAmount, Math.Rounding.Floor);
        uint256 gmxWithdrawAmount = totalETHAmount.mul(gmxAllocation).div(100);
        uint256 stargateWithdrawAmount = totalETHAmount.sub(gmxWithdrawAmount);
        _burn(msg.sender, sharesAmount);
        gmxV2Eth.withdraw(gmxWithdrawAmount);
        stargateETH.withdraw(stargateWithdrawAmount);
        wethToken.withdraw(totalETHAmount);
        payable(msg.sender).transfer(totalETHAmount);
    }

    function _compoundFees() internal override {
        uint256 gmxV2EthBalanceBefore = gmxV2EthStrat.balanceOf(address(this));
        uint256 stargateEthBalanceBefore = stargateEthStrat.balanceOf(address(this));
        uint256 totalBalanceBefore = gmxV2EthBalanceBefore.add(stargateEthBalanceBefore);
        gmxV2EthStrat.withdrawGMX();
        stargateEthStrat.withdrawStargate();
        uint256 performanceFee = totalBalanceBefore.mul(performanceFee).div(10000);
        uint256 treasuryFee = performanceFee.mul(performanceFee).div(100);
        uint256 gmxV2EthFee = gmxV2EthStrat.balanceOf(address(this));
        uint256 stargateEthFee = stargateEthStrat.balanceOf(address(this));
        payable(addresses.treasury).transfer(treasuryFee);
        uint256 totalBalanceAfter = gmxV2EthFee.add(stargateEthFee);
        uint256 gmxV2EthFeeActualPercent = gmxV2EthFee.mul(100).div(totalBalanceAfter);
        uint256 stargateEthFeeActualPercent = stargateEthFee.mul(100).div(totalBalanceAfter);
        gmxV2EthStrat.deposit();
        stargateEthStrat.deposit();
        lastCompoundTimestamp = block.timestamp;
    }

    function setAllocation() public onlyOwner {
        gmxAllocation = _gmxAllocation;
        stargateAllocation = _stargateAllocation;
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
