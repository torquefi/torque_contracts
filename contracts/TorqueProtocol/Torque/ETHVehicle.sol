pragma solidity ^0.8.0;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./interfaces/IStargateLPStaking.sol";
import "./interfaces/ISwapRouterV3.sol";
import "./interfaces/IGMX.sol";
// import IChildVault.sol interface

// @dev This is a basic setup of the ETHVehicle which handles child-vault routing.

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract ETHVehicle is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    
    // Variables and mapping
    IStargateLPStaking lpStaking;
    IERC20 public stargateInterface;
    ISwapRouterV3 public swapRouter;
    IGMX public gmxInterface;
    address constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    address public Stargate;
    uint256 constant DENOMINATOR = 10000;
    
    address[] public childVaultAddresses;
    mapping(address => bool) public isChildVault;
    mapping(address => bool) public allowedTokens;
    mapping(address => uint256) public totalStack;

    // Structs and events
    struct VehicleInfo {
        uint256 amount;
        uint256 amountToSTG;
        uint256 amountFromGMX;
        uint256 lastProcess;
    }

    event PidSet(address indexed token, uint256 indexed pid);
    event VehicleDeposited(address indexed user, uint256 amount);
    event VehicleWithdrawn(address indexed user, uint256 amount);

    constructor (
        address _stargateStakingAddress,
        address _stargateAddress,
        address _swapRouter,
        address _gmxAddress,
    ) {
        lpStaking = IStargateLPStaking(_stargateStakingAddress);
        stargateInterface = IERC20(_stargateAddress);
        swapRouter = ISwapRouterV3(_swapRouter);
        gmxInterface = IGMX(_gmxAddress);
    }

    function addAllowedToken(address tokenAddress) public onlyOwner {
        allowedTokens[tokenAddress] = true;
    }

    function removeAllowedToken(address tokenAddress) public onlyOwner {
        allowedTokens[tokenAddress] = false;
    }

    // Function to add a new child vault
    function addChildVault(address vault) external onlyOwner {
        require(!isChildVault[vault], "Vault is already added");
        isChildVault[vault] = true;
        childVaultAddresses.push(vault);
    }

    // Function to remove a child vault
    function removeChildVault(address vault) external onlyOwner {
        require(isChildVault[vault], "Vault not found");
        isChildVault[vault] = false;
        uint256 index;
        for (uint256 i = 0; i < childVaultAddresses.length; i++) {
            if (childVaultAddresses[i] == vault) {
                index = i;
                break;
            }
        }

        // Swap the vault to remove with the last vault in array
        childVaultAddresses[index] = childVaultAddresses[childVaultAddresses.length - 1];

        // Reduce the size of the array by one
        childVaultAddresses.pop();
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
        emit PidSet(_token, _pid);
    }

    function handleWETH(uint256 amount) external nonReentrant {
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

        emit VehicleDeposited(_msgSender(), _amount);
    }
    
    function withdrawalFromVaults(uint256 amount) external nonReentrant {
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

        emit VehicleWithdrawn(_msgSender(), _amount);
    }
}