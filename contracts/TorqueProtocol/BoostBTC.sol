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
import "./interfaces/IGMX.sol";
import "./strategies/GMXV2BTC.sol";
import "./strategies/UniswapBTC.sol";
import "./tToken.sol";

contract BoostBTC is BoostAbstract, AutomationCompatible {
    Iwbtc public wbtcToken;
    GMXV2Btc public gmxV2btcStrat;
    uniswapbtc public uniswapbtcStrat;

    constructor(
        address _wbtcTokenAddress,
        address _tTokenContract,
        address _gmxV2btcStratAddress,
        address _uniswapbtcStratAddress,
        address _treasury
    ) BoostAbstract(_tTokenContract, _treasury) {
        wbtcToken = Iwbtc(_wbtcTokenAddress);
        gmxV2btcStrat = GMXV2Btc(_gmxV2btcStratAddress);
        uniswapbtcStrat = uniswapbtc(_uniswapbtcStratAddress);
        config.gmxV2btcPercent = 50;
        config.uniswapbtcPercent = 50;
    }

    function deposit(uint256 _amount) public override nonReentrant {
        _deposit(_amount);
    }

    function withdraw(uint256 tTokenAmount) public override nonReentrant {
        _withdraw(tTokenAmount);
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
        wbtcToken.deposit{value: amount}();
        uint256 half = amount.div(2);
        wbtcToken.approve(address(gmxV2btcStrat), half);
        gmxV2btcStrat.deposit(half);
        wbtcToken.approve(address(uniswapbtcStrat), half);
        uniswapbtcStrat.deposit(half);
        tTokenContract.mint(msg.sender, amount);
        _updateTotalSupplied(amount, true);
        emit Deposit(msg.sender, amount);
    }

    function _withdraw(uint256 tTokenAmount) internal override {
        require(tTokenAmount > 0, "Withdraw amount must be greater than zero");
        require(tTokenContract.balanceOf(msg.sender) >= tTokenAmount, "Insufficient tToken balance");
        uint256 btcAmount = calculatebtcAmount(tTokenAmount);
        gmxV2btcStrat.withdraw(tTokenAmount.div(2));
        uniswapbtcStrat.withdraw(tTokenAmount.div(2));
        tTokenContract.burn(msg.sender, tTokenAmount);
        wbtcToken.transfer(msg.sender, btcAmount);
        _updateTotalSupplied(btcAmount, false);
        emit Withdraw(msg.sender, tTokenAmount);
    }

    function _compoundFees() internal override {
        uint256 gmxV2btcBalanceBefore = gmxV2btcStrat.balanceOf(address(this));
        uint256 uniswapbtcBalanceBefore = uniswapbtcStrat.balanceOf(address(this));
        uint256 totalBalanceBefore = gmxV2btcBalanceBefore.add(uniswapbtcBalanceBefore);
        gmxV2btcStrat.withdrawGMX();
        uniswapbtcStrat.withdrawuniswap();
        uint256 performanceFee = totalBalanceBefore.mul(config.performanceFee).div(10000);
        uint256 treasuryFee = performanceFee.mul(20).div(100);
        uint256 gmxV2btcFee = gmxV2btcStrat.balanceOf(address(this));
        uint256 uniswapbtcFee = uniswapbtcStrat.balanceOf(address(this));
        wbtcToken.transfer(addresses.treasury, treasuryFee);
        uint256 totalBalanceAfter = gmxV2btcFee.add(uniswapbtcFee);
        uint256 gmxV2btcFeeActualPercent = gmxV2btcFee.mul(100).div(totalBalanceAfter);
        uint256 uniswapbtcFeeActualPercent = uniswapbtcFee.mul(100).div(totalBalanceAfter);
        gmxV2btcStrat.deposit();
        uniswapbtcStrat.deposit();
        lastCompoundTimestamp = block.timestamp;
        emit Compound(gmxV2btcFeeActualPercent, uniswapbtcFeeActualPercent);
    }
    
    function calculatebtcAmount(uint256 tTokenAmount) public view returns (uint256) {
        uint256 totalSupply = tTokenContract.totalSupply();
        if (totalSupply == 0) return 0;
        uint256 btcBalance = wbtcToken.balanceOf(address(this));
        return tTokenAmount.mul(btcBalance).div(totalSupply);
    }

    receive() external payable {}
}
