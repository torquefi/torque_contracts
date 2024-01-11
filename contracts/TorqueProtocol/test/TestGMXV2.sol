// SPDX-License-Identifier: MIT

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//      \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//       \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//        \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//         \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|
//

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../interfaces/IExchangeRouter.sol";

contract TestGMXV2 is Ownable {
    IERC20 public wethGMX;
    IERC20 public gmToken;
    IERC20 public usdcToken;
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
        gmxExchange.sendWnt{ value: _amount }(depositVault, _amount);
        IExchangeRouter.CreateDepositParams memory params = createDepositParams();
        gmxExchange.createDeposit(params);
        gmTokenAmount = gmToken.balanceOf(address(this));
        gmToken.transfer(msg.sender, gmTokenAmount);
    }

    function withdrawGMX(
        uint256 _amount
    ) public payable onlyOwner returns (uint256 ethAmount, uint256 usdcAmount) {
        gmToken.transferFrom(msg.sender, address(this), _amount);
        gmToken.approve(withdrawalVault, _amount);
        gmxExchange.sendTokens(address(gmToken), withdrawalVault, _amount);
        IExchangeRouter.CreateWithdrawalParams memory params = createWithdrawParams();
        gmxExchange.createWithdrawal(params);
        ethAmount = address(this).balance;
        usdcAmount = usdcToken.balanceOf(address(this));
        (bool success, ) = msg.sender.call{ value: ethAmount }("");
        require(success, "Transfer native token failed");
        usdcToken.transfer(msg.sender, usdcAmount);
    }

    function createDepositParams()
        internal
        view
        returns (IExchangeRouter.CreateDepositParams memory)
    {
        IExchangeRouter.CreateDepositParams memory depositParams;
        depositParams.receiver = address(this);
        depositParams.market = address(gmToken);
        depositParams.initialLongToken = address(wethGMX);
        depositParams.initialShortToken = address(usdcToken);
        depositParams.minMarketTokens = 0;
        depositParams.shouldUnwrapNativeToken = true;
        depositParams.executionFee = 0; // Should check the execution fee later
        depositParams.callbackGasLimit = 0;

        return depositParams;
    }

    function createWithdrawParams()
        internal
        view
        returns (IExchangeRouter.CreateWithdrawalParams memory)
    {
        IExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.receiver = address(this);
        withdrawParams.market = address(gmToken);
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        withdrawParams.shouldUnwrapNativeToken = true;
        withdrawParams.executionFee = 0; // Should check the execution fee later
        withdrawParams.callbackGasLimit = 0;

        return withdrawParams;
    }
}
