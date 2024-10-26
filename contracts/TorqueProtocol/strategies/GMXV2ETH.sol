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

/// @title GMXV2ETH Contract
/// @notice Manages deposits, withdrawals, and compounding for WETH on GMX V2.
contract GMXV2ETH is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Wrapped ETH (WETH) token interface
    IWETH9 public weth;
    /// @notice GMX token interface
    IERC20 public gmToken;
    /// @notice USDC token interface
    IERC20 public usdcToken;
    /// @notice Arbitrum token interface
    IERC20 public arbToken;

    /// @notice GMX market address used for deposit and withdrawal interactions
    address public marketAddress = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
    /// @notice Vault address for depositing funds
    address public depositVault;
    /// @notice Vault address for withdrawing funds
    address public withdrawalVault;
    /// @notice Token router address for transfers
    address public router;

    /// @notice GMX exchange router interface
    IGMXExchangeRouter public exchangeRouter;
    /// @notice Uniswap swap router interface
    ISwapRouter public swapRouter;

    /// @notice Total WETH deposited in the contract
    uint256 public depositedWethAmount;
    /// @notice Minimum USDC amount for operations
    uint256 public minUSDCAmount = 0;
    /// @notice Minimum ARB amount required for swaps
    uint256 public minARBAmount = 1 ether;
    /// @notice Swap fee for Uniswap swaps
    uint24 public feeAmt = 500;
    /// @notice Controller address responsible for calling certain functions
    address public controller;

    /// @notice Treasury address for collecting fees
    address public treasury = 0x0f773B3d518d0885DbF0ae304D87a718F68EEED5;
    /// @notice User balances in USDC
    mapping(address => uint256) public usdcAmount;
    /// @notice User balances in WETH
    mapping(address => uint256) public wethAmount;

    /// @notice Constant value for max PnL factor in withdrawals
    bytes32 public constant MAX_PNL_FACTOR_FOR_WITHDRAWALS = keccak256(abi.encode("MAX_PNL_FACTOR_FOR_WITHDRAWALS"));

    /// @notice Data store for GMX Oracle operations
    address public dataStore = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
    /// @notice Chainlink Oracle for price feed
    IChainlinkOracle public chainlinkOracle = IChainlinkOracle(0xb6C62D5EB1F572351CC66540d043EF53c4Cd2239);
    /// @notice Synthetic Reader for GMX
    ISyntheticReader public syntheticReader = ISyntheticReader(0xf60becbba223EEA9495Da3f606753867eC10d139);

    /// @notice GMX Oracle instance for price calculations
    GMXOracle public gmxOracle;

    /// @notice Initializes the GMXV2ETH contract
    /// @param weth_ WETH token address
    /// @param gmToken_ GMX token address
    /// @param usdcToken_ USDC token address
    /// @param arbToken_ ARB token address
    /// @param exchangeRouter_ GMX exchange router address
    /// @param swapRouter_ Uniswap swap router address
    /// @param depositVault_ Deposit vault address
    /// @param withdrawalVault_ Withdrawal vault address
    /// @param router_ Token router address
    constructor(
        address payable weth_,
        address gmToken_,
        address usdcToken_,
        address arbToken_,
        address payable exchangeRouter_,
        address swapRouter_,
        address depositVault_,
        address withdrawalVault_,
        address router_
    ) Ownable(msg.sender) {
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
        gmxOracle = new GMXOracle(dataStore, syntheticReader, chainlinkOracle);
    }

    /// @notice Deposits WETH into the GMX V2 platform
    /// @param _amount Amount of WETH to deposit
    function deposit(uint256 _amount) external payable {
        require(msg.sender == controller, "Only controller can call this");
        require(msg.value > 0, "Execution fee required");

        exchangeRouter.sendWnt{value: msg.value}(address(depositVault), msg.value);
        require(weth.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        weth.approve(address(router), _amount);
        exchangeRouter.sendTokens(address(weth), address(depositVault), _amount);

        IGMXExchangeRouter.CreateDepositParams memory depositParams = createDepositParams();
        exchangeRouter.createDeposit(depositParams);

        depositedWethAmount = depositedWethAmount.add(_amount);
    }

    /// @notice Withdraws WETH from the GMX V2 platform
    /// @param _amount Amount of WETH to withdraw
    /// @param _userAddress User's address
    function withdraw(uint256 _amount, address _userAddress) external payable {
        require(msg.sender == controller, "Only controller can call this");
        require(msg.value > 0, "Execution fee required");

        exchangeRouter.sendWnt{value: msg.value}(address(withdrawalVault), msg.value);

        uint256 gmAmountWithdraw = _amount.mul(gmToken.balanceOf(address(this))).div(depositedWethAmount);
        gmToken.approve(address(router), gmAmountWithdraw);
        exchangeRouter.sendTokens(address(gmToken), address(withdrawalVault), gmAmountWithdraw);

        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams = createWithdrawParams();
        exchangeRouter.createWithdrawal(withdrawParams);

        depositedWethAmount = depositedWethAmount.sub(_amount);
        (uint256 wethWithdraw, uint256 usdcWithdraw) = calculateGMPrice(gmAmountWithdraw);

        usdcAmount[_userAddress] = usdcAmount[_userAddress].add(usdcWithdraw);
        wethAmount[_userAddress] = wethAmount[_userAddress].add(wethWithdraw);
    }

    /// @notice Withdraws user funds considering slippage
    /// @param _slippage Slippage percentage (1 = 0.1%)
    function withdrawAmount(uint16 _slippage) external returns (uint256) {
        require(_slippage < 1000, "Slippage cannot be 1000");
        usdcAmount[msg.sender] = usdcAmount[msg.sender].mul(1000 - _slippage).div(1000);
        wethAmount[msg.sender] = wethAmount[msg.sender].mul(1000 - _slippage).div(1000);

        uint256 usdcBalance = usdcToken.balanceOf(address(this));
        uint256 wethBalanceBefore = weth.balanceOf(address(this));

        require(usdcAmount[msg.sender] <= usdcBalance, "Insufficient USDC balance");
        require(wethAmount[msg.sender] <= wethBalanceBefore, "Insufficient WETH balance");

        if (usdcBalance >= usdcAmount[msg.sender]) {
            swapUSDCtoWETH(usdcAmount[msg.sender]);
        }
        usdcAmount[msg.sender] = 0;

        uint256 wethBalanceAfter = weth.balanceOf(address(this));
        uint256 wethAmountToTransfer = wethAmount[msg.sender].add(wethBalanceAfter).sub(wethBalanceBefore);

        require(wethAmountToTransfer <= wethBalanceAfter, "Insufficient balance");
        wethAmount[msg.sender] = 0;
        require(weth.transfer(msg.sender, wethAmountToTransfer), "Transfer failed");

        return wethAmountToTransfer;
    }

    /// @notice Compounds ARB rewards to WETH
    function compound() external {
        require(msg.sender == controller, "Only controller can call this");

        uint256 arbAmount = arbToken.balanceOf(address(this));
        if (arbAmount > minARBAmount) {
            uint256 wethAmount = swapARBtoWETH(arbAmount);
            require(weth.transfer(msg.sender, wethAmount), "Transfer failed");
        }
    }

    /// @notice Updates the controller address
    /// @param _controller The new controller address
    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    /// @notice Updates the treasury address
    /// @param _treasury The new treasury address
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /// @notice Withdraws treasury fees
    function withdrawTreasuryFees() external onlyOwner {
        payable(treasury).transfer(address(this).balance);
    }

    /// @notice Updates the swap fee
    /// @param fee The new swap fee
    function updateFee(uint24 fee) external onlyOwner {
        feeAmt = fee;
    }

    /// @notice Calculates the GMX price for withdrawals
    /// @param gmAmountWithdraw Amount of GMX to withdraw
    /// @return (uint256, uint256) Returns the calculated WETH and USDC amounts
    function calculateGMPrice(uint256 gmAmountWithdraw) view public returns (uint256, uint256) {
        (, ISyntheticReader.MarketPoolValueInfoProps memory marketPoolValueInfo) = gmxOracle.getMarketTokenInfo(
            address(gmToken),
            address(usdcToken),
            address(weth),
            address(usdcToken),
            MAX_PNL_FACTOR_FOR_WITHDRAWALS,
            false
        );

        uint256 totalGMSupply = gmToken.totalSupply();
        uint256 adjustedSupply = getAdjustedSupply(
            marketPoolValueInfo.longTokenUsd,
            marketPoolValueInfo.shortTokenUsd,
            marketPoolValueInfo.totalBorrowingFees,
            marketPoolValueInfo.netPnl,
            marketPoolValueInfo.impactPoolAmount
        );

        return getEthNUsdcAmount(
            gmAmountWithdraw,
            adjustedSupply.div(totalGMSupply),
            marketPoolValueInfo.longTokenUsd.div(1e11),
            marketPoolValueInfo.shortTokenUsd,
            marketPoolValueInfo.longTokenUsd.div(marketPoolValueInfo.longTokenAmount),
            marketPoolValueInfo.shortTokenUsd.div(marketPoolValueInfo.shortTokenAmount)
        );
    }

    /// @notice Creates deposit parameters for GMX interactions
    /// @return CreateDepositParams Struct containing deposit parameters
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

    /// @notice Creates withdrawal parameters for GMX interactions
    /// @return CreateWithdrawalParams Struct containing withdrawal parameters
    function createWithdrawParams() internal view returns (IGMXExchangeRouter.CreateWithdrawalParams memory) {
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams;
        withdrawParams.receiver = address(this);
        withdrawParams.callbackContract = address(this);
        withdrawParams.market = marketAddress;
        withdrawParams.callbackGasLimit = 0;
        withdrawParams.executionFee = msg.value;
        withdrawParams.shouldUnwrapNativeToken = false;
        withdrawParams.minLongTokenAmount = 0;
        withdrawParams.minShortTokenAmount = 0;
        return withdrawParams;
    }

    /// @notice Internal function to swap USDC to WETH
    /// @param usdcVal USDC amount to swap
    function swapUSDCtoWETH(uint256 usdcVal) internal {
        usdcToken.approve(address(swapRouter), usdcVal);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
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

    /// @notice Internal function to swap ARB to WETH
    /// @param arbAmount ARB amount to swap
    /// @return amountOut Amount of WETH received
    function swapARBtoWETH(uint256 arbAmount) internal returns (uint256 amountOut) {
        arbToken.approve(address(swapRouter), arbAmount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(arbToken),
            tokenOut: address(weth),
            fee: feeAmt,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: arbAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        return swapRouter.exactInputSingle(params);
    }

    /// @notice Gets the adjusted supply for price calculations
    /// @param wethPool WETH pool amount
    /// @param usdcPool USDC pool amount
    /// @param totalBorrowingFees Total borrowing fees
    /// @param pnl Profit and Loss
    /// @param impactPoolPrice Impact pool price
    /// @return adjustedSupply Adjusted supply amount
    function getAdjustedSupply(
        uint256 wethPool,
        uint256 usdcPool,
        uint256 totalBorrowingFees,
        int256 pnl,
        uint256 impactPoolPrice
    ) internal pure returns (uint256 adjustedSupply) {
        wethPool = wethPool.div(1e12);
        usdcPool = usdcPool.div(10);
        totalBorrowingFees = totalBorrowingFees.div(1e6);
        impactPoolPrice = impactPoolPrice.mul(1e6);

        uint256 newPNL = (pnl > 0) ? uint256(pnl) : uint256(-pnl);
        newPNL = newPNL.div(1e12);

        return wethPool.add(usdcPool).sub(totalBorrowingFees).sub(newPNL).sub(impactPoolPrice);
    }

    /// @notice Calculates WETH and USDC amounts from GMX withdrawal
    /// @param gmxWithdraw GMX amount to withdraw
    /// @param price GMX price
    /// @param wethVal WETH value in USD
    /// @param usdcVal USDC value in USD
    /// @param wethPrice WETH price
    /// @param usdcPrice USDC price
    /// @return (uint256, uint256) WETH and USDC amounts received
    function getEthNUsdcAmount(
        uint256 gmxWithdraw,
        uint256 price,
        uint256 wethVal,
        uint256 usdcVal,
        uint256 wethPrice,
        uint256 usdcPrice
    ) public pure returns (uint256, uint256) {
        uint256 wethAmountUSD = gmxWithdraw.mul(price).div(1e6).mul(wethVal).div(wethVal.add(usdcVal));
        uint256 usdcAmountUSD = gmxWithdraw.mul(price).div(1e6).mul(usdcVal).div(wethVal.add(usdcVal));

        return (
            wethAmountUSD.mul(1e19).div(wethPrice),
            usdcAmountUSD.mul(1e7).div(usdcPrice)
        );
    }

    /// @notice Transfers a specific token to a specified address
    /// @param _tokenAddress Token contract address
    /// @param _to Recipient address
    /// @param _amount Amount to transfer
    function transferToken(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        require(IERC20(_tokenAddress).transfer(_to, _amount), "Transfer failed");
    }

    /// @notice Fallback function to receive ETH
    receive() external payable {}
}
