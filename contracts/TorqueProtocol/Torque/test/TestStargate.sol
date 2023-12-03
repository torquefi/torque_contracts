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

interface IRouterETH {
    function addLiquidityETH() external payable;
}

interface IRouter {
    function instantRedeemLocal(
        uint16 _srcPoolId,
        uint256 _amountLP,
        address _to
    ) external returns (uint256 amountSD);
}

contract TestStargate is Ownable {
    address iRouterETH;
    address iRouter;
    address WETH;

    constructor(address _iRouterETH, address _iRouter, address _WETH) {
        iRouter = _iRouter;
        iRouterETH = _iRouterETH;
        WETH = _WETH;
    }

    function setAddress(address _iRouterETH, address _iRouter, address _WETH) public onlyOwner {
        iRouter = _iRouter;
        iRouterETH = _iRouterETH;
        WETH = _WETH;
    }

    function depositStargate(address _token, uint256 _amount) public payable onlyOwner {
        if (_token == WETH) {
            IRouterETH routerETH = IRouterETH(iRouterETH);
            routerETH.addLiquidityETH{ value: _amount }();
        }
    }

    function withdrawStargate(address _token, uint256 _amount) public onlyOwner {
        if (_token == WETH) {
            uint16 srcPoolID = 13;
            IRouter router = IRouter(iRouter);
            router.instantRedeemLocal(srcPoolID, _amount, msg.sender);
        }
    }
}
