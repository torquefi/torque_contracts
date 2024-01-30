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
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ISwapRouter.sol";
import "../interfaces/IGMXExchangeRouter.sol";
import "../interfaces/IWETH9.sol";
import "./GMXOracle.sol";

contract GMXV2ETH is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWETH9 public weth;
    IERC20 public gmToken;
    IERC20 public usdcToken;
    IERC20 public arbToken;

    address public marketAddress = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
    uint256 public executionFee; 
    address depositVault;
    address withdrawalVault;
    address router;

    IGMXExchangeRouter public exchangeRouter;
    ISwapRouter public swapRouter;

    uint256 public depositedWethAmount;
    uint256 minUSDCAmount = 0;
    uint256 minARBAmount = 1000000000000000000;

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
        executionFee = 1000000000000000;
        gmxOracle = new GMXOracle(dataStore, syntheticReader,  chainlinkOracle);
    }

    function deposit(uint256 _amount) external payable{
        require(msg.value >= executionFee, "You must pay GMX v2 execution fee");
        exchangeRouter.sendWnt{value: executionFee}(address(depositVault), executionFee);
        weth.transferFrom(msg.sender, address(this), _amount);
        weth.approve(address(router), _amount);
        exchangeRouter.sendTokens(address(weth), address(depositVault), _amount);
        IGMXExchangeRouter.CreateDepositParams memory depositParams = createDepositParams();
        exchangeRouter.createDeposit(depositParams);
        depositedWethAmount = depositedWethAmount + _amount;
    }

    function withdraw(uint256 _amount, address _userAddress) external payable onlyOwner() {
        require(msg.value >= executionFee, "You must pay GMX V2 execution fee");
        exchangeRouter.sendWnt{value: executionFee}(address(withdrawalVault), executionFee);
        uint256 gmAmountWithdraw = _amount * gmToken.balanceOf(address(this)) / depositedWethAmount;
        gmToken.approve(address(router), gmAmountWithdraw);
        exchangeRouter.sendTokens(address(gmToken), address(withdrawalVault), gmAmountWithdraw);
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams = createWithdrawParams();
        bytes32 withdrawalKey = exchangeRouter.createWithdrawal(withdrawParams);
        depositedWethAmount = depositedWethAmount - _amount;
        uint256 GMToUSDC = 0; // FIX
        uint256 GMToWETH = 0; // FIX
        // Calculate GM token market price
        // Calculate GM token to USDC
        // Calculate GM token to WETH
        usdcAmount[_userAddress] += GMToUSDC;
        wethAmount[_userAddress] += GMToWETH;
    }

    // slippage is 0.1% for input 1
    // slippage is 1% for input 10
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
        weth.transfer(msg.sender, _wethAmount);
        return _wethAmount;
    }

    function withdrawETH() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
    }

    // To be removed Temporary function
    function withdrawAllTempfunction() external {
        uint256 _weth = weth.balanceOf(address(this));
        uint256 _usdc = usdcToken.balanceOf(address(this));
        weth.transfer(msg.sender, _weth);
        usdcToken.transfer(msg.sender, _usdc);
        payable(msg.sender).transfer(address(this).balance);
    }

    function compound() external onlyOwner() {
        uint256 arbAmount = arbToken.balanceOf(address(this));
        if(arbAmount > minARBAmount){
            swapARBtoWETH(arbAmount);
            uint256 wethAmount = weth.balanceOf(address(this));
            weth.transfer(msg.sender, wethAmount);
        }
    }

    function swapUSDCtoWETH(uint256 usdcAmount) internal {
        usdcToken.approve(address(swapRouter), usdcAmount);
        ISwapRouter.ExactInputSingleParams memory params =  
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdcToken),
                tokenOut: address(weth),
                fee: 0, // Double check
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: usdcAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        swapRouter.exactInputSingle(params);
    }

    function updateExecutionFee(uint256 _executionFee) public onlyOwner{
        executionFee = _executionFee;
    }

    function swapARBtoWETH(uint256 arbAmount) internal returns (uint256 amountOut){
        arbToken.approve(address(swapRouter), arbAmount);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(arbToken),
                tokenOut: address(weth),
                fee: 0,
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
        depositParams.executionFee = executionFee;
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
        withdrawParams.executionFee = executionFee;
        withdrawParams.shouldUnwrapNativeToken = false;
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        return withdrawParams;
    }

    function calculateGMPrice() view public returns (int256) {
        (int256 marketTokenPrice, ISyntheticReader.MarketPoolValueInfoProps memory marketPoolValueInfo) = gmxOracle.getMarketTokenInfo(
            address(gmToken),
            address(usdcToken),
            address(weth),
            address(usdcToken),
            MAX_PNL_FACTOR_FOR_WITHDRAWALS,
            false
            );
        return marketTokenPrice;
    }

    receive() external payable{}
}

// bytes32 public constant MAX_PNL_FACTOR_FOR_WITHDRAWALS = keccak256(abi.encode("MAX_PNL_FACTOR_FOR_WITHDRAWALS"));
/**
    * @dev Get LP (market) token info
    * @param marketToken LP token address
    * @param indexToken Index token address
    * @param longToken Long token address
    * @param shortToken Short token address
    * @param pnlFactorType P&L Factory type in bytes32 hashed string
    * @param maximize Min/max price boolean // false
    * @return (marketTokenPrice, MarketPoolValueInfoProps MarketInfo)
  */
//   function getMarketTokenInfo(
//     address marketToken, // GM TOKEN
//     address indexToken, // USDC
//     address longToken, // WETH
//     address shortToken, // USDC
//     bytes32 pnlFactorType, // MAX_PNL_FACTOR_FOR_WITHDRAWALS
//     bool maximize // false
//   )