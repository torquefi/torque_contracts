// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./../interfaces/IGMX.sol";
import "../interfaces/IGMXExchangeRouter.sol";
import "../utils/GMXOracle.sol";

contract GMXV2BTC is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public wbtcGMX;
    IERC20 public gmToken;
    IERC20 public usdcToken;
    IERC20 public arbToken;

    address marketAddress;
    address depositVault;
    address withdrawalVault;
    address router;

    uint256 public depositedBTCAmount = 0;
    uint256 public executionFee; 
    uint256 minUSDCAmount = 0;

    uint24 feeAmt = 500;
    uint256 minARBAmount = 1000000000000000000;
    
    IGMXExchangeRouter public immutable gmxExchange;
    ISwapRouter public immutable swapRouter;

    mapping (address => uint256) public usdcAmount;
    mapping (address => uint256) public wbtcAmount;

    address dataStore = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
    IChainlinkOracle chainlinkOracle = IChainlinkOracle(0xb6C62D5EB1F572351CC66540d043EF53c4Cd2239);
    ISyntheticReader syntheticReader = ISyntheticReader(0xf60becbba223EEA9495Da3f606753867eC10d139);
    GMXOracle gmxOracle;
    
    address private constant UNISWAP_V3_ROUTER = 0x2f5e87C9312fa29aed5c179E456625D79015299c;
    bytes32 public constant MAX_PNL_FACTOR_FOR_WITHDRAWALS = keccak256(abi.encode("MAX_PNL_FACTOR_FOR_WITHDRAWALS"));

    constructor(
        address _wbtc,
        address gmToken_, 
        address usdcToken_, 
        address arbToken_, 
        address payable exchangeRouter_, 
        address swapRouter_, 
        address depositVault_, 
        address withdrawalVault_, 
        address router_) Ownable(msg.sender) {
            wbtcGMX = IERC20(_wbtc);
            gmToken = IERC20(gmToken_);
            usdcToken = IERC20(usdcToken_);
            arbToken = IERC20(arbToken_);
            gmxExchange = IGMXExchangeRouter(exchangeRouter_);
            swapRouter = ISwapRouter(swapRouter_);
            depositVault = depositVault_;
            withdrawalVault = withdrawalVault_;
            router = router_;
            executionFee = 1000000000000000;
            gmxOracle = new GMXOracle(dataStore, syntheticReader,  chainlinkOracle);
    }

    function deposit(uint256 _amount) external payable {
        require(msg.value >= executionFee, "You must pay GMX v2 execution fee");
        gmxExchange.sendWnt{value: executionFee}(address(depositVault), executionFee);
        wbtcGMX.transferFrom(msg.sender, address(this), _amount);
        wbtcGMX.approve(address(router), _amount);
        gmxExchange.sendTokens(address(wbtcGMX), address(depositVault), _amount);
        IGMXExchangeRouter.CreateDepositParams memory depositParams = createDepositParams();
        gmxExchange.createDeposit(depositParams);
        depositedBTCAmount = depositedBTCAmount + _amount;
    }

    function withdraw(uint256 _amount, address _userAddress) external payable onlyOwner() {
        require(msg.value >= executionFee, "You must pay GMX v2 execution fee");
        gmxExchange.sendWnt{value: executionFee}(address(withdrawalVault), executionFee);
        uint256 gmAmountWithdraw = _amount * gmToken.balanceOf(address(this)) / depositedBTCAmount;
        gmToken.approve(address(router), gmAmountWithdraw);
        gmxExchange.sendTokens(address(gmToken), address(withdrawalVault), gmAmountWithdraw);
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams = createWithdrawParams();
        gmxExchange.createWithdrawal(withdrawParams);
        depositedBTCAmount = depositedBTCAmount - _amount;
        (uint256 wbtcWithdraw, uint256 usdcWithdraw) = calculateGMPrice(gmAmountWithdraw);
        usdcAmount[_userAddress] += usdcWithdraw;
        wbtcAmount[_userAddress] += wbtcWithdraw;
    }

    // slippage is 0.1% for input 1
    // slippage is 1% for input 10
    function withdrawAmount(uint16 _slippage) external returns (uint256) {
        require(_slippage < 1000, "Slippage cant be 1000");
        usdcAmount[msg.sender] = usdcAmount[msg.sender].mul(1000-_slippage).div(1000);
        wbtcAmount[msg.sender] = wbtcAmount[msg.sender].mul(1000-_slippage).div(1000);
        uint256 usdcAmountBalance = usdcToken.balanceOf(address(this));
        uint256 wbtcAmountBefore = wbtcGMX.balanceOf(address(this));
        require(usdcAmount[msg.sender] <= usdcAmountBalance, "Insufficient Funds, Execute Withdrawal not proceesed");
        require(wbtcAmount[msg.sender] <= wbtcAmountBefore, "Insufficient Funds, Execute Withdrawal not proceesed");
        if(usdcAmountBalance >= usdcAmount[msg.sender]){
            swapUSDCtoWBTC(usdcAmount[msg.sender]);
        }
        usdcAmount[msg.sender] = 0;
        uint256 wbtcAmountAfter = wbtcGMX.balanceOf(address(this));
        uint256 _wbtcAmount = wbtcAmount[msg.sender] + wbtcAmountAfter - wbtcAmountBefore;
        require(_wbtcAmount <= wbtcAmountAfter, "Not enough balance");
        wbtcAmount[msg.sender] = 0;
        wbtcGMX.transfer(msg.sender, _wbtcAmount);
        return _wbtcAmount;
    }

    function compound() external onlyOwner() {
        uint256 arbAmount = arbToken.balanceOf(address(this));
        if(arbAmount > minARBAmount){
            swapARBtoBTC(arbAmount);
            uint256 wbtcVal = wbtcGMX.balanceOf(address(this));
            wbtcGMX.transfer(msg.sender, wbtcVal);
        }
    }

    function _sendWnt(address _receiver, uint256 _amount) private {
        gmxExchange.sendWnt(_receiver, _amount);
    }

    function _sendTokens(address _token, address _receiver, uint256 _amount) private {
        gmxExchange.sendTokens(_token, _receiver, _amount);
    }

    function createDepositParams() internal view returns (IGMXExchangeRouter.CreateDepositParams memory) {
        IGMXExchangeRouter.CreateDepositParams memory depositParams;
        depositParams.callbackContract = address(this);
        depositParams.callbackGasLimit = 0;
        depositParams.executionFee = executionFee;
        depositParams.initialLongToken = address(wbtcGMX);
        depositParams.initialShortToken = address(usdcToken);
        depositParams.market = marketAddress;
        depositParams.shouldUnwrapNativeToken = false;
        depositParams.receiver = address(this);
        depositParams.minMarketTokens = 0;
        return depositParams;
    }

    function createWithdrawParams() internal view returns (IGMXExchangeRouter.CreateWithdrawalParams memory) {
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.callbackContract = address(this);
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = executionFee;
        withdrawParams.market = marketAddress;
        withdrawParams.shouldUnwrapNativeToken = false;
        withdrawParams.receiver = address(this);
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        return withdrawParams;
    }

    function swapUSDCtoWBTC(uint256 usdcVal) internal {
        usdcToken.approve(address(swapRouter), usdcVal);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdcToken),
                tokenOut: address(wbtcGMX),
                fee: feeAmt, 
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: usdcVal,
                amountOutMinimum: 99,
                sqrtPriceLimitX96: 0
            });

        swapRouter.exactInputSingle(params);
    }

    function updateExecutionFee(uint256 _executionFee) public onlyOwner{
        executionFee = _executionFee;
    }

    function updateFee(uint24 fee) external onlyOwner {
        feeAmt = fee;
    }

    function swapARBtoBTC(uint256 arbAmount) internal returns (uint256 amountOut){
        arbToken.approve(address(swapRouter), arbAmount);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(arbToken),
                tokenOut: address(wbtcGMX),
                fee: feeAmt,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: arbAmount,
                amountOutMinimum:0,
                sqrtPriceLimitX96: 0
            });
        return swapRouter.exactInputSingle(params);
    }

    function calculateGMPrice(uint256 gmAmountWithdraw) view public returns (uint256, uint256) {
        (,ISyntheticReader.MarketPoolValueInfoProps memory marketPoolValueInfo) = gmxOracle.getMarketTokenInfo(
            address(gmToken),
            address(usdcToken),
            address(wbtcGMX),
            address(usdcToken),
            MAX_PNL_FACTOR_FOR_WITHDRAWALS,
            false
            );
        uint256 totalGMSupply = gmToken.totalSupply(); 
        uint256 adjustedSupply = getAdjustedSupply(marketPoolValueInfo.longTokenUsd , marketPoolValueInfo.shortTokenUsd , marketPoolValueInfo.totalBorrowingFees, marketPoolValueInfo.netPnl, marketPoolValueInfo.impactPoolAmount);
        return getBtcNUsdcAmount(gmAmountWithdraw, adjustedSupply.div(totalGMSupply), marketPoolValueInfo.longTokenUsd.div(100), marketPoolValueInfo.shortTokenUsd, marketPoolValueInfo.longTokenUsd.div(marketPoolValueInfo.longTokenAmount), marketPoolValueInfo.shortTokenUsd.div(marketPoolValueInfo.shortTokenAmount));
    }

    function getBtcNUsdcAmount(uint256 gmxWithdraw, uint256 price, uint256 wbtcVal, uint256 usdcVal, uint256 wbtcPrice, uint256 usdcPrice) internal pure returns (uint256, uint256) {
        uint256 wbtcAmountUSD = gmxWithdraw.mul(price).div(10e5).mul(wbtcVal);
        wbtcAmountUSD = wbtcAmountUSD.div(wbtcVal.add(usdcVal));

        uint256 usdcAmountUSD = gmxWithdraw.mul(price).div(10e5).mul(usdcVal);
        usdcAmountUSD = usdcAmountUSD.div(wbtcVal.add(usdcVal));
        return(wbtcAmountUSD.mul(10e8).div(wbtcPrice), usdcAmountUSD.mul(10e6).div(usdcPrice));
    }

    function getAdjustedSupply(uint256 wbtcPool, uint256 usdcPool, uint256 totalBorrowingFees, int256 pnl, uint256 impactPoolPrice) pure internal returns (uint256) {
        wbtcPool = wbtcPool.div(10e2);
        usdcPool = usdcPool.div(10);
        totalBorrowingFees = totalBorrowingFees.div(10e6);
        impactPoolPrice = impactPoolPrice.mul(10e6);
        uint256 newPNL;
        if(pnl>0){
            newPNL = uint256(pnl);
            newPNL = newPNL.div(10e12);
            return wbtcPool + usdcPool - totalBorrowingFees - newPNL - impactPoolPrice;
        }
        else{
            newPNL = uint256(-pnl);
            newPNL = newPNL.div(10e12);
            return wbtcPool + usdcPool - totalBorrowingFees + newPNL - impactPoolPrice;
        }
    }

    receive() external payable{}
}

// PS CHECK
// struct MarketPoolValueInfoProps {
//     int256 poolValue; 30297859937182975781353382593557078314
//     int256 longPnl; -30256194486684016933915089809167659866
//     int256 shortPnl; 57958940031103509964560000000000
//     int256 netPnl; -30256136527743985830405125249167659866

//     uint256 longTokenAmount; 177282026099
//     uint256 shortTokenAmount; 72438845087601
//     uint256 longTokenUsd; 7621624829125607562252570000000000
//     uint256 shortTokenUsd; 72448675038879387455700000000000

//     uint256 totalBorrowingFees; 54014820524637842323983133951457854
//     uint256 borrowingFeePoolFactor; 630000000000000000000000000000n

//     uint256 impactPoolAmount; 995561279n
//   }117473871830231827571983404