// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "../interfaces/IStargateLPStaking.sol";
import "../interfaces/ISwapRouterV3.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IGMX.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BoostETH is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    // variables and mapping
    IStargateLPStaking lpStaking;
    IERC20 public stargateInterface;
    ISwapRouterV3 public swapRouter;
    IGMX public gmxInterface;
    address constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address public Stargate;
    mapping(address => uint256) public totalStack;
    address treasuryWallet;
    uint256 treasuryProportion;
    uint256 constant DENOMINATOR = 10000;
    // address[] public stakeHolders;

    mapping(address => mapping(uint256 => UserInfo)) public userInfo;
    mapping(address => mapping(uint256 => bool)) public isStakeHolder;
    mapping(uint256 => address[]) public stakeHolders;
    mapping(address => uint256) public addressToPid;

    // structs and events
    struct UserInfo {
        uint256 amount;
        uint256 amountToSTG;
        uint256 amountFromGMX;
        uint256 lastProcess;
    }

    // constructor and functions
    constructor(
        address _stargateStakingAddress,
        address _stargateAddress,
        address _swapRouter,
        address _gmxAddress,
        address _treasuryWallet,
        uint256 _treasuryProportion
    ) {
        lpStaking = IStargateLPStaking(_stargateStakingAddress);
        stargateInterface = IERC20(_stargateAddress);
        swapRouter = ISwapRouterV3(_swapRouter);
        gmxInterface = IGMX(_gmxAddress);
        treasuryWallet = _treasuryWallet;
        treasuryProportion = _treasuryProportion;
    }

    function changeConfigAddress(
        address _stargateStakingAddress,
        address _stargateAddress,
        address _swapRouter
    ) public onlyOwner {
        lpStaking = IStargateLPStaking(_stargateStakingAddress);
        stargateInterface = IERC20(_stargateAddress);
        swapRouter = ISwapRouterV3(_swapRouter);
    }

    function setPid(address _token, uint256 _pid) public onlyOwner {
        addressToPid[_token] = _pid;
    }

    function deposit(address _token, uint256 _amount) public payable nonReentrant {
        uint256 pid = addressToPid[_token];
        IERC20 tokenInterface = IERC20(_token);
        if (_token == WETH) {
            require(msg.value >= _amount, "Not enough ETH");
            IWETH weth = IWETH(WETH);
            weth.deposit{ value: _amount / 2 }();
        } else {
            tokenInterface.transferFrom(_msgSender(), address(this), _amount);
        }
        tokenInterface.approve(address(lpStaking), _amount / 2);
        // tokenInterface.approve(address(gmxInterface), _amount / 2);
        lpStaking.deposit(pid, _amount);
        uint256 gmTokenAmount = gmxInterface.createDeposit{ value: _amount / 2 }(_amount / 2);

        UserInfo storage _userInfo = userInfo[_msgSender()][pid];
        if (_userInfo.lastProcess == 0) {
            address[] storage stakes = stakeHolders[pid];
            stakes.push(_msgSender());
        }
        _userInfo.amount = _userInfo.amount.add(_amount);
        _userInfo.amountToSTG = _userInfo.amountToSTG.add(_amount / 2);
        _userInfo.amountFromGMX = _userInfo.amountFromGMX.add(gmTokenAmount);
        _userInfo.lastProcess = block.timestamp;
        totalStack[_token] = totalStack[_token].add(_amount);
    }

    function withdraw(address _token, uint256 _amount) public payable nonReentrant {
        uint256 pid = addressToPid[_token];
        UserInfo storage _userInfo = userInfo[_msgSender()][pid];
        uint256 currentAmount = _userInfo.amount;
        _userInfo.amount = currentAmount.sub(_amount);
        uint256 amountFromSTG = _userInfo.amountToSTG.mul(_amount).div(currentAmount);
        uint256 amountToGMX = _userInfo.amountFromGMX.mul(_amount).div(currentAmount);
        _userInfo.lastProcess = block.timestamp;
        totalStack[_token] = totalStack[_token].sub(_amount);

        IERC20 tokenInterface = IERC20(_token);
        lpStaking.withdraw(pid, amountFromSTG);
        uint256 tokenFromGMX = gmxInterface.createWithdrawal(amountToGMX);
        uint256 totalTokenReturn = tokenFromGMX + amountFromSTG;
        if (_token == WETH) {
            IWETH weth = IWETH(WETH);
            weth.withdraw(amountFromSTG);
            (bool success, ) = msg.sender.call{ value: totalTokenReturn }("");
            require(success, "Transfer ETH failed");
        } else {
            tokenInterface.transfer(_msgSender(), _amount);
        }
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
    }

    // internal functions
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
    }

    function updateTreasuryProportion(uint256 _treasuryProportion) public onlyOwner {
        require(_treasuryProportion < DENOMINATOR, "Invalid treasury proportion");
        treasuryProportion = _treasuryProportion;
    }

    // For testing purposes only
    function swapETHToSTG() public payable {
        IWETH weth = IWETH(WETH);
        uint256 _amount = msg.value;
        weth.deposit{ value: _amount }();
        IERC20 tokenInterface = IERC20(WETH);
        tokenInterface.approve(address(swapRouter), _amount);
        ISwapRouterV3.ExactInputSingleParams memory params = ISwapRouterV3.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: address(stargateInterface),
            fee: 10000,
            recipient: msg.sender,
            deadline: block.timestamp + 1000000,
            amountIn: _amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        swapRouter.exactInputSingle(params);
    }
}