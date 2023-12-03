// SPDX-License-Identifier: MIT

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//      \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//       \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//        \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//         \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|
//

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../interfaces/IExchangeRouter.sol";

contract TestGMXV2 is Ownable {
    IERC20 public wethGMX;
    IERC20 public gmToken;
    IERC20 public usdcToken;
    address marketAddress;
    // IERC20 public immutable
    address depositVault;
    address withdrawalVault;
    IExchangeRouter public immutable gmxExchange;

    constructor(
        address _weth,
        address _gmxExchange,
        address _gmToken,
        address _usdcToken,
        address _depositVault,
        address _withdrawalVault
    ) {
        wethGMX = IERC20(_weth);
        gmxExchange = IExchangeRouter(_gmxExchange);
        gmToken = IERC20(_gmToken);
        usdcToken = IERC20(_usdcToken);
        depositVault = _depositVault;
        withdrawalVault = _withdrawalVault;
    }

    function depositGMX(uint256 _amount) public payable onlyOwner returns (uint256 gmTokenAmount) {
        gmxExchange.sendWnt(depositVault, _amount);
        IExchangeRouter.CreateDepositParams memory params = createDepositParams();
        wethGMX.transferFrom(msg.sender, address(this), _amount);
        wethGMX.approve(depositVault, _amount);
        gmxExchange.createDeposit{ value: _amount }(params);
        gmTokenAmount = gmToken.balanceOf(address(this));
    }

    function _withdrawGMX(
        uint256 _amount
    ) public payable onlyOwner returns (uint256 wethAmount, uint256 usdcAmount) {
        gmxExchange.sendTokens(address(gmToken), withdrawalVault, _amount);
        IExchangeRouter.CreateWithdrawalParams memory params = createWithdrawParams();
        gmToken.transferFrom(msg.sender, address(this), _amount);
        gmToken.approve(withdrawalVault, _amount);
        gmxExchange.createWithdrawal(params);
        wethGMX.transfer(msg.sender, _amount);
        wethAmount = wethGMX.balanceOf(address(this));
        usdcAmount = usdcToken.balanceOf(address(this));
    }

    function createDepositParams()
        internal
        view
        returns (IExchangeRouter.CreateDepositParams memory)
    {
        IExchangeRouter.CreateDepositParams memory depositParams;
        depositParams.callbackContract = address(this);
        depositParams.callbackGasLimit = 0;
        depositParams.executionFee = 0;
        depositParams.initialLongToken = address(wethGMX);
        depositParams.initialShortToken = address(usdcToken);
        depositParams.market = marketAddress;
        depositParams.shouldUnwrapNativeToken = true;
        depositParams.receiver = address(this);
        depositParams.minMarketTokens = 0;

        return depositParams;
    }

    function createWithdrawParams()
        internal
        view
        returns (IExchangeRouter.CreateWithdrawalParams memory)
    {
        IExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.callbackContract = address(this);
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = 0;
        // withdrawParams.initialLongToken = address(weth);
        // withdrawParams.initialShortToken = address(usdcToken);
        withdrawParams.market = marketAddress;
        withdrawParams.shouldUnwrapNativeToken = true;
        withdrawParams.receiver = address(this);
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;

        return withdrawParams;
    }
}
