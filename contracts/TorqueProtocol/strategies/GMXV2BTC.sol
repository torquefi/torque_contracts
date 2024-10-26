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

/// @title GMXV2BTC - BTC Strategy using GMX
/// @notice This contract manages BTC deposits, withdrawals, and compounding using GMX and Uniswap.
/// @dev Implements functionality for interacting with GMX, managing WBTC, USDC, and ARB tokens.
contract GMXV2BTC is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Token contracts
    IERC20 public wbtcGMX;  // Wrapped Bitcoin for GMX
    IERC20 public gmToken;  // GMX Token
    IERC20 public usdcToken; // USDC Token
    IERC20 public arbToken;  // ARB Token

    // Contract addresses
    address public marketAddress = 0x47c031236e19d024b42f8AE6780E44A573170703; // Market address for GMX
    address public depositVault; // Vault for deposits
    address public withdrawalVault; // Vault for withdrawals
    address public router; // Router address
    address public controller; // Address of the controller

    // State variables
    uint256 public depositedBTCAmount = 0; // Total deposited BTC amount
    uint256 public minUSDCAmount = 0; // Minimum USDC amount for swapping
    uint24 public feeAmt = 500; // Fee amount for Uniswap V3 swaps
    uint256 public minARBAmount = 1 ether; // Minimum ARB amount for compounding

    // Interfaces
    IGMXExchangeRouter public immutable gmxExchange; // GMX Exchange Router
    ISwapRouter public immutable swapRouter; // Uniswap V3 Swap Router

    // Mapping for user balances
    mapping(address => uint256) public usdcAmount; // User's USDC balance
    mapping(address => uint256) public wbtcAmount; // User's WBTC balance

    address public treasury = 0x0f773B3d518d0885DbF0ae304D87a718F68EEED5; // Treasury address

    // Oracle addresses and instance
    address public dataStore = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8; // Data store address
    IChainlinkOracle public chainlinkOracle = IChainlinkOracle(0xb6C62D5EB1F572351CC66540d043EF53c4Cd2239); // Chainlink Oracle
    ISyntheticReader public syntheticReader = ISyntheticReader(0xf60becbba223EEA9495Da3f606753867eC10d139); // Synthetic Reader
    GMXOracle public gmxOracle; // GMX Oracle instance

    bytes32 public constant MAX_PNL_FACTOR_FOR_WITHDRAWALS = keccak256(abi.encode("MAX_PNL_FACTOR_FOR_WITHDRAWALS")); // Max PnL factor for withdrawals

    /// @notice Initializes the GMXV2BTC contract with required parameters.
    /// @param _wbtc Address of the WBTC token.
    /// @param gmToken_ Address of the GMX token.
    /// @param usdcToken_ Address of the USDC token.
    /// @param arbToken_ Address of the ARB token.
    /// @param exchangeRouter_ Address of the GMX exchange router.
    /// @param swapRouter_ Address of the Uniswap V3 swap router.
    /// @param depositVault_ Address of the deposit vault.
    /// @param withdrawalVault_ Address of the withdrawal vault.
    /// @param router_ Address of the router.
    constructor(
        address _wbtc,
        address gmToken_,
        address usdcToken_,
        address arbToken_,
        address payable exchangeRouter_,
        address swapRouter_,
        address depositVault_,
        address withdrawalVault_,
        address router_
    ) Ownable(msg.sender) {
        wbtcGMX = IERC20(_wbtc);
        gmToken = IERC20(gmToken_);
        usdcToken = IERC20(usdcToken_);
        arbToken = IERC20(arbToken_);
        gmxExchange = IGMXExchangeRouter(exchangeRouter_);
        swapRouter = ISwapRouter(swapRouter_);
        depositVault = depositVault_;
        withdrawalVault = withdrawalVault_;
        router = router_;
        gmxOracle = new GMXOracle(dataStore, syntheticReader, chainlinkOracle);
    }

    /// @notice Deposits WBTC into the GMX vault.
    /// @param _amount The amount of WBTC to deposit.
    /// @dev Only the controller can call this function. Sends WBTC and WNT to the GMX vault.
    function deposit(uint256 _amount) external payable {
        require(msg.sender == controller, "Only controller can call this!");

        // Send WNT to GMX vault for deposit
        gmxExchange.sendWnt{value: msg.value}(address(depositVault), msg.value);

        // Transfer WBTC from user to contract
        require(wbtcGMX.transferFrom(msg.sender, address(this), _amount), "Transfer Asset Failed");

        // Approve WBTC for GMX deposit
        wbtcGMX.approve(address(router), _amount);

        // Send WBTC to GMX deposit vault
        gmxExchange.sendTokens(address(wbtcGMX), address(depositVault), _amount);

        // Create GMX deposit parameters and execute deposit
        IGMXExchangeRouter.CreateDepositParams memory depositParams = createDepositParams();
        gmxExchange.createDeposit(depositParams);

        // Update deposited BTC amount
        depositedBTCAmount = depositedBTCAmount.add(_amount);
    }

    /// @notice Withdraws WBTC from the GMX vault.
    /// @param _amount The amount of WBTC to withdraw.
    /// @param _userAddress The address of the user receiving the withdrawal.
    /// @dev Only the controller can call this function. Proceeds with GMX and USDC withdrawal.
    function withdraw(uint256 _amount, address _userAddress) external payable {
        require(msg.sender == controller, "Only controller can call this!");

        // Send WNT to GMX vault for withdrawal
        gmxExchange.sendWnt{value: msg.value}(address(withdrawalVault), msg.value);

        // Calculate GM token amount to withdraw
        uint256 gmAmountWithdraw = _amount.mul(gmToken.balanceOf(address(this))).div(depositedBTCAmount);

        // Approve GM tokens for withdrawal
        gmToken.approve(address(router), gmAmountWithdraw);

        // Send GM tokens to GMX withdrawal vault
        gmxExchange.sendTokens(address(gmToken), address(withdrawalVault), gmAmountWithdraw);

        // Create GMX withdrawal parameters and execute withdrawal
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams = createWithdrawParams();
        gmxExchange.createWithdrawal(withdrawParams);

        // Update deposited BTC amount
        depositedBTCAmount = depositedBTCAmount.sub(_amount);

        // Calculate WBTC and USDC amounts to withdraw
        (uint256 wbtcWithdraw, uint256 usdcWithdraw) = calculateGMPrice(gmAmountWithdraw);
        usdcAmount[_userAddress] = usdcAmount[_userAddress].add(usdcWithdraw);
        wbtcAmount[_userAddress] = wbtcAmount[_userAddress].add(wbtcWithdraw);
    }

    /// @notice Executes withdrawal of USDC and WBTC with slippage tolerance.
    /// @param _slippage The slippage tolerance for withdrawal.
    /// @return The total amount of WBTC withdrawn.
    function withdrawAmount(uint16 _slippage) external returns (uint256) {
        require(_slippage < 1000, "Slippage can't be 1000");

        // Adjust user's USDC and WBTC balances based on slippage
        usdcAmount[msg.sender] = usdcAmount[msg.sender].mul(1000 - _slippage).div(1000);
        wbtcAmount[msg.sender] = wbtcAmount[msg.sender].mul(1000 - _slippage).div(1000);

        uint256 usdcAmountBalance = usdcToken.balanceOf(address(this));
        uint256 wbtcAmountBefore = wbtcGMX.balanceOf(address(this));

        // Ensure sufficient balance for withdrawal
        require(usdcAmount[msg.sender] <= usdcAmountBalance, "Insufficient USDC balance");
        require(wbtcAmount[msg.sender] <= wbtcAmountBefore, "Insufficient WBTC balance");

        // Swap USDC to WBTC if USDC balance is sufficient
        if (usdcAmountBalance >= usdcAmount[msg.sender]) {
            swapUSDCtoWBTC(usdcAmount[msg.sender]);
        }

        // Reset user's USDC balance
        usdcAmount[msg.sender] = 0;

        // Calculate WBTC amount after conversion
        uint256 wbtcAmountAfter = wbtcGMX.balanceOf(address(this));
        uint256 totalWbtcAmount = wbtcAmount[msg.sender].add(wbtcAmountAfter).sub(wbtcAmountBefore);

        require(totalWbtcAmount <= wbtcAmountAfter, "Insufficient WBTC for withdrawal");

        // Reset user's WBTC balance
        wbtcAmount[msg.sender] = 0;

        // Transfer WBTC to user
        require(wbtcGMX.transfer(msg.sender, totalWbtcAmount), "Transfer Asset Failed");

        return totalWbtcAmount;
    }

    /// @notice Compounds ARB tokens to WBTC.
    /// @dev Only the controller can call this function. Converts ARB to WBTC using Uniswap V3.
    function compound() external {
        require(msg.sender == controller, "Only controller can call this!");

        uint256 arbAmount = arbToken.balanceOf(address(this));

        // Convert ARB to WBTC if ARB amount is sufficient
        if (arbAmount > minARBAmount) {
            uint256 wbtcVal = swapARBtoBTC(arbAmount);
            require(wbtcGMX.transfer(msg.sender, wbtcVal), "Transfer Asset Failed");
        }
    }

    /// @notice Creates GMX deposit parameters for deposit.
    /// @return The GMX deposit parameters.
    function createDepositParams() internal view returns (IGMXExchangeRouter.CreateDepositParams memory) {
        IGMXExchangeRouter.CreateDepositParams memory depositParams;
        depositParams.callbackContract = address(this);
        depositParams.callbackGasLimit = 0;
        depositParams.executionFee = msg.value;
        depositParams.initialLongToken = address(wbtcGMX);
        depositParams.initialShortToken = address(usdcToken);
        depositParams.market = marketAddress;
        depositParams.shouldUnwrapNativeToken = false;
        depositParams.receiver = address(this);
        depositParams.minMarketTokens = 0;
        return depositParams;
    }

    /// @notice Creates GMX withdrawal parameters for withdrawal.
    /// @return The GMX withdrawal parameters.
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

    /// @notice Swaps USDC to WBTC using Uniswap V3.
    /// @param usdcVal The amount of USDC to swap.
    function swapUSDCtoWBTC(uint256 usdcVal) internal {
        usdcToken.approve(address(swapRouter), usdcVal);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
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

    /// @notice Updates the fee for Uniswap V3 swaps.
    /// @param fee The new fee amount.
    function updateFee(uint24 fee) external onlyOwner {
        feeAmt = fee;
    }

    /// @notice Withdraws accumulated treasury fees.
    /// @dev Only callable by the owner.
    function withdrawTreasuryFees() external onlyOwner {
        payable(treasury).transfer(address(this).balance);
    }

    /// @notice Sets the treasury address.
    /// @param _treasury The new treasury address.
    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    /// @notice Swaps ARB to WBTC using Uniswap V3.
    /// @param arbAmount The amount of ARB to swap.
    /// @return The amount of WBTC received.
    function swapARBtoBTC(uint256 arbAmount) internal returns (uint256 amountOut) {
        arbToken.approve(address(swapRouter), arbAmount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(arbToken),
            tokenOut: address(wbtcGMX),
            fee: feeAmt,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: arbAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        return swapRouter.exactInputSingle(params);
    }

    /// @notice Calculates GM price for withdrawals.
    /// @param gmAmountWithdraw The amount of GM tokens to withdraw.
    /// @return The amount of WBTC and USDC received.
    function calculateGMPrice(uint256 gmAmountWithdraw) view public returns (uint256, uint256) {
        (, ISyntheticReader.MarketPoolValueInfoProps memory marketPoolValueInfo) = gmxOracle.getMarketTokenInfo(
            address(gmToken),
            address(usdcToken),
            address(wbtcGMX),
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
        return getBtcNUsdcAmount(
            gmAmountWithdraw,
            adjustedSupply.div(totalGMSupply),
            marketPoolValueInfo.longTokenUsd.div(100),
            marketPoolValueInfo.shortTokenUsd,
            marketPoolValueInfo.longTokenUsd.div(marketPoolValueInfo.longTokenAmount),
            marketPoolValueInfo.shortTokenUsd.div(marketPoolValueInfo.shortTokenAmount)
        );
    }

    /// @notice Calculates BTC and USDC amounts based on GMX withdrawal.
    /// @param gmxWithdraw The amount of GMX withdrawn.
    /// @param price The price of GMX.
    /// @param wbtcVal The WBTC value.
    /// @param usdcVal The USDC value.
    /// @param wbtcPrice The WBTC price.
    /// @param usdcPrice The USDC price.
    /// @return The amounts of WBTC and USDC.
    function getBtcNUsdcAmount(uint256 gmxWithdraw, uint256 price, uint256 wbtcVal, uint256 usdcVal, uint256 wbtcPrice, uint256 usdcPrice) internal pure returns (uint256, uint256) {
        uint256 wbtcAmountUSD = gmxWithdraw.mul(price).div(10e5).mul(wbtcVal);
        wbtcAmountUSD = wbtcAmountUSD.div(wbtcVal.add(usdcVal));

        uint256 usdcAmountUSD = gmxWithdraw.mul(price).div(10e5).mul(usdcVal);
        usdcAmountUSD = usdcAmountUSD.div(wbtcVal.add(usdcVal));

        return (
            wbtcAmountUSD.mul(10e8).div(wbtcPrice),
            usdcAmountUSD.mul(10e6).div(usdcPrice)
        );
    }

    /// @notice Adjusts supply for GMX withdrawal calculations.
    /// @param wbtcPool The WBTC pool.
    /// @param usdcPool The USDC pool.
    /// @param totalBorrowingFees The total borrowing fees.
    /// @param pnl The profit or loss (PnL).
    /// @param impactPoolPrice The impact pool price.
    /// @return The adjusted supply.
    function getAdjustedSupply(uint256 wbtcPool, uint256 usdcPool, uint256 totalBorrowingFees, int256 pnl, uint256 impactPoolPrice) pure internal returns (uint256) {
        wbtcPool = wbtcPool.div(10e2);
        usdcPool = usdcPool.div(10);
        totalBorrowingFees = totalBorrowingFees.div(10e6);
        impactPoolPrice = impactPoolPrice.mul(10e6);
        uint256 newPNL;

        if (pnl > 0) {
            newPNL = uint256(pnl).div(10e12);
            return wbtcPool.add(usdcPool).sub(totalBorrowingFees).sub(newPNL).sub(impactPoolPrice);
        } else {
            newPNL = uint256(-pnl).div(10e12);
            return wbtcPool.add(usdcPool).sub(totalBorrowingFees).add(newPNL).sub(impactPoolPrice);
        }
    }

    /// @notice Sets the controller address.
    /// @param _controller The new controller address.
    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    /// @notice Transfers specified ERC20 tokens to a given address.
    /// @param _tokenAddress The address of the ERC20 token.
    /// @param _to The recipient address.
    /// @param _amount The amount to transfer.
    function transferToken(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        require(IERC20(_tokenAddress).transfer(_to, _amount), "Transfer failed");
    }

    /// @notice Fallback function to reject any ETH sent to the contract
    receive() external payable {
        revert("Cannot receive ETH");
    }
}
