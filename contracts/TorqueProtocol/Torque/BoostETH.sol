// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

// @dev This is a basic setup of the top-level Boost ETH contract
// which handles compounding, rebalancing, and distribution
// to vehicle for further child-vault distribution.

// @dev We should model BoostUSD off of this once the 6 related
// BoostETH contracts are complete (BoostETH.sol, ETHVehicle.sol,
// GMXV2ETH.sol, StargateETH.sol, TorqueETH.sol, and vToken.sol).

import "./interfaces/IWETH.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./ETHVehicle.sol"; // Deposits and withdraws routed through ETHVehicle
import "./TorqueETH.sol"; // Need to implement mint and burn tETH logic

// import "./RewardUtil"; // Need to implement reward distribution setup

contract BoostETH is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Variables and mapping
    ETHVehicle public ethVehicle;
    address treasuryWallet;
    uint256 treasuryProportion;
    address constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    address[] stakeHolders;

    mapping(address => mapping(uint256 => UserInfo)) public userInfo;
    mapping(address => mapping(uint256 => bool)) public isStakeHolder;
    mapping(uint256 => address[]) public stakeHolders;
    mapping(address => uint256) public addressToPid;
    mapping(address => uint256) public userBalances;

    // Structs and events
    struct UserInfo {
        uint256 amount;
    }

    event TreasuryUpdated(address indexed newTreasuryWallet);
    event UserDeposited(address indexed user, uint256 amount);
    event UserWithdrawn(address indexed user, uint256 amount);
    event UserAutoCompounded(address indexed user, uint256 amount);

    constructor(address _ethVehicleAddress, address _treasuryWallet, uint256 _treasuryProportion) {
        ethVehicle = ETHVehicle(_ethVehicleAddress);
        treasuryWallet = _treasuryWallet;
        treasuryProportion = _treasuryProportion;
    }

    function deposit(uint256 _amount, bool _useETH) public payable nonReentrant {
        require(_amount > 0, "Cannot deposit 0");
        address user = msg.sender;
        updateUserInfo(user);

        if (_useETH) {
            require(msg.value == _amount, "ETH value mismatch");
            // Convert ETH to WETH
            IWETH(WETH).deposit{ value: _amount }();
        } else {
            require(msg.value == 0, "Should not send ETH");
            // Transfer WETH from user to this contract
            IERC20(WETH).transferFrom(user, address(this), _amount);
        }

        // Convert ETH to WETH
        IWETH(WETH).deposit{ value: _amount }();

        // Transfer WETH to ETHVehicle for further distribution
        IERC20(WETH).safeTransfer(address(ethVehicle), _amount);

        // Notify ETHVehicle to distribute the WETH to child vaults
        ethVehicle.handleWETH(_amount);

        // Update the user's balance in the mapping
        userBalances[msg.sender] = userBalances[msg.sender].add(_amount);

        // Emit an event to notify deposit has occurred
        emit UserDeposited(msg.sender, _amount);
    }

    function withdraw(address _token, uint256 _amount) public nonReentrant {
        require(_amount > 0, "Cannot withdraw 0");
        require(userBalances[msg.sender] >= _amount, "Insufficient balance");

        // Step 1: Trigger ETHVehicle to withdraw from child vaults
        ethVehicle.withdrawFromVaults(_token, _amount);

        // Step 2: Update the user balance
        userBalances[msg.sender] = userBalances[msg.sender].sub(_amount);

        // Step 3: Distribute assets to end user after receiving from ETHVehicle
        if (_token == WETH) {
            IWETH(WETH).withdraw(_amount);
            (bool success, ) = msg.sender.call{ value: _amount }("");
            require(success, "Transfer ETH failed");
        } else {
            IERC20(_token).transfer(msg.sender, _amount);
        }

        emit UserWithdrawn(msg.sender, _amount);
    }

    function autoCompound(address _token) public nonReentrant {
        IERC20 tokenInterface = IERC20(_token);
        uint256 pid = addressToPid[_token];
        uint256 totalProduction = calculateTotalProduct(pid);
        lpStaking.withdraw(pid, totalStack[_token]);
        uint256 rewardSTG = stargateInterface.balanceOf(address(this));
        if (rewardSTG > 0) {
            uint256 tokenReward = swapRewardSTGToToken(_token, rewardSTG);
            uint256 treasuryReserved = tokenReward.mul(treasuryProportion).div(DENOMINATOR);
            uint256 remainReward = tokenReward.sub(treasuryReserved);
            tokenInterface.transfer(treasuryWallet, treasuryReserved);
            address[] memory stakes = stakeHolders[pid];
            for (uint256 i = 0; i < stakes.length; i++) {
                UserInfo storage _userInfo = userInfo[stakes[i]][pid];
                uint256 userProduct = calculateUserProduct(pid, stakes[i]);
                uint256 reward = remainReward.mul(userProduct).div(totalProduction);
                _userInfo.amount = _userInfo.amount.add(reward);
            }
            totalStack[_token] = totalStack[_token].add(remainReward);
            tokenInterface.approve(address(lpStaking), totalStack[_token]);
            lpStaking.deposit(pid, totalStack[_token]);
        }

        emit UserAutoCompounded(msg.sender, totalStack[_token]);
    }

    // Internal functions
    function calculateTotalProduct(uint256 _pid) internal view returns (uint256) {
        address[] memory stakes = stakeHolders[_pid];
        uint256 totalProduct = 0;
        for (uint256 i = 0; i < stakes.length; i++) {
            uint256 userProduct = calculateUserProduct(_pid, stakes[i]);
            totalProduct = totalProduct.add(userProduct);
        }
        return totalProduct;
    }

    function calculateUserProduct(uint256 _pid, address _staker) internal view returns (uint256) {
        UserInfo memory _userInfo = userInfo[_staker][_pid];
        uint256 interval = block.timestamp.sub(_userInfo.lastProcess);
        return interval.mul(_userInfo.amount);
    }

    function swapRewardSTGToToken(
        address _token,
        uint256 _stgAmount
    ) internal returns (uint256 amountOut) {
        stargateInterface.approve(address(swapRouter), _stgAmount);
        ISwapRouterV3.ExactInputSingleParams memory params = ISwapRouterV3.ExactInputSingleParams({
            tokenIn: address(stargateInterface),
            tokenOut: _token,
            fee: 10000,
            recipient: address(this),
            deadline: block.timestamp + 1000000,
            amountIn: _stgAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        amountOut = swapRouter.exactInputSingle(params);
    }

    function updateTreasury(address _treasuryWallet) public onlyOwner {
        treasuryWallet = _treasuryWallet;
        emit TreasuryUpdated(_treasuryWallet);
    }

    function updateTreasuryProportion(uint256 _treasuryProportion) public onlyOwner {
        require(_treasuryProportion < DENOMINATOR, "Invalid treasury proportion");
        treasuryProportion = _treasuryProportion;
    }

    receive() external payable {}
}
