// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

// @dev This contract should be refactored and comply like BoostETH.

import "../interfaces/IStargateLPStaking.sol";
import "../interfaces/ISwapRouterV3.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IGMX.sol";
import "../interfaces/INonfungiblePositionManager.sol";
import "../interfaces/IComet.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BoostUSD is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    
    // Variables and mapping
    ISwapRouterV3 public swapRouter;
    INonfungiblePositionManager public nonfungiblePositionManager;
    IComet public comet;
    IGMX public gmxInterface;
    address constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    uint256 public totalStack;
    uint256 public totalLiquidity;
    uint256 public totalUSDCToCompound;
    address treasuryWallet;
    IERC20 public usdToken;
    IERC20 public usdcToken;
    uint256 treasuryProportion;
    uint256 constant DENOMINATOR = 10000;
    uint256 tokenID;
    // address[] public stakeHolders;

    mapping(address => UserInfo) public userInfo;
    mapping(address => mapping(uint256 => bool)) public isStakeHolder;
    address[] public stakeHolders;

    // Structs and events
    struct UserInfo {
        uint256 amount;
        uint256 amountToCompound;
        uint256 uniswapLiquidity;
        uint256 lastProcess;
    }

    // Constructor and functions
    constructor(
        address _swapRouter,
        address _treasuryWallet,
        uint256 _treasuryProportion,
        address _usdAddress,
        address _usdcAddress,
        address _nonfungiblePositionManager,
        address _comet
    ) {
        swapRouter = ISwapRouterV3(_swapRouter);
        treasuryWallet = _treasuryWallet;
        treasuryProportion = _treasuryProportion;
        usdToken = IERC20(_usdAddress);
        usdcToken = IERC20(_usdcAddress);
        nonfungiblePositionManager = INonfungiblePositionManager(nonfungiblePositionManager);
        comet = IComet(_comet);
    }

    function changeConfigAddress(address _swapRouter) public onlyOwner {
        swapRouter = ISwapRouterV3(_swapRouter);
    }

    function deposit(address _token, uint256 _amount) public payable nonReentrant {
        UserInfo storage _userInfo = userInfo[_msgSender()];
        IERC20 tokenInterface = IERC20(_token);
        tokenInterface.transferFrom(_msgSender(), address(this), _amount);
        uint256 usdToConvert = _amount.mul(3).div(4);
        usdToken.approve(usdToConvert, address(swapRouter));

        ISwapRouterV3.ExactInputSingleParams memory params = ISwapRouterV3.ExactInputSingleParams({
            tokenIn: address(usdToken),
            tokenOut: address(usdcToken),
            fee: 10000,
            recipient: address(this),
            deadline: block.timestamp + 1000000,
            amountIn: usdToConvert,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        uint256 usdcAmount = swapRouter.exactInputSingle(params);
        usdToken.approve(_amount.div(4), address(nonfungiblePositionManager));
        usdcToken.approve(usdcAmount, address(nonfungiblePositionManager));

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory addLiquidityParams = nonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenID,
                amount0Desired: _amount.div(4),
                amount1Desired: usdcAmount,
                amount0Min: _amount.div(4),
                amount1Min: 0,
                deadline: block.timestamp
            });

        (uint256 liquidity, uint256 amount0, uint256 amount1) = nonfungiblePositionManager
            .increaseLiquidity(addLiquidityParams);

        uint256 remainUSDCAmount = usdcToken.balanceOf(address(this));
        usdcToken.approve(remainUSDCAmount, address(comet));
        comet.supply(address(usdcToken), remainUSDCAmount);

        if (_userInfo.lastProcess == 0) {
            address[] storage stakes = stakeHolders;
            stakes.push(_msgSender());
        }
        _userInfo.amount = _userInfo.amount.add(_amount);
        _userInfo.uniswapLiquidity = _userInfo.uniswapLiquidity.add(liquidity);
        _userInfo.amountToCompound = _userInfo.amountToCompound.add(remainUSDCAmount);
        _userInfo.lastProcess = block.timestamp;
        totalStack = totalStack.add(_amount);
        totalLiquidity = totalLiquidity.add(liquidity);
        totalUSDCToCompound = totalUSDCToCompound.add(remainUSDCAmount);
    }

    function withdraw(address _token, uint256 _amount) public payable nonReentrant {
        UserInfo storage _userInfo = userInfo[_msgSender()];
        uint256 currentAmount = _userInfo.amount;
        _userInfo.amount = currentAmount.sub(_amount);
        uint256 liquidityToUniswap = _userInfo.uniswapLiquidity.mul(_amount).div(currentAmount);
        uint256 usdcFromCompound = _userInfo.amountToCompound.mul(_amount).div(currentAmount);
        _userInfo.lastProcess = block.timestamp;
        totalStack = totalStack.sub(_amount);

        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = nonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenID,
                liquidity: liquidityToUniswap,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        nonfungiblePositionManager.decreaseLiquidity(params);
        totalLiquidity = totalLiquidity.sub(liquidityToUniswap);
        totalUSDCToCompound = totalUSDCToCompound.sub(usdcFromCompound);
        comet.withdraw(address(usdcToken), usdcFromCompound);
        uint256 usdAmountReturn = usdToken.balanceOf(address(this));
        uint256 usdcAmountReturn = usdcToken.balanceOf(address(this));
        usdToken.transfer(_msgSender(), usdAmountReturn);
        usdcToken.transfer(_msgSender(), usdcAmountReturn);
    }

    function autoCompound(address _token) public nonReentrant {
        uint256 totalProduction = calculateTotalProduct();
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = nonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenID,
                liquidity: totalLiquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        nonfungiblePositionManager.decreaseLiquidity(params);
        comet.withdraw(address(usdcToken), totalUSDCToCompound);
        uint256 currentUSDAmount = usdToken.balanceOf(address(this));
        uint256 currentUSDCAmount = usdcToken.balanceOf(address(this));
        uint256 totalUSDAmount = totalStack.div(4);
        uint256 rewardUSD = 0;
        uint256 rewardUSDC = 0;
        if (currentUSDAmount > totalUSDAmount) {
            rewardUSD = currentUSDAmount - totalUSDAmount;
        }
        if (currentUSDCAmount > totalUSDCToCompound) {
            rewardUSDC = currentUSDCAmount - totalUSDCToCompound;
        }
        if (rewardUSD > 0) {
            usdToken.transfer(treasuryWallet, rewardUSD.mul(3).div(10));
        }
        if (rewardUSDC > 0) {
            usdcToken.transfer(treasuryWallet, rewardUSDC.mul(3).div(10));
        }
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
    function calculateTotalProduct() internal view returns (uint256) {
        address[] memory stakes = stakeHolders;
        uint256 totalProduct = 0;
        for (uint256 i = 0; i < stakes.length; i++) {
            uint256 userProduct = calculateUserProduct(stakes[i]);
            totalProduct = totalProduct.add(userProduct);
        }
        return totalProduct;
    }

    function calculateUserProduct(address _staker) internal view returns (uint256) {
        UserInfo memory _userInfo = userInfo[_staker];
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

    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata data
    ) external returns (bytes4);
}