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
import "./interfaces/IWETH.sol";
import "./interfaces/IGMX.sol";
import "./strategies/StargateETH.sol";
import "./strategies/GMXV2ETH.sol";
import "./tToken.sol";

contract BoostETH is BoostAbstract, AutomationCompatible {
    IWETH public wethToken;
    GMXV2ETH public gmxV2EthStrat;
    StargateETH public stargateEthStrat;

    constructor(
        address _wethTokenAddress,
        address _tTokenContract,
        address _gmxV2EthStratAddress,
        address _stargateEthStratAddress,
        address _treasury
    ) BoostAbstract(_tTokenContract, _treasury) {
        wethToken = IWETH(_wethTokenAddress);
        gmxV2EthStrat = GMXV2ETH(_gmxV2EthStratAddress);
        stargateEthStrat = StargateETH(_stargateEthStratAddress);
        config.gmxV2EthPercent = 50;
        config.stargateEthPercent = 50;
    }

    function deposit() external payable override nonReentrant {
        _deposit(msg.value);
    }

    function withdraw(uint256 tTokenAmount) external override nonReentrant {
        _withdraw(tTokenAmount);
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
        uint256 half = amount.div(2);
        wethToken.approve(address(gmxV2EthStrat), half);
        gmxV2EthStrat.deposit(half);
        wethToken.approve(address(stargateEthStrat), half);
        stargateEthStrat.deposit(half);
        tTokenContract.mint(msg.sender, amount);
        _updateTotalSupplied(amount, true);
        emit Deposit(msg.sender, amount);
    }

    function _withdraw(uint256 tTokenAmount) internal {
        require(tTokenAmount > 0, "Withdraw amount must be greater than zero");
        require(tTokenContract.balanceOf(msg.sender) >= tTokenAmount, "Insufficient tToken balance");
        uint256 ethAmount = calculateEthAmount(tTokenAmount);
        gmxV2EthStrat.withdraw(tTokenAmount.div(2));
        stargateEthStrat.withdraw(tTokenAmount.div(2));
        tTokenContract.burn(msg.sender, tTokenAmount);
        wethToken.withdraw(ethAmount);
        payable(msg.sender).transfer(ethAmount);
        _updateTotalSupplied(ethAmount, false);
        emit Withdraw(msg.sender, tTokenAmount);
    }

    function _compoundFees() internal override {
        uint256 gmxV2EthBalanceBefore = gmxV2EthStrat.balanceOf(address(this));
        uint256 stargateEthBalanceBefore = stargateEthStrat.balanceOf(address(this));
        uint256 totalBalanceBefore = gmxV2EthBalanceBefore.add(stargateEthBalanceBefore);
        gmxV2EthStrat.withdrawGMX();
        stargateEthStrat.withdrawStargate();
        uint256 performanceFee = totalBalanceBefore.mul(config.performanceFee).div(10000);
        uint256 treasuryFee = performanceFee.mul(20).div(100);
        uint256 gmxV2EthFee = gmxV2EthStrat.balanceOf(address(this));
        uint256 stargateEthFee = stargateEthStrat.balanceOf(address(this));
        payable(addresses.treasury).transfer(treasuryFee);
        uint256 totalBalanceAfter = gmxV2EthFee.add(stargateEthFee);
        uint256 gmxV2EthFeeActualPercent = gmxV2EthFee.mul(100).div(totalBalanceAfter);
        uint256 stargateEthFeeActualPercent = stargateEthFee.mul(100).div(totalBalanceAfter);
        gmxV2EthStrat.deposit();
        stargateEthStrat.deposit();
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
