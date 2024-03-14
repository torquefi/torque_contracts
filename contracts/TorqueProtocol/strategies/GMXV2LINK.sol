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
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "../interfaces/IGMXExchangeRouter.sol";
import "../utils/GMXOracle.sol";

contract GMXV2LINK is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public linkToken;
    IERC20 public gmToken;
    IERC20 public usdcToken;
    IERC20 public arbToken;

    address marketAddress = 0x7f1fa204bb700853D36994DA19F830b6Ad18455C;
    address depositVault;
    address withdrawalVault;
    address router;
    address controller;

    uint256 public depositedLinkAmount = 0;
    uint256 minUSDCAmount = 0;

    uint24 feeAmt = 500;
    uint256 minARBAmount = 1000000000000000000;
    
    IGMXExchangeRouter public immutable gmxExchange;
    ISwapRouter public immutable swapRouter;

    mapping (address => uint256) public usdcAmount;
    mapping (address => uint256) public linkAmount;

    address public treasury = 0x0f773B3d518d0885DbF0ae304D87a718F68EEED5;

    address dataStore = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
    IChainlinkOracle chainlinkOracle = IChainlinkOracle(0xb6C62D5EB1F572351CC66540d043EF53c4Cd2239);
    ISyntheticReader syntheticReader = ISyntheticReader(0xf60becbba223EEA9495Da3f606753867eC10d139);
    GMXOracle gmxOracle;
    
    bytes32 public constant MAX_PNL_FACTOR_FOR_WITHDRAWALS = keccak256(abi.encode("MAX_PNL_FACTOR_FOR_WITHDRAWALS"));

    constructor(
        address linkToken_,
        address gmToken_, 
        address usdcToken_, 
        address arbToken_, 
        address payable exchangeRouter_, 
        address swapRouter_, 
        address depositVault_, 
        address withdrawalVault_, 
        address router_) {
            linkToken = IERC20(linkToken_);
            gmToken = IERC20(gmToken_);
            usdcToken = IERC20(usdcToken_);
            arbToken = IERC20(arbToken_);
            gmxExchange = IGMXExchangeRouter(exchangeRouter_);
            swapRouter = ISwapRouter(swapRouter_);
            depositVault = depositVault_;
            withdrawalVault = withdrawalVault_;
            router = router_;
            gmxOracle = new GMXOracle(dataStore, syntheticReader,  chainlinkOracle);
    }

    function deposit(uint256 _amount) external payable {
        require(msg.sender == controller, "Only controller can call this!");
        gmxExchange.sendWnt{value: msg.value}(address(depositVault), msg.value);
        require(linkToken.transferFrom(msg.sender, address(this), _amount), "Transfer Asset Failed");
        linkToken.approve(address(router), _amount);
        gmxExchange.sendTokens(address(linkToken), address(depositVault), _amount);
        IGMXExchangeRouter.CreateDepositParams memory depositParams = createDepositParams();
        gmxExchange.createDeposit(depositParams);
        depositedLinkAmount = depositedLinkAmount + _amount;
    }

    function withdraw(uint256 _amount, address _userAddress) external payable {
        require(msg.sender == controller, "Only controller can call this!");
        gmxExchange.sendWnt{value: msg.value}(address(withdrawalVault), msg.value);
        uint256 gmAmountWithdraw = _amount * gmToken.balanceOf(address(this)) / depositedLinkAmount;
        gmToken.approve(address(router), gmAmountWithdraw);
        gmxExchange.sendTokens(address(gmToken), address(withdrawalVault), gmAmountWithdraw);
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams = createWithdrawParams();
        gmxExchange.createWithdrawal(withdrawParams);
        depositedLinkAmount = depositedLinkAmount - _amount;
        (uint256 linkWithdraw, uint256 usdcWithdraw) = calculateGMPrice(gmAmountWithdraw);
        usdcAmount[_userAddress] += usdcWithdraw;
        linkAmount[_userAddress] += linkWithdraw;
    }

    // slippage is 0.1% for input 1
    // slippage is 1% for input 10
    function withdrawAmount(uint16 _slippage) external returns (uint256) {
        require(_slippage < 1000, "Slippage cant be 1000");
        usdcAmount[msg.sender] = usdcAmount[msg.sender].mul(1000-_slippage).div(1000);
        linkAmount[msg.sender] = linkAmount[msg.sender].mul(1000-_slippage).div(1000);
        uint256 usdcAmountBalance = usdcToken.balanceOf(address(this));
        uint256 linkAmountBefore = linkToken.balanceOf(address(this));
        require(usdcAmount[msg.sender] <= usdcAmountBalance, "Insufficient Funds, Execute Withdrawal not proceesed");
        require(linkAmount[msg.sender] <= linkAmountBefore, "Insufficient Funds, Execute Withdrawal not proceesed");
        if(usdcAmountBalance >= usdcAmount[msg.sender]){
            swapUSDCtoLINK(usdcAmount[msg.sender]);
        }
        usdcAmount[msg.sender] = 0;
        uint256 linkAmountAfter = linkToken.balanceOf(address(this));
        uint256 _linkAmount = linkAmount[msg.sender] + linkAmountAfter - linkAmountBefore;
        require(_linkAmount <= linkAmountAfter, "Not enough balance");
        linkAmount[msg.sender] = 0;
        require(linkToken.transfer(msg.sender, _linkAmount), "Transfer Asset Failed");
        return _linkAmount;
    }

    function compound() external {
        require(msg.sender == controller, "Only controller can call this!");
        uint256 arbAmount = arbToken.balanceOf(address(this));
        if(arbAmount > minARBAmount){
            uint256 linkVal = swapARBtoLINK(arbAmount);
            require(linkToken.transfer(msg.sender, linkVal), "Transfer Asset Failed");
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
        depositParams.executionFee = msg.value;
        depositParams.initialLongToken = address(linkToken);
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
        withdrawParams.executionFee = msg.value;
        withdrawParams.market = marketAddress;
        withdrawParams.shouldUnwrapNativeToken = false;
        withdrawParams.receiver = address(this);
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        return withdrawParams;
    }

    function swapUSDCtoLINK(uint256 usdcVal) internal {
        usdcToken.approve(address(swapRouter), usdcVal);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdcToken),
                tokenOut: address(linkToken),
                fee: feeAmt, 
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: usdcVal,
                amountOutMinimum: 99,
                sqrtPriceLimitX96: 0
            });

        swapRouter.exactInputSingle(params);
    }

    function updateFee(uint24 fee) external onlyOwner {
        feeAmt = fee;
    }

    function withdrawTreasuryFees() external onlyOwner() {
        payable(treasury).transfer(address(this).balance);
    }

    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function swapARBtoLINK(uint256 arbAmount) internal returns (uint256 amountOut){
        arbToken.approve(address(swapRouter), arbAmount);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(arbToken),
                tokenOut: address(linkToken),
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
            address(linkToken),
            address(usdcToken),
            MAX_PNL_FACTOR_FOR_WITHDRAWALS,
            false
            );
        uint256 totalGMSupply = gmToken.totalSupply(); 
        uint256 adjustedSupply = getAdjustedSupply(marketPoolValueInfo.longTokenUsd , marketPoolValueInfo.shortTokenUsd , marketPoolValueInfo.totalBorrowingFees, marketPoolValueInfo.netPnl, marketPoolValueInfo.impactPoolAmount);
        return getLinkNUsdcAmount(gmAmountWithdraw, adjustedSupply.div(totalGMSupply), marketPoolValueInfo.longTokenUsd.div(100), marketPoolValueInfo.shortTokenUsd, marketPoolValueInfo.longTokenUsd.div(marketPoolValueInfo.longTokenAmount), marketPoolValueInfo.shortTokenUsd.div(marketPoolValueInfo.shortTokenAmount));
    }

    function getLinkNUsdcAmount(uint256 gmxWithdraw, uint256 price, uint256 linkVal, uint256 usdcVal, uint256 linkPrice, uint256 usdcPrice) internal pure returns (uint256, uint256) {
        uint256 linkAmountUSD = gmxWithdraw.mul(price).div(10e5).mul(linkVal);
        linkAmountUSD = linkAmountUSD.div(linkVal.add(usdcVal));

        uint256 usdcAmountUSD = gmxWithdraw.mul(price).div(10e5).mul(usdcVal);
        usdcAmountUSD = usdcAmountUSD.div(linkVal.add(usdcVal));
        return(linkAmountUSD.mul(10e8).div(linkPrice), usdcAmountUSD.mul(10e6).div(usdcPrice));
    }

    function getAdjustedSupply(uint256 linkPool, uint256 usdcPool, uint256 totalBorrowingFees, int256 pnl, uint256 impactPoolPrice) pure internal returns (uint256) {
        linkPool = linkPool.div(10e2);
        usdcPool = usdcPool.div(10);
        totalBorrowingFees = totalBorrowingFees.div(10e6);
        impactPoolPrice = impactPoolPrice.mul(10e6);
        uint256 newPNL;
        if(pnl>0){
            newPNL = uint256(pnl);
            newPNL = newPNL.div(10e12);
            return linkPool + usdcPool - totalBorrowingFees - newPNL - impactPoolPrice;
        }
        else{
            newPNL = uint256(-pnl);
            newPNL = newPNL.div(10e12);
            return linkPool + usdcPool - totalBorrowingFees + newPNL - impactPoolPrice;
        }
    }

    function setController(address _controller) external onlyOwner() {
        controller = _controller;
    }

    receive() external payable{}
}
