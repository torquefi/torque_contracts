// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./BoostAbstract.sol";

import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

import "./interfaces/IStargateLPStaking.sol";
import "./interfaces/ISwapRouterV3.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IGMX.sol";

import "./strategies/StargateETH.sol";
import "./strategies/GMXV2ETH.sol";

import "./tToken.sol";

contract BoostETH is BoostAbstract, AutomationCompatibleInterface {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Config {
        address treasury;
        uint256 gmxV2EthPercent;
        uint256 stargateEthPercent;
        uint256 performanceFee;
    }

    struct Addresses {
        address tTokenContract;
        address wethTokenAddress;
        address gmxV2EthVaultAddress;
        address stargateEthVaultAddress;
        address treasury;
    }

    Config public config;
    Addresses public addresses;
    IWETH public wethToken;
    tToken public tTokenContract;
    GMXV2ETH public gmxV2EthVault;
    StargateETH public stargateEthVault;
    RewardUtil public rewardUtil;
    uint public totalSupplied;
    uint256 public lastCompoundTimestamp;

    constructor(
        address _wethTokenAddress,
        address _tTokenContract,
        address _gmxV2EthVaultAddress,
        address _stargateEthVaultAddress,
        address _treasury
    ) {
        wethToken = IWETH(_wethTokenAddress);
        tTokenContract = tToken(_tTokenContract);
        gmxV2EthVault = GMXV2ETH(_gmxV2EthVaultAddress);
        stargateEthVault = StargateETH(_stargateEthVaultAddress);
        addresses.treasury = _treasury;
        config.gmxV2EthPercent = 50;
        config.stargateEthPercent = 50;
        config.performanceFee = 2000;
    }

    function deposit() external payable nonReentrant {
        _deposit(msg.value);
    }

    function withdraw(uint256 tTokenAmount) external nonReentrant {
        _withdraw(tTokenAmount);
    }

    function compoundFees() external nonReentrant {
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
        uint256 half = amount.div(2);
        wethToken.approve(address(gmxV2EthVault), half);
        gmxV2EthVault.deposit(half);
        wethToken.approve(address(stargateEthVault), half);
        stargateEthVault.deposit(half);
        tTokenContract.mint(msg.sender, amount);
        totalSupplied = totalSupplied.add(amount);
        RewardUtil(rewardUtil).updateReward(msg.sender);
        emit Deposit(msg.sender, amount, amount);
    }

    function _withdraw(uint256 tTokenAmount) internal {
        _checkWithdraw(tTokenAmount);
        uint256 ethAmount = calculateEthAmount(tTokenAmount);
        require(ethAmount <= address(this).balance, "Insufficient ETH balance in contract");
        gmxV2EthVault.withdraw(tTokenAmount.div(2));
        stargateEthVault.withdraw(tTokenAmount.div(2));
        tTokenContract.burn(msg.sender, tTokenAmount);
        wethToken.withdraw(ethAmount);
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");
        totalSupplied = totalSupplied.sub(ethAmount);
        RewardUtil(rewardUtil).updateReward(msg.sender);
        emit Withdraw(msg.sender, tTokenAmount, ethAmount);
    }

    function _compoundFees() internal {
        uint256 gmxV2EthBalanceBefore = gmxV2EthVault.balanceOf(address(this));
        uint256 stargateEthBalanceBefore = stargateEthVault.balanceOf(address(this));
        uint256 totalBalanceBefore = gmxV2EthBalanceBefore.add(stargateEthBalanceBefore);
        gmxV2EthVault.withdrawGMX();
        stargateEthVault.withdrawStargate();
        uint256 performanceFee = totalBalanceBefore.mul(config.performanceFee).div(10000);
        uint256 treasuryFee = performanceFee.mul(20).div(100);
        uint256 gmxV2EthFee = gmxV2EthVault.balanceOf(address(this));
        uint256 stargateEthFee = stargateEthVault.balanceOf(address(this));
        payable(addresses.treasury).transfer(treasuryFee);
        uint256 totalBalanceAfter = gmxV2EthFee.add(stargateEthFee);
        uint256 gmxV2EthFeeActualPercent = gmxV2EthFee.mul(100).div(totalBalanceAfter);
        uint256 stargateEthFeeActualPercent = stargateEthFee.mul(100).div(totalBalanceAfter);
        gmxV2EthVault.deposit();
        stargateEthVault.deposit();
        lastCompoundTimestamp = block.timestamp;
        emit Compound(gmxV2EthFeeActualPercent, stargateEthFeeActualPercent);
    }
    
    function calculateEthAmount(uint256 tTokenAmount) public view returns (uint256) {
        uint256 totalSupply = tTokenContract.totalSupply();
        if (totalSupply == 0) return 0;
        uint256 ethBalance = address(this).balance;
        return tTokenAmount.mul(ethBalance).div(totalSupply);
    }
    
    receive() external payable {}
}
