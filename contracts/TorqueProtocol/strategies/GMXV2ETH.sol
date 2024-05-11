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
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ISwapRouter.sol";
import "../interfaces/IGMXExchangeRouter.sol";
import "../interfaces/IWETH9.sol";
import "../utils/GMXOracle.sol";

contract GMXV2ETH is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWETH9 public weth;
    IERC20 public gmToken;
    IERC20 public usdcToken;
    IERC20 public arbToken;

    address public marketAddress = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
    address depositVault;
    address withdrawalVault;
    address router;

    IGMXExchangeRouter public exchangeRouter;
    ISwapRouter public swapRouter;

    uint256 public depositedWethAmount;
    uint256 minUSDCAmount = 0;
    uint256 minARBAmount = 1000000000000000000;
    uint24 feeAmt = 500;
    address controller;

    address public treasury = 0x0f773B3d518d0885DbF0ae304D87a718F68EEED5;
    mapping (address => uint256) public usdcAmount;
    mapping (address => uint256) public wethAmount;
    
    bytes32 public constant MAX_PNL_FACTOR_FOR_WITHDRAWALS = keccak256(abi.encode("MAX_PNL_FACTOR_FOR_WITHDRAWALS"));

    address dataStore = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
    IChainlinkOracle chainlinkOracle = IChainlinkOracle(0xb6C62D5EB1F572351CC66540d043EF53c4Cd2239);
    ISyntheticReader syntheticReader = ISyntheticReader(0xf60becbba223EEA9495Da3f606753867eC10d139);

    GMXOracle gmxOracle;
    

    constructor(address payable weth_, address gmToken_, address usdcToken_, address arbToken_, address payable exchangeRouter_, address swapRouter_, address depositVault_, address withdrawalVault_, address router_) Ownable(msg.sender) {
        weth = IWETH9(weth_);
        gmToken = IERC20(gmToken_);
        usdcToken = IERC20(usdcToken_);
        arbToken = IERC20(arbToken_);
        exchangeRouter = IGMXExchangeRouter(exchangeRouter_);
        swapRouter = ISwapRouter(swapRouter_);
        depositVault = depositVault_;
        withdrawalVault = withdrawalVault_;
        router = router_;
        depositedWethAmount = 0;
        gmxOracle = new GMXOracle(dataStore, syntheticReader,  chainlinkOracle);
    }

    function deposit(uint256 _amount) external payable{
        require(msg.sender == controller, "Only Controller can call this");
        require(msg.value > 0, "You must pay GMX v2 execution fee");
        exchangeRouter.sendWnt{value: msg.value}(address(depositVault), msg.value);
        require(weth.transferFrom(msg.sender, address(this), _amount), "Transfer Asset Failed");
        weth.approve(address(router), _amount);
        exchangeRouter.sendTokens(address(weth), address(depositVault), _amount);
        IGMXExchangeRouter.CreateDepositParams memory depositParams = createDepositParams();
        exchangeRouter.createDeposit(depositParams);
        depositedWethAmount = depositedWethAmount + _amount;
    }

    function withdraw(uint256 _amount, address _userAddress) external payable {
        require(msg.sender == controller, "Only Controller can call this");
        require(msg.value > 0, "You must pay GMX V2 execution fee");
        exchangeRouter.sendWnt{value: msg.value}(address(withdrawalVault), msg.value);
        uint256 gmAmountWithdraw = _amount * gmToken.balanceOf(address(this)) / depositedWethAmount;
        gmToken.approve(address(router), gmAmountWithdraw);
        exchangeRouter.sendTokens(address(gmToken), address(withdrawalVault), gmAmountWithdraw);
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams = createWithdrawParams();
        exchangeRouter.createWithdrawal(withdrawParams);
        depositedWethAmount = depositedWethAmount - _amount;
        (uint256 wethWithdraw, uint256 usdcWithdraw) = calculateGMPrice(gmAmountWithdraw);
        usdcAmount[_userAddress] += usdcWithdraw;
        wethAmount[_userAddress] += wethWithdraw;
    }

    /** 
        @notice Slippage for input 1 is 0.1% & Slippage for input 10 is 1% 
    */
    function withdrawAmount(uint16 _slippage) external returns (uint256) {
        require(_slippage < 1000, "Slippage cant be 1000");
        usdcAmount[msg.sender] = usdcAmount[msg.sender].mul(1000-_slippage).div(1000);
        wethAmount[msg.sender] = wethAmount[msg.sender].mul(1000-_slippage).div(1000);
        uint256 usdcAmountBalance = usdcToken.balanceOf(address(this));
        uint256 wethAmountBefore = weth.balanceOf(address(this));
        require(usdcAmount[msg.sender] <= usdcAmountBalance, "Insufficient Funds, Execute Withdrawal not proceesed");
        require(wethAmount[msg.sender] <= wethAmountBefore, "Insufficient Funds, Execute Withdrawal not proceesed");
        if(usdcAmountBalance >= usdcAmount[msg.sender]){
            swapUSDCtoWETH(usdcAmount[msg.sender]);
        }
        usdcAmount[msg.sender] = 0;
        uint256 wethAmountAfter = weth.balanceOf(address(this));
        uint256 _wethAmount = wethAmount[msg.sender] + wethAmountAfter - wethAmountBefore;
        require(_wethAmount <= wethAmountAfter, "Not enough balance");
        wethAmount[msg.sender] = 0;
        require(weth.transfer(msg.sender, _wethAmount), "Transfer Asset Failed");
        return _wethAmount;
    }

    function withdrawTreasuryFees() external onlyOwner() {
        payable(treasury).transfer(address(this).balance);
    }

    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function compound() external {
        require(msg.sender == controller, "Only Controller can call this");
        uint256 arbAmount = arbToken.balanceOf(address(this));
        if(arbAmount > minARBAmount){
            uint256 wethVal = swapARBtoWETH(arbAmount);
            require(weth.transfer(msg.sender, wethVal), "Transfer Asset Failed");
        }
    }

    function setController(address _controller) external onlyOwner() {
        controller = _controller;
    }

    function swapUSDCtoWETH(uint256 usdcVal) internal {
        usdcToken.approve(address(swapRouter), usdcVal);
        ISwapRouter.ExactInputSingleParams memory params =  
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdcToken),
                tokenOut: address(weth),
                fee: feeAmt,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: usdcVal,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        swapRouter.exactInputSingle(params);
    }

    function swapARBtoWETH(uint256 arbAmount) internal returns (uint256 amountOut){
        arbToken.approve(address(swapRouter), arbAmount);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(arbToken),
                tokenOut: address(weth),
                fee: feeAmt,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: arbAmount,
                amountOutMinimum:0,
                sqrtPriceLimitX96: 0
            });
        return swapRouter.exactInputSingle(params);
    }

    function createDepositParams() internal view returns (IGMXExchangeRouter.CreateDepositParams memory) {
        IGMXExchangeRouter.CreateDepositParams memory depositParams;
        depositParams.receiver = address(this);
        depositParams.callbackContract = address(this);
        depositParams.market = marketAddress;
        depositParams.minMarketTokens = 0;
        depositParams.shouldUnwrapNativeToken = false;
        depositParams.executionFee = msg.value;
        depositParams.callbackGasLimit = 0;
        depositParams.initialLongToken = address(weth);
        depositParams.initialShortToken = address(usdcToken);
        return depositParams;
    }

    function createWithdrawParams() internal view returns (IGMXExchangeRouter.CreateWithdrawalParams memory) {
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.receiver = address(this);
        withdrawParams.callbackContract = address(this);
        withdrawParams.market = marketAddress;
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = msg.value;
        withdrawParams.shouldUnwrapNativeToken = false;
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        return withdrawParams;
    }

    function updateFee(uint24 fee) external onlyOwner {
        feeAmt = fee;
    }

    function calculateGMPrice(uint256 gmAmountWithdraw) view public returns (uint256, uint256) {
        (,ISyntheticReader.MarketPoolValueInfoProps memory marketPoolValueInfo) = gmxOracle.getMarketTokenInfo(
            address(gmToken),
            address(usdcToken),
            address(weth),
            address(usdcToken),
            MAX_PNL_FACTOR_FOR_WITHDRAWALS,
            false
            );
        uint256 totalGMSupply = gmToken.totalSupply();
        uint256 adjustedSupply = getAdjustedSupply(marketPoolValueInfo.longTokenUsd , marketPoolValueInfo.shortTokenUsd , marketPoolValueInfo.totalBorrowingFees, marketPoolValueInfo.netPnl, marketPoolValueInfo.impactPoolAmount);
        return getEthNUsdcAmount(gmAmountWithdraw, adjustedSupply.div(totalGMSupply), marketPoolValueInfo.longTokenUsd.div(10e11), marketPoolValueInfo.shortTokenUsd, marketPoolValueInfo.longTokenUsd.div(marketPoolValueInfo.longTokenAmount), marketPoolValueInfo.shortTokenUsd.div(marketPoolValueInfo.shortTokenAmount));
    }

    function getEthNUsdcAmount(uint256 gmxWithdraw, uint256 price, uint256 wethVal, uint256 usdcVal, uint256 wethPrice, uint256 usdcPrice) public pure returns (uint256, uint256) {
        uint256 wethAmountUSD = gmxWithdraw.mul(price).div(10e6).mul(wethVal);
        wethAmountUSD = wethAmountUSD.div(wethVal.add(usdcVal));

        uint256 usdcAmountUSD = gmxWithdraw.mul(price).div(10e6).mul(usdcVal);
        usdcAmountUSD = usdcAmountUSD.div(wethVal.add(usdcVal));
        return(wethAmountUSD.mul(10e19).div(wethPrice), usdcAmountUSD.mul(10e7).div(usdcPrice));
    }

    function getAdjustedSupply(uint256 wethPool, uint256 usdcPool, uint256 totalBorrowingFees, int256 pnl, uint256 impactPoolPrice) pure internal returns(uint256 adjustedSupply) {
        wethPool = wethPool.div(10e12);
        usdcPool = usdcPool.div(10);
        totalBorrowingFees = totalBorrowingFees.div(10e6);
        impactPoolPrice = impactPoolPrice.mul(10e6);
        uint256 newPNL;
        if(pnl>0){
            newPNL = uint256(pnl);
        }
        else{
            newPNL = uint256(-pnl);
        }
        newPNL = newPNL.div(10e12);
        return wethPool + usdcPool - totalBorrowingFees - newPNL - impactPoolPrice;
    }

    function transferToken(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        require(IERC20(_tokenAddress).transfer(_to,_amount));
    }

    receive() external payable{}
}
