// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface RadiantLendingPool {
    function repay(
		address asset,
		uint256 amount,
		uint256 rateMode,
		address onBehalfOf
	) external returns (uint256);
}

interface RadiantWETHGateway {
    function withdrawETH(address lendingPool, uint256 amount, address to) external;
}

interface IWETH {
    function deposit() external payable;
}

contract RadiantWethRefinanceUSDC is Ownable {

    RadiantLendingPool radiantLendingPool = RadiantLendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);
    RadiantWETHGateway radiantWETHGateway = RadiantWETHGateway(0x534D4851616B364d3643978433C6715Ec9aA15c0);
    address assetUsdc = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address assetUsdce = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address assetRWeth = address(0x0dF5dfd95966753f01cb80E76dc20EA958238C46);
    address assetWETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    uint256 rateMode = 2;

    constructor() Ownable(msg.sender) {}
    
    function torqRefinanceUSDC(uint256 usdcAmount, uint256 rWethAmount) external {
        depositUSDC(usdcAmount);
        withdrawETH(rWethAmount);
    }

    function torqRefinanceUSDCe(uint256 usdcAmount, uint256 rWethAmount) external {
        depositUSDCe(usdcAmount);
        withdrawETH(rWethAmount);
    }

    function depositUSDC(uint256 usdcAmount) public {
        IERC20(assetUsdc).transferFrom(msg.sender, address(this), usdcAmount);
        IERC20(assetUsdc).approve(address(radiantLendingPool), usdcAmount);
        radiantLendingPool.repay(assetUsdc, usdcAmount, rateMode, msg.sender);
    }

    function depositUSDCe(uint256 usdcAmount) public {
        IERC20(assetUsdce).transferFrom(msg.sender, address(this), usdcAmount);
        IERC20(assetUsdce).approve(address(radiantLendingPool), usdcAmount);
        radiantLendingPool.repay(assetUsdce, usdcAmount, rateMode, msg.sender);
    }

    function withdrawETH(uint256 rWethAmount) public {
        IERC20(assetRWeth).transferFrom(msg.sender, address(this), rWethAmount);
        IERC20(assetRWeth).approve(address(radiantWETHGateway), rWethAmount);

        bytes memory withdrawData = abi.encodeWithSignature("withdrawETH(address,uint256,address)", address(radiantLendingPool), rWethAmount, address(this));
        (bool success, ) = address(radiantWETHGateway).call(withdrawData);
        require(success, "Delegate call failed");

        wrapEther(rWethAmount);
        require(IERC20(assetWETH).transfer(msg.sender, rWethAmount), "Transfer Asset Failed");
    }

    function withdraw(uint256 _amount, address _asset) external onlyOwner {
        require(IERC20(_asset).transfer(msg.sender, _amount), "Transfer Asset Failed");
    }

    function withdraw() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        payable(owner()).transfer(contractBalance);
    }

    function updateRLendingPool(address _address) external onlyOwner {
        radiantLendingPool = RadiantLendingPool(_address);
    }

    function updateRateMode(uint256 _rateMode) external onlyOwner {
        rateMode = _rateMode;
    }

    function wrapEther(uint256 _ethAmount) public payable {
        IWETH(assetWETH).deposit{value: _ethAmount}();
    }

    receive() external payable {}

}