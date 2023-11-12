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
import "./../interfaces/IGMXV2ETH.sol";

// @dev I imported all GMX interfaces that should be needed to be implemented.

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "./../vToken.sol";

contract GMXV2ETH is ERC4626, Ownable, ReentrancyGuard, IGMXV2ETH {
    using SafeERC20 for IERC20;

    IERC20 public immutable weth;
    IERC20 public immutable gmToken;
    IERC20 public immutable usdcToken;
    address marketAddress;
    // IERC20 public immutable 
    address booster;
    address depositVault;
    address withdrawalVault;
    IExchangeRouter public immutable gmxExchange;
    vToken public immutable vTokenInstance;


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

    function _depositGMX(
        uint256 _amount
    ) external payable nonReentrant returns(uint256 gmTokenAmount) {
        CreateDepositParams params memory = createDepositParams(_amount);
        usdcToken.safeTransferFrom(msg.sender, address(this), params.initialLongToken);
        usdcToken.approve(depositVault, params.initialLongToken);
        weth.safeTransferFrom(msg.sender, address(this), params.initialShortToken);
        weth.approve(depositVault, params.initialShortToken);
        gmxExchange.createDeposit(params);
        vTokenInstance.mint(msg.sender, _amount);
        gmTokenAmount = gmToken.balanceOf(address(this));
        gmToken.transfer(booster, gmTokenAmount);
    }

    function _withdrawGMX(uint256 _amount) external payable nonReentrant returns(uint256 wethAmount, uint256 usdcAmount) {
        CreateWithdrawalParams params = createWithdrawParams(_amount);
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

    function createDepositParams(uint256 _amount) internal returns(CreateDepositParams) {
        CreateDepositParams depositParams memory;
        depositParams.callbackContract = address(this);
        depositParams.callbackGasLimit = 0;
        depositParams.executionFee = 0;
        depositParams.initialLongToken = address(weth);
        depositParams.initialShortToken = address(usdcToken);
        depositParams.market = marketAddress;
        depositParams.shouldUnwrapNativeToken = true;
        depositParams.receiver = address(this);
        depositParams.minMarketTokens = 0;

        return depositParams;
    }

    function createWithdrawParams(uint256 _amount) internal returns(CreateWithdrawalParams) {
        CreateWithdrawalParams withdrawParams memory;
        withdrawParams.callbackContract = address(this);
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = 0;
        withdrawParams.initialLongToken = address(weth);
        withdrawParams.initialShortToken = address(usdcToken);
        withdrawParams.market = marketAddress;
        withdrawParams.shouldUnwrapNativeToken = true;
        withdrawParams.receiver = address(this);
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;

        return depositParams;
    }
}
