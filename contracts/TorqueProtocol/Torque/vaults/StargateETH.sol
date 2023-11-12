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

import "./vToken.sol";

contract StargateETH is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable weth;
    IStargateLPStaking lpStaking;

    mapping(address => uint256) public addressToPid;

    constructor(IERC20 _weth, IStargate _stargatePool, address _stargateStakingAddress,) {
        weth = _weth;
       lpStaking = IStargateLPStaking(_stargateStakingAddress);
    }

    function setPid(address _token, uint256 _pid) public onlyOwner {
        addressToPid[_token] = _pid;
    }

    function _depositStargate(address _token, uint256 _amount) external nonReentrant {
        uint256 pid = addressToPid[_token];
        weth.safeTransferFrom(msg.sender, address(this), _amount);
        weth.approve(address(stargatePool), _amount);
       lpStaking.deposit(pid, _amount);
    }

    function _withdrawStargate(address _token, uint256 _amount) external nonReentrant {
        uint256 pid = addressToPid[_token];
        weth.safeTransfer(msg.sender, _amount);
        lpStaking.withdraw(pid, _amount);
    }
}
