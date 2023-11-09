pragma solidity ^0.8.0;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./../interfaces/IGMX.sol";
import "./../interfaces/IExchangeRouter.sol";
// import "./..interfaces/IDeposit.sol";
// import "./..interfaces/IDepositCallback.sol";
// import "./..interfaces/IDepositHandler.sol";
// import "./..interfaces/IEvent.sol";
// import "./..interfaces/IRouter.sol";
import "./..interfaces/IWETH.sol";
import "./..interfaces/IWithdraw.sol";
import "./..interfaces/IWithdrawCallback.sol";

// @dev I imported all GMX interfaces that should be needed to be implemented.

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "./../vToken.sol";

contract GMXV2ETH is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable weth;
    IERC20 public immutable gmToken;
    IERC20 public immutable usdcToken;
    IERC20 public immutable 
    address booster;
    address depositVault;
    address withdrawalVault;
    IExchangeRouter public immutable gmxExchange;
    vToken public immutable vTokenInstance;

    struct CreateDepositParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minMarketTokens;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    struct CreateWithdrawalParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 marketTokenAmount;
        uint256 minLongTokenAmount;
        uint256 minShortTokenAmount;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    constructor(
        IERC20 _weth, 
        IGMX _gmxExchange, 
        address vTokenAddress, 
        address _gmToken, 
        address _usdcToken, 
        address _booster, 
        address _depositVault, 
        address _withdrawalVault
    ) {
        weth = _weth;
        gmxExchange = _gmxExchange;
        vTokenInstance = vToken(vTokenAddress);
        gmToken = _gmToken;
        usdcToken = _usdcToken;
        booster = _booster;
        depositVault = _depositVault;
        withdrawalVault = _withdrawalVault;
    }

    function updateBooster(address _booster) public onlyOwner {
        booster = _booster;
    }

    function deposit(
        WithdrawalUtils.CreateWithdrawalParams calldata params
    ) external payable nonReentrant returns(uint256 gmTokenAmount) {
        usdcToken.safeTransferFrom(msg.sender, address(this), params.initialLongToken);
        usdcToken.approve(depositVault, params.initialLongToken);
        weth.safeTransferFrom(msg.sender, address(this), params.initialShortToken);
        weth.approve(depositVault, params.initialShortToken);
        gmxExchange.createDeposit(params);
        vTokenInstance.mint(msg.sender, _amount);
        gmTokenAmount = gmToken.balanceOf(address(this));
        gmToken.transfer(booster, gmTokenAmount);
    }

    function withdraw(CreateWithdrawalParams calldata params) external nonReentrant returns(uint256 wethAmount, uint256 usdcAmount) {
        gmToken.safeTransferFrom(msg.sender, address(this), params.marketTokenAmount);
        gmToken.approve(withdrawalVault, params.marketTokenAmount);
        gmxExchange.createWithdrawal(params);
        weth.safeTransfer(msg.sender, _amount);
        vTokenInstance.burn(msg.sender, _amount);
        wethAmount = weth.balanceOf(address(this));
        usdcAmount = usdcToken.balanceOf(address(this));
        weth.transfer(booster, wethAmount);
        usdcToken.transfer(booster, usdcAmount);
    }

    function sendWnt() public {}

    function sendTokens() public {}
}
