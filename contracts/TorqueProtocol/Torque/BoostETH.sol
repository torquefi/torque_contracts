// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IStargateLPStaking.sol";
import "./interfaces/ISwapRouterV3.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IGMX.sol";

import "./strategies/StargateETH.sol";
import "./strategies/GMXV2ETH.sol";

import "./tToken.sol";
// import "./RewardUtil";

contract BoostETH is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Config {
        address treasury;
        uint256 gmxV2EthPercent;
        uint256 stargateEthPercent;
        uint256 performanceFee;
    }

    struct Addresses {
        // address rewardUtil;
        address tTokenContract;
        address wethTokenAddress;
        address gmxV2EthVaultAddress;
        address stargateEthVaultAddress;
    }

    Config public config;
    Addresses public addresses;
    IWETH public wethToken;
    tToken public tTokenContract;
    GMXV2ETH public gmxV2EthVault;
    StargateETH public stargateEthVault;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event EtherSwept(address indexed treasury, uint256 amount);
    event TokensSwept(address indexed token, address indexed treasury, uint256 amount);
    event AllocationUpdated(uint256 redactedTORQPercent, uint256 uniswapTORQPercent);
    event PerformanceFeesDistributed(address indexed treasury, uint256 amount);
    event FeesCompounded();

    constructor(
        address _wethTokenAddress,
        address _tTokenContract,
        address _gmxV2EthVaultAddress,
        address _stargateEthVaultAddress,
        address _treasury,
        // address _rewardUtil
    ) {
        wethToken = IWETH(_wethTokenAddress);
        tTokenContract = tToken(_tTokenContract);
        gmxV2EthVault = GMXV2ETH(_gmxV2EthVaultAddress);
        stargateEthVault = StargateETH(_stargateEthVaultAddress);
        addresses.treasury = _treasury;
        // addresses.rewardUtil = _rewardUtil;
        config.gmxV2EthPercent = 50;
        config.stargateEthPercent = 50;
        config.performanceFee = 1000; // 10% performance fee
    }

    function deposit() external payable nonReentrant {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        wethToken.deposit{value: msg.value}();
        uint256 half = msg.value.div(2);
        wethToken.approve(address(gmxV2EthVault), half);
        gmxV2EthVault.deposit(half);
        wethToken.approve(address(stargateEthVault), half);
        stargateEthVault.deposit(half);
        tTokenContract.mint(msg.sender, msg.value);
        emit Deposited(msg.sender, msg.value, msg.value);
    }

    function withdraw(uint256 tTokenAmount) external nonReentrant {
        require(tTokenAmount > 0, "Withdraw amount must be greater than zero");
        require(tTokenContract.balanceOf(msg.sender) >= tTokenAmount, "Insufficient tToken balance");
        uint256 ethAmount = calculateEthAmount(tTokenAmount);
        require(ethAmount <= address(this).balance, "Insufficient ETH balance in contract");
        gmxV2EthVault.withdraw(tTokenAmount.div(2));
        stargateEthVault.withdraw(tTokenAmount.div(2));
        tTokenContract.burn(msg.sender, tTokenAmount);
        wethToken.withdraw(ethAmount);
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");
        emit Withdrawn(msg.sender, tTokenAmount, ethAmount);
    }

    function calculateEthAmount(uint256 tTokenAmount) public view returns (uint256) {
        uint256 totalSupply = tTokenContract.totalSupply();
        if (totalSupply == 0) return 0;
        uint256 ethBalance = address(this).balance;
        return tTokenAmount.mul(ethBalance).div(totalSupply);
    }

    // Other functions

    receive() external payable {}
}
