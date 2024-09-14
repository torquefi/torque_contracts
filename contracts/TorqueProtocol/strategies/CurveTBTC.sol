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

// 1. 0x37c5ab57AF7100Bdc9B668d766e193CCbF6614FD --> deposit_and_stake (https://arbiscan.io/tx/0xf30078b6c3d81402ad6955b7864859d4630700267ef263a760ff85cd698dcf61)
// 2. 0xB7e23A438C9cad2575d3C048248A943a7a03f3fA --> claim_rewards() (https://arbiscan.io/tx/0xbd13c29b11291570de8f963140efabcffe810aebfc425c290684a6a37ea8f8d3)
// 3. 0xabC000d88f23Bb45525E447528DBF656A9D55bf5 --> mint(0xB7e23A438C9cad2575d3C048248A943a7a03f3fA) (https://arbiscan.io/tx/0xd2a1a78f6c77acf1d5b09ce11ab7c740bc17c4411a4a1c5bcab88f4095e91245)
// 4. 0xB7e23A438C9cad2575d3C048248A943a7a03f3fA --> withdraw(uint256 amount) (https://arbiscan.io/tx/0x8f2c67bd9ff9dceeb3828defaea7fddf71394420c803f661bc9879747e232c57)
// 5. 0x186cF879186986A20aADFb7eAD50e3C20cb26CeC --> remove_liquidity_one_coin (https://arbiscan.io/tx/0x3371b6b4baa828032a424777f84f29f9dfb2c45eaceb1bb19d2bd03e39052004)


interface CurveDepositAndStakeZap {

    function deposit_and_stake(
        address deposit, //	0x186cF879186986A20aADFb7eAD50e3C20cb26CeC
        address lp_token, // 	0x186cF879186986A20aADFb7eAD50e3C20cb26CeC
        address gauge, // 0xB7e23A438C9cad2575d3C048248A943a7a03f3fA
        uint256 n_coins, // 2
        address[] memory coins, // 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, 0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40
        uint256[] memory amounts,
        uint256 min_mint_amount,
        bool use_underlying, // false
        bool is_plain_stable_ng, // true 
        address pool) external; // 	0x0000000000000000000000000000000000000000   
}

interface Vyper_contract {
    function claim_rewards() external;
    function withdraw(uint256 amount) external; 
}

interface Vyper_gauge {
    function mint(address gauge) external; // 0xB7e23A438C9cad2575d3C048248A943a7a03f3fA
}	

interface CurveStableSwapNG {
    function remove_liquidity_one_coin(
        uint256 burn_amount,
        int128 i, // 0
        uint256 min_received
    ) external;
}

contract CurveTBTC is Ownable, ReentrancyGuard {

    using SafeMath for uint256;
    
    IERC20 public wbtcToken = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20 public tbtcToken = IERC20(0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40);
    IERC20 public BTC2Gauge = IERC20(0xB7e23A438C9cad2575d3C048248A943a7a03f3fA);
    IERC20 public curveDaoToken = IERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    IERC20 public arbToken = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);

    CurveDepositAndStakeZap curveDepositAndStakeZap = CurveDepositAndStakeZap(0x37c5ab57AF7100Bdc9B668d766e193CCbF6614FD);
    Vyper_contract vyper_contract = Vyper_contract(0xB7e23A438C9cad2575d3C048248A943a7a03f3fA);
    Vyper_gauge vyper_gauge = Vyper_gauge(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);
    CurveStableSwapNG curveStableSwapNG = CurveStableSwapNG(0x186cF879186986A20aADFb7eAD50e3C20cb26CeC);
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint256 slippage = 20;
    uint256 withdrawSlippage = 1;
    address controller;
    uint256 minPercent = 9900; // Add update option with max 10000
    uint24 poolFeeArb = 500;
    uint24 poolFeeCDao = 500;

    event Deposited(uint256 amount);
    event Withdrawal(uint256 amount);

    constructor() Ownable(msg.sender) {
    }

    function deposit(uint256 amount) external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");
        require(wbtcToken.transferFrom(msg.sender, address(this), amount), "Transfer Asset Failed");
        
        wbtcToken.approve(address(curveDepositAndStakeZap), amount);

        address[] memory coins = new address[](2);
        coins[0] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
        coins[1] = 0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = 0;
        
        curveDepositAndStakeZap.deposit_and_stake(0x186cF879186986A20aADFb7eAD50e3C20cb26CeC, 0x186cF879186986A20aADFb7eAD50e3C20cb26CeC, 0xB7e23A438C9cad2575d3C048248A943a7a03f3fA, 2, coins , amounts, amount*minPercent*10e6, false, true, 0x0000000000000000000000000000000000000000);

        emit Deposited(amount);

    }

    function withdraw(uint256 amount, uint256 totalCurveAmount) external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");
        uint256 btc2Amount = BTC2Gauge.balanceOf(address(this));
        amount = btc2Amount*amount/totalCurveAmount;
        BTC2Gauge.approve(address(vyper_contract), amount);

        vyper_contract.withdraw(amount);
        curveStableSwapNG.remove_liquidity_one_coin(amount, 0, amount/(10e10*withdrawSlippage));
        uint256 btcBalance = wbtcToken.balanceOf(address(this));
        wbtcToken.transfer(msg.sender, btcBalance);

        emit Withdrawal(amount);
    }

    function compound() external nonReentrant {
        require(msg.sender == controller, "Only controller can call this!");
        
        vyper_contract.claim_rewards();
        vyper_gauge.mint(0xB7e23A438C9cad2575d3C048248A943a7a03f3fA);

        convertARBtowbtc(arbToken.balanceOf(address(this)));
        convertCurveDaotowbtc(curveDaoToken.balanceOf(address(this)));
        wbtcToken.transfer(msg.sender, wbtcToken.balanceOf(address(this)));
    }

    function setController(address _controller) external onlyOwner() {
        controller = _controller;
    }

    function setSlippage(uint256 _slippage) external onlyOwner {
        slippage = _slippage;
    }

    function updatePoolFee(uint24 arbFee, uint24 cdaoFee) external onlyOwner {
        poolFeeArb = arbFee;
        poolFeeCDao = cdaoFee;
    }

    // 9000 --> 10000 (90% --> 100%)
    function setLiquiditySlippage(uint128 _slippage) external onlyOwner {
        require(_slippage <= 10000, "Invalid value!");
        minPercent = _slippage;
    }

    function setWithdrawSlippage(uint128 _slippage) external onlyOwner {
        withdrawSlippage = _slippage;
    }

    function convertARBtowbtc(uint256 arbAmount) internal returns (uint256) {
        arbToken.approve(address(swapRouter), arbAmount);
        ISwapRouter.ExactInputSingleParams memory params =  
            ISwapRouter.ExactInputSingleParams({
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

    function convertCurveDaotowbtc(uint256 cDaoAmount) internal returns (uint256) {
        curveDaoToken.approve(address(swapRouter), cDaoAmount);
        ISwapRouter.ExactInputSingleParams memory params =  
            ISwapRouter.ExactInputSingleParams({
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

    function withdraw(uint256 _amount, address _asset) external onlyOwner {
        IERC20(_asset).transfer(msg.sender, _amount);
    }

}
