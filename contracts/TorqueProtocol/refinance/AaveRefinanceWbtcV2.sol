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

interface AaveLendingPool {
    function repay(
		address asset,
		uint256 amount,
		uint256 rateMode,
		address onBehalfOf
	) external returns (uint256);

    function withdraw(
        address asset, 
        uint256 amount, 
        address to
    ) external returns (uint256);
}

interface WBTCBorrowFactoryV2 {
    function callBorrowRefinance(uint supplyAmount, uint borrowAmountUSDC, address userAddress) external; 
}

contract AaveWbtcRefinanceV2 is Ownable {

    event USDCDeposited(address indexed user, uint256 amount);
    event USDCeDeposited(address indexed user, uint256 amount);
    event WbtcWithdrawn(address indexed user, uint256 amount);
    event AavePoolUpdated(address indexed newAddress);
    event RateModeUpdated(uint256 newRateMode);
    event BorrowTorq(uint256 supplyAmount, uint borrowAmount, address user);
    event WBTCBorrowFactoryUpdated(address _borrowFactoryAddress);

    AaveLendingPool aaveLendingPool = AaveLendingPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    WBTCBorrowFactoryV2 borrowFactoryV2 = WBTCBorrowFactoryV2(0x9859C74a9CF69CCb9E328A8F508fc4Ba740A7504);
    address assetUsdc = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address assetUsdce = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address assetAaveWbtc = address(0x078f358208685046a11C85e8ad32895DED33A249);
    address assetWbtc = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    uint256 rateMode = 2;

    constructor() Ownable(msg.sender) {}
    
    function torqRefinanceUSDC(uint256 usdcAmount, uint256 rWbtcAmount) external {
        depositUSDC(usdcAmount);
        withdrawWBTC(rWbtcAmount);
        torqFinance(usdcAmount, rWbtcAmount);
    }

    function torqRefinanceUSDCe(uint256 usdcAmount, uint256 rWbtcAmount) external {
        depositUSDCe(usdcAmount);
        withdrawWBTC(rWbtcAmount);
        torqFinance(usdcAmount, rWbtcAmount);
    }

    function depositUSDC(uint256 usdcAmount) public {
        require(usdcAmount > 0, "USDC amount must be greater than 0");
        IERC20(assetUsdc).transferFrom(msg.sender, address(this), usdcAmount);
        IERC20(assetUsdc).approve(address(aaveLendingPool), usdcAmount);
        uint256 repaidAmount = aaveLendingPool.repay(assetUsdc, usdcAmount, rateMode, msg.sender);
        
        if(repaidAmount < usdcAmount) {
            uint256 differenceAmount = usdcAmount - repaidAmount;
            if(IERC20(assetUsdc).balanceOf(address(this)) >= differenceAmount) {
                IERC20(assetUsdc).transfer(msg.sender, differenceAmount);
            }
        }

        emit USDCDeposited(msg.sender, repaidAmount);
    }

    function depositUSDCe(uint256 usdceAmount) public {
        require(usdceAmount > 0, "USDCe amount must be greater than 0");
        IERC20(assetUsdce).transferFrom(msg.sender, address(this), usdceAmount);
        IERC20(assetUsdce).approve(address(aaveLendingPool), usdceAmount);
        uint256 repaidAmount = aaveLendingPool.repay(assetUsdce, usdceAmount, rateMode, msg.sender);

        if(repaidAmount < usdceAmount) {
            uint256 differenceAmount = usdceAmount - repaidAmount;
            if(IERC20(assetUsdce).balanceOf(address(this)) >= differenceAmount) {
                IERC20(assetUsdce).transfer(msg.sender, differenceAmount);
            }
        }

        emit USDCeDeposited(msg.sender, repaidAmount);
    }

    function withdrawWBTC(uint256 rWbtcAmount) internal {
        require(rWbtcAmount > 0, "rWETH amount must be greater than 0");
        IERC20(assetAaveWbtc).transferFrom(msg.sender, address(this), rWbtcAmount);
        IERC20(assetAaveWbtc).approve(address(aaveLendingPool), rWbtcAmount);
        aaveLendingPool.withdraw(assetWbtc, rWbtcAmount, address(this));

        emit WbtcWithdrawn(msg.sender, rWbtcAmount);
    }

    function torqFinance(uint256 usdcAmount, uint256 rWbtcAmount) internal {
        require(IERC20(assetWbtc).approve(address(borrowFactoryV2), rWbtcAmount), "Approve Asset Failed");
        borrowFactoryV2.callBorrowRefinance(rWbtcAmount, usdcAmount, msg.sender);

        emit BorrowTorq(rWbtcAmount, usdcAmount, msg.sender);
    }

    function withdraw(uint256 _amount, address _asset) external onlyOwner {
        IERC20(_asset).transfer(msg.sender, _amount);
    }

    function updateAaveLendingPool(address _address) external onlyOwner {
        require(_address != address(0), "Address cannot be zero");
        aaveLendingPool = AaveLendingPool(_address);

        emit AavePoolUpdated(_address);
    }

    function updateRateMode(uint256 _rateMode) external onlyOwner {
        rateMode = _rateMode;

        emit RateModeUpdated(_rateMode);
    }

    function updateBorrowFactoryV2(address _address) external onlyOwner {
        require(_address != address(0), "Address cannot be zero");
        borrowFactoryV2 = WBTCBorrowFactoryV2(_address);
        emit WBTCBorrowFactoryUpdated(_address);
    }

}
