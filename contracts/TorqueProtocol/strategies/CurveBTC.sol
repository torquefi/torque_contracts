// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/// @title CurveBTC - 2BTC Strategy for Curve Integration
/// @notice This contract manages WBTC deposits in Curve, handling deposits, withdrawals, and compounding.
/// @dev The contract interacts with Curve's deposit, stake, and reward functions to manage BTC yield.
contract CurveBTC is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    
    /// @notice WBTC token contract
    IERC20 public wbtcToken;
    /// @notice TBTC token contract
    IERC20 public tbtcToken;
    /// @notice BTC2Gauge token contract
    IERC20 public BTC2Gauge;
    /// @notice Curve DAO token contract
    IERC20 public curveDaoToken;
    /// @notice ARB token contract
    IERC20 public arbToken;

    /// @notice Curve's deposit and stake zap contract
    CurveDepositAndStakeZap public curveDepositAndStakeZap;
    /// @notice Vyper contract for rewards and withdrawals
    Vyper_contract public vyper_contract;
    /// @notice Vyper gauge contract for minting
    Vyper_gauge public vyper_gauge;
    /// @notice Curve's stable swap contract for liquidity management
    CurveStableSwapNG public curveStableSwapNG;
    /// @notice Uniswap v3 swap router
    ISwapRouter public swapRouter;

    uint256 public slippage = 10; // Slippage tolerance in basis points
    uint256 public withdrawSlippage = 1; // Withdraw slippage tolerance in basis points
    address public controller; // Controller address for restricted functions
    uint256 public minPercent = 9900; // Minimum percentage for liquidity minting (max: 10000)
    uint24 public poolFeeArb = 500; // Pool fee for ARB to WBTC swap on Uniswap v3
    uint24 public poolFeeCDao = 500; // Pool fee for Curve DAO to WBTC swap on Uniswap v3

    /// @notice Emitted when WBTC is deposited in Curve.
    /// @param amount The amount of WBTC deposited.
    event Deposited(uint256 amount);

    /// @notice Emitted when WBTC is withdrawn from Curve.
    /// @param amount The amount of WBTC withdrawn.
    event Withdrawal(uint256 amount);

    /// @notice Constructor initializes the CurveBTC contract with token and contract addresses.
    constructor() Ownable(msg.sender) {
        wbtcToken = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
        tbtcToken = IERC20(0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40);
        BTC2Gauge = IERC20(0xB7e23A438C9cad2575d3C048248A943a7a03f3fA);
        curveDaoToken = IERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
        arbToken = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
        curveDepositAndStakeZap = CurveDepositAndStakeZap(0x37c5ab57AF7100Bdc9B668d766e193CCbF6614FD);
        vyper_contract = Vyper_contract(0xB7e23A438C9cad2575d3C048248A943a7a03f3fA);
        vyper_gauge = Vyper_gauge(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);
        curveStableSwapNG = CurveStableSwapNG(0x186cF879186986A20aADFb7eAD50e3C20cb26CeC);
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    }

    /// @notice Deposits WBTC into Curve's deposit and stake zap.
    /// @param amount The amount of WBTC to deposit.
    /// @dev Only the controller can call this function.
    function deposit(uint256 amount) external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");
        require(wbtcToken.transferFrom(msg.sender, address(this), amount), "Transfer Asset Failed");
        
        wbtcToken.approve(address(curveDepositAndStakeZap), amount);

        address[] memory coins = new address[](2);
        coins[0] = address(wbtcToken);
        coins[1] = address(tbtcToken);
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = 0;
        
        // Call Curve's deposit and stake function
        curveDepositAndStakeZap.deposit_and_stake(
            address(curveStableSwapNG), 
            address(curveStableSwapNG), 
            address(BTC2Gauge), 
            2, 
            coins, 
            amounts, 
            amount.mul(minPercent).div(10000), 
            false, 
            true, 
            address(0)
        );

        emit Deposited(amount);
    }

    /// @notice Withdraws WBTC from Curve's gauge and removes liquidity.
    /// @param amount The amount of WBTC to withdraw.
    /// @param totalCurveAmount The total WBTC amount in Curve.
    /// @dev Only the controller can call this function.
    function withdraw(uint256 amount, uint256 totalCurveAmount) external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");

        uint256 btc2Amount = BTC2Gauge.balanceOf(address(this));
        amount = btc2Amount.mul(amount).div(totalCurveAmount);
        BTC2Gauge.approve(address(vyper_contract), amount);

        // Withdraw from the Curve gauge and remove liquidity
        vyper_contract.withdraw(amount);
        curveStableSwapNG.remove_liquidity_one_coin(amount, 0, amount.mul(10**10).div(withdrawSlippage));

        uint256 btcBalance = wbtcToken.balanceOf(address(this));
        require(wbtcToken.transfer(msg.sender, btcBalance), "Transfer Asset Failed");

        emit Withdrawal(amount);
    }

    /// @notice Compounds rewards by claiming and converting them to WBTC.
    /// @dev Converts ARB and Curve DAO tokens to WBTC.
    function compound() external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");

        vyper_contract.claim_rewards();
        vyper_gauge.mint(address(BTC2Gauge));

        convertARBtowbtc(arbToken.balanceOf(address(this)));
        convertCurveDaotowbtc(curveDaoToken.balanceOf(address(this)));

        require(wbtcToken.transfer(msg.sender, wbtcToken.balanceOf(address(this))), "Transfer Asset Failed");
    }

    /// @notice Sets the controller address for restricted functions.
    /// @param _controller New controller address.
    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    /// @notice Sets the slippage tolerance for deposits.
    /// @param _slippage New slippage tolerance in basis points.
    function setSlippage(uint256 _slippage) external onlyOwner {
        slippage = _slippage;
    }

    /// @notice Updates the Uniswap pool fees for ARB and Curve DAO swaps.
    /// @param arbFee New ARB pool fee.
    /// @param cdaoFee New Curve DAO pool fee.
    function updatePoolFee(uint24 arbFee, uint24 cdaoFee) external onlyOwner {
        poolFeeArb = arbFee;
        poolFeeCDao = cdaoFee;
    }

    /// @notice Sets the minimum liquidity percentage for minting.
    /// @param _slippage New minimum percentage (max: 10000).
    function setLiquiditySlippage(uint128 _slippage) external onlyOwner {
        require(_slippage <= 10000, "Invalid value!");
        minPercent = _slippage;
    }

    /// @notice Sets the slippage tolerance for withdrawals.
    /// @param _slippage New withdrawal slippage in basis points.
    function setWithdrawSlippage(uint128 _slippage) external onlyOwner {
        withdrawSlippage = _slippage;
    }

    /// @notice Converts ARB to WBTC using Uniswap v3.
    /// @param arbAmount The amount of ARB to convert.
    /// @return The amount of WBTC received.
    function convertARBtowbtc(uint256 arbAmount) internal returns (uint256) {
        arbToken.approve(address(swapRouter), arbAmount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(arbToken),
            tokenOut: address(wbtcToken),
            fee: poolFeeArb,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: arbAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        return swapRouter.exactInputSingle(params);
    }

    /// @notice Converts Curve DAO tokens to WBTC using Uniswap v3.
    /// @param cDaoAmount The amount of Curve DAO tokens to convert.
    /// @return The amount of WBTC received.
    function convertCurveDaotowbtc(uint256 cDaoAmount) internal returns (uint256) {
        curveDaoToken.approve(address(swapRouter), cDaoAmount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(curveDaoToken),
            tokenOut: address(wbtcToken),
            fee: poolFeeCDao,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: cDaoAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        return swapRouter.exactInputSingle(params);
    }

    /// @notice Withdraws specified token to the owner.
    /// @param _amount The amount of the token to withdraw.
    /// @param _asset The address of the token to withdraw.
    function withdraw(uint256 _amount, address _asset) external onlyOwner {
        require(IERC20(_asset).transfer(msg.sender, _amount), "Transfer Failed");
    }
}
