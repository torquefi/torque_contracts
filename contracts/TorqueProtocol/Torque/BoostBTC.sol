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
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Config {
        address treasury;
        uint256 gmxV2btcPercent;
        uint256 uniswapbtcPercent;
        uint256 performanceFee;
    }

    struct Addresses {
        address tTokenContract;
        address wbtcTokenAddress;
        address gmxV2btcVaultAddress;
        address uniswapbtcVaultAddress;
        address treasury;
    }

    Config public config;
    Addresses public addresses;
    Iwbtc public wbtcToken;
    tToken public tTokenContract;
    GMXV2Btc public gmxV2btcVault;
    uniswapbtc public uniswapbtcVault;
    RewardUtil public rewardUtil;
    uint public totalSupplied;
    uint256 public lastCompoundTimestamp;

    constructor(
        address _wbtcTokenAddress,
        address _tTokenContract,
        address _gmxV2btcVaultAddress,
        address _uniswapbtcVaultAddress,
        address _treasury
    ) {
        wbtcToken = Iwbtc(_wbtcTokenAddress);
        tTokenContract = tToken(_tTokenContract);
        gmxV2btcVault = GMXV2btc(_gmxV2btcVaultAddress);
        uniswapbtcVault = uniswapbtc(_uniswapbtcVaultAddress);
        addresses.treasury = _treasury;
        config.gmxV2btcPercent = 50;
        config.uniswapbtcPercent = 50;
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

    function sweep(address[] memory _tokens, address _treasury) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address tokenAddress = _tokens[i];
            uint256 balance;
            if (tokenAddress == address(0)) {
                balance = address(this).balance;
                if (balance > 0) {
                    payable(_treasury).transfer(balance);
                    emit EtherSwept(_treasury, balance);
                }
            } else {
                IERC20 token = IERC20(tokenAddress);
                balance = token.balanceOf(address(this));
                if (balance > 0) {
                    token.transfer(_treasury, balance);
                    emit TokensSwept(tokenAddress, _treasury, balance);
                }
            }
        }
    }

    function _deposit(uint256 amount) internal {
        require(amount > 0, "Deposit amount must be greater than zero");
        wbtcToken.deposit{value: amount}();
        uint256 half = amount.div(2);
        wbtcToken.approve(address(gmxV2btcVault), half);
        gmxV2btcVault.deposit(half);
        wbtcToken.approve(address(uniswapbtcVault), half);
        uniswapbtcVault.deposit(half);
        tTokenContract.mint(msg.sender, amount);
        totalSupplied = totalSupplied.add(amount);
        RewardUtil(rewardUtil).updateReward(msg.sender);
        emit Deposit(msg.sender, amount, amount);
    }

    function _withdraw(uint256 tTokenAmount) internal {
        _checkWithdraw(tTokenAmount);
        uint256 btcAmount = calculatebtcAmount(tTokenAmount);
        require(btcAmount <= address(this).balance, "Insufficient btc balance in contract");
        gmxV2btcVault.withdraw(tTokenAmount.div(2));
        uniswapbtcVault.withdraw(tTokenAmount.div(2));
        tTokenContract.burn(msg.sender, tTokenAmount);
        wbtcToken.withdraw(btcAmount);
        (bool success, ) = msg.sender.call{value: btcAmount}("");
        require(success, "btc transfer failed");
        totalSupplied = totalSupplied.sub(btcAmount);
        RewardUtil(rewardUtil).updateReward(msg.sender);
        emit Withdraw(msg.sender, tTokenAmount, btcAmount);
    }

    function _compoundFees() internal {
        uint256 gmxV2btcBalanceBefore = gmxV2btcVault.balanceOf(address(this));
        uint256 uniswapbtcBalanceBefore = uniswapbtcVault.balanceOf(address(this));
        uint256 totalBalanceBefore = gmxV2btcBalanceBefore.add(uniswapbtcBalanceBefore);
        gmxV2btcVault.withdrawGMX();
        uniswapbtcVault.withdrawuniswap();
        uint256 performanceFee = totalBalanceBefore.mul(config.performanceFee).div(10000);
        uint256 treasuryFee = performanceFee.mul(20).div(100);
        uint256 gmxV2btcFee = gmxV2btcVault.balanceOf(address(this));
        uint256 uniswapbtcFee = uniswapbtcVault.balanceOf(address(this));
        payable(addresses.treasury).transfer(treasuryFee);
        uint256 totalBalanceAfter = gmxV2btcFee.add(uniswapbtcFee);
        uint256 gmxV2btcFeeActualPercent = gmxV2btcFee.mul(100).div(totalBalanceAfter);
        uint256 uniswapbtcFeeActualPercent = uniswapbtcFee.mul(100).div(totalBalanceAfter);
        gmxV2btcVault.deposit();
        uniswapbtcVault.deposit();
        lastCompoundTimestamp = block.timestamp;
        emit Compound(gmxV2btcFeeActualPercent, uniswapbtcFeeActualPercent);
    }
    
    function calculatebtcAmount(uint256 tTokenAmount) public view returns (uint256) {
        uint256 totalSupply = tTokenContract.totalSupply();
        if (totalSupply == 0) return 0;
        uint256 btcBalance = address(this).balance;
        return tTokenAmount.mul(btcBalance).div(totalSupply);
    }
    
    receive() external payable {}
}
