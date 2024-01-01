// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./../interfaces/ISwapRouterV3.sol";
import "./../interfaces/IStargateLPStaking.sol";

contract StargateETH is Ownable, ReentrancyGuard {
    IERC20 public immutable wethSTG;
    IStargateLPStaking lpStaking;

    mapping(address => uint256) public addressToPid;

    constructor(address _weth, address _stargateStakingAddress) {
        wethSTG = IERC20(_weth);
        lpStaking = IStargateLPStaking(_stargateStakingAddress);
    }

    function _deposit(address _token, uint256 _amount) internal payable {
        uint256 pid = addressToPid[_token];
        wethSTG.safeTransferFrom(msg.sender, address(this), _amount);
        wethSTG.approve(address(lpStaking), _amount);
        lpStaking.deposit(pid, _amount);
    }

    function _withdraw(address _token, uint256 _amount) internal {
        uint256 pid = addressToPid[_token];
        lpStaking.withdraw(pid, _amount);
        wethSTG.safeTransfer(msg.sender, _amount);
    }

    function setPid(address _token, uint256 _pid) public onlyOwner {
        addressToPid[_token] = _pid;
    }
}
