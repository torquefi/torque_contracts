// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "../interfaces/ISwapRouterV3.sol";
import "./../interfaces/IStargateLPStaking.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./../vToken.sol";

contract StargateETH is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable wethSTG;
    IStargateLPStaking lpStaking;

    mapping(address => uint256) public addressToPid;

    constructor(address _weth, address _stargateStakingAddress) {
        wethSTG = IERC20(_weth);
        lpStaking = IStargateLPStaking(_stargateStakingAddress);
    }

    function setPid(address _token, uint256 _pid) public onlyOwner {
        addressToPid[_token] = _pid;
    }

    function _depositStargate(address _token, uint256 _amount) external nonReentrant {
        uint256 pid = addressToPid[_token];
        wethSTG.safeTransferFrom(msg.sender, address(this), _amount);
        wethSTG.approve(address(lpStaking), _amount);
        lpStaking.deposit(pid, _amount);
    }

    function _withdrawStargate(address _token, uint256 _amount) external nonReentrant {
        uint256 pid = addressToPid[_token];
        wethSTG.safeTransfer(msg.sender, _amount);
        lpStaking.withdraw(pid, _amount);
    }
}
