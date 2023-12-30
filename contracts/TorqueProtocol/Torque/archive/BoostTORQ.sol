// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./BoostAbstract.sol";

import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

import "./strategies/redactedTORQ.sol";
import "./strategies/UniswapTORQ.sol";

import "./tToken.sol";

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

contract BoostTORQ is BoostAbstract, AutomationCompatible {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Config {
        address treasury;
        uint256 redactedTORQPercent;
        uint256 uniswapTORQPercent;
        uint256 performanceFee;
    }

    struct Addresses {
        address rewardUtilConfig;
        address rewardUtil;
        address tTokenContract;
        address uniswapV3PoolAddress;
        address uniswapRouterAddress;
        address wethTokenAddress;
        address torqTokenAddress;
        address redactedTORQAddress;
        address uniswapTORQAddress;
    }

    struct ImmutableAddresses {
        ISwapRouter uniswapRouter;
        IERC20 wethToken;
        IERC20 torqToken;
        IUniswapV3Pool uniswapV3Pool;
    }

    struct State {
        ISwapRouter.ExactInputSingleParams params;
        mapping(address => uint256) lastDepositTime;
        mapping(address => uint256) lastCalledTime;
    }

    Config public config;
    Addresses public addresses;
    ImmutableAddresses public immutableAddresses;
    State public state;
    uint public totalSupplied;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event EtherSwept(address indexed treasury, uint256 amount);
    event TokensSwept(address indexed token, address indexed treasury, uint256 amount);
    event AllocationUpdated(uint256 redactedTORQPercent, uint256 uniswapTORQPercent);
    event PerformanceFeesDistributed(address indexed treasury, uint256 amount);
    event FeesCompounded();

    constructor(
        address _treasury,
        address _uniswapRouter,
        address _wethToken,
        address _torqToken,
        address _uniswapV3PoolAddress,
        address _rewardUtil,
        address _rewardUtilConfig,
        address _redactedTORQAddress,
        address _uniswapTORQAddress) {
        treasury = _treasury;
        uniswapRouter = ISwapRouter(_uniswapRouter);
        wethToken = IERC20(_wethToken);
        torqToken = IERC20(_torqToken);
        uniswapV3Pool = IUniswapV3Pool(_uniswapV3PoolAddress);
        rewardUtil = RewardUtil(_rewardUtil);
        rewardUtilConfig = RewardUtilConfig(_rewardUtilConfig);
        redactedTORQAddress = _redactedTORQAddress;
        uniswapTORQAddress = _uniswapTORQAddress;
        redactedTORQPercent = 50;
        uniswapTORQPercent = 50;
        params = ISwapRouter.ExactInputSingleParams(
            address(wethToken),
            address(torqToken),
            3000, // Fee
            address(this),
            block.timestamp + 2 minutes,
            0, // amountIn can set later
            99.5, // amountOutMinimum
            0 // sqrtPriceLimitX96
        );
    }

    mapping(address => uint256) public minDepositDuration;
    
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Deposit amount must be greater than zero");
        uint256 half = amount.div(2);
        require(
            IERC20(tTokenContract).transferFrom(msg.sender, address(redactedTORQ), half),
            "Transfer to RedactedTORQ failed"
        );
        require(
            IERC20(tTokenContract).transferFrom(msg.sender, address(uniswapTORQ), amount.sub(half)),
            "Transfer to UniswapTORQ failed"
        );
        lastDepositTime[msg.sender] = block.timestamp;
        minDepositDuration[msg.sender] = block.timestamp;
        tTokenContract.mint(msg.sender, amount);
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(tTokenContract.balanceOf(msg.sender) >= amount, "Insufficient balance");
        uint256 minimumDuration = 7 days;
        require(
            block.timestamp >= minDepositDuration[msg.sender] + minimumDuration,
            "Minimum duration not reached, but you may withdraw."
        );
        uint256 half = amount.div(2);
        redactedTORQ.withdraw(half);
        uniswapTORQ.withdraw(amount.sub(half));
        uint256 totalTorqAmount = calculateTotalTorqAmount(amount);
        tTokenContract.burn(msg.sender, amount);
        torqToken.safeTransfer(msg.sender, totalTorqAmount);
        emit Withdrawal(msg.sender, amount);
    }

    function compoundFees() external onlyOwner nonReentrant {
        require(block.timestamp >= lastCalledTime[msg.sender] + 12 hours, "Minimum 12 hours not reached");
        (uint256 torqFees, uint256 wethFees) = collectFeesFromChildVaults();
        uint256 convertedTorqFromWeth = convertWETHtoTORQ(wethFees);
        uint256 totalTorqFees = torqFees.add(convertedTorqFromWeth);
        uint256 performanceFees = totalTorqFees * performanceFee / 1000;
        torqToken.transfer(treasury, performanceFees);
        uint256 remainingTorqFees = totalTorqFees.sub(performanceFees);
        redepositTORQ(remainingTorqFees);
        lastCalledTime[msg.sender] = block.timestamp;
        emit FeesCompounded();
    }

    function sweep(address[] memory _tokens, address _treasury) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address tokenAddress = _tokens[i];
            uint256 balance;
            if (tokenAddress == address(0)) {
                balance = address(this).balance;
                if (balance > 0) {
                    payable(_treasury).transfer(balance);
                    emit EtherSwept(_treasury, balance);
                }
            } else {
                IERC20 token = IERC20(tokenAddress);
                balance = token.balanceOf(address(this));
                if (balance > 0) {
                    token.transfer(_treasury, balance);
                    emit TokensSwept(tokenAddress, _treasury, balance);
                }
            }
        }
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        performanceFee = _performanceFee;
    }

    function setRewardUtil(address _rewardUtil) external onlyOwner {
        rewardUtil = RewardUtil(_rewardUtil);
    }

    function setRewardUtilConfig(address _config) external onlyOwner {
        rewardUtilConfig = _config;
    }

    function setAllocation(uint256 _redactedTORQPercent, uint256 _uniswapTORQPercent) external onlyOwner {
        require(_redactedTORQPercent + _uniswapTORQPercent == 100, "Total allocation must be 100%");
        redactedTORQPercent = _redactedTORQPercent;
        uniswapTORQPercent = _uniswapTORQPercent;
        emit AllocationUpdated(_redactedTORQPercent, _uniswapTORQPercent);
    }

    function collectFeesFromChildVaults() internal returns (uint256 torqFees, uint256 wethFees) {
        (uint256 torqFeeFromRedacted, uint256 wethFeeFromRedacted) = redactedTORQ.collectFees();
        torqFees = torqFees.add(torqFeeFromRedacted);
        wethFees = wethFees.add(wethFeeFromRedacted);
        (uint256 torqFeeFromUniswap, uint256 wethFeeFromUniswap) = uniswapTORQ.collectFees();
        torqFees = torqFees.add(torqFeeFromUniswap);
        wethFees = wethFees.add(wethFeeFromUniswap);
        return (torqFees, wethFees);
    }

    function calculateTotalTorqAmount(uint256 withdrawAmount) internal view returns (uint256) {
        uint256 torqBalance = torqToken.balanceOf(address(this));
        uint256 wethBalance = wethToken.balanceOf(address(this));
        uint256 convertedTorq = convertWETHtoTORQ(wethBalance);
        uint256 totalTorqAmount = torqBalance.add(convertedTorq);
        uint256 totalSupply = tTokenContract.totalSupply();
        return totalTorqAmount.mul(withdrawAmount).div(totalSupply);
    }

    function convertWETHtoTORQ(uint256 wethAmount) internal returns (uint256) {
        require(wethToken.approve(address(uniswapRouter), wethAmount), "WETH approval failed");
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(wethToken),
            tokenOut: address(torqToken),
            fee: 3000, // 0.3% pool fee tier
            recipient: address(this),
            deadline: block.timestamp + 15 minutes,
            amountIn: wethAmount,
            amountOutMinimum: 99.5, // Rasonable minimum amount based on slippage tolerance
            sqrtPriceLimitX96: 0
        });
        // Execute the swap and return the amount of TORQ received
        return uniswapRouter.exactInputSingle(params);
    }

    function calculateMinimumAmountOut(uint256 wethAmount) internal view returns (uint256) {
        uint256 currentPrice = getLatestPrice(); // Price of 1 WETH in terms of TORQ
        uint256 expectedTorq = wethAmount * currentPrice;
        uint256 slippageTolerance = 5; // Representing 0.5%
        uint256 amountOutMinimum = expectedTorq * (1000 - slippageTolerance) / 1000;
        return amountOutMinimum;
    }

    function getLatestPrice() internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = uniswapV3Pool.slot0();
        // Convert the sqrt price to a regular price
        // Assumes pool consists of WETH and TORQ, WETH is token0
        return uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18 >> (96 * 2);
    }

    function distributePerformanceFees(uint256 totalFees) internal {
        torqToken.transfer(treasury, totalFees);
        emit PerformanceFeesDistributed(treasury, totalFees);
    }

    receive() external payable {}
}
