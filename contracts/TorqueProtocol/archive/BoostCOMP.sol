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

// import "./strategies/SushiCOMP.sol";
import "./UniswapCOMP.sol";

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

contract BoostCOMP is BoostAbstract, AutomationCompatible {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Config {
        address treasury;
        uint256 redactedcompPercent;
        uint256 uniswapcompPercent;
        uint256 performanceFee;
    }

    struct Addresses {
        address rewardUtilConfig;
        address rewardUtil;
        address tTokenContract;
        address uniswapV3PoolAddress;
        address uniswapRouterAddress;
        address wethTokenAddress;
        address compTokenAddress;
        address redactedcompAddress;
        address uniswapcompAddress;
    }

    struct ImmutableAddresses {
        ISwapRouter uniswapRouter;
        IERC20 wethToken;
        IERC20 compToken;
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
    event AllocationUpdated(uint256 redactedcompPercent, uint256 uniswapcompPercent);
    event PerformanceFeesDistributed(address indexed treasury, uint256 amount);
    event FeesCompounded();

    constructor(
        address _treasury,
        address _uniswapRouter,
        address _wethToken,
        address _compToken,
        address _uniswapV3PoolAddress,
        address _rewardUtil,
        address _redactedcompAddress,
        address _uniswapcompAddress) {
        treasury = _treasury;
        uniswapRouter = ISwapRouter(_uniswapRouter);
        wethToken = IERC20(_wethToken);
        compToken = IERC20(_compToken);
        uniswapV3Pool = IUniswapV3Pool(_uniswapV3PoolAddress);
        rewardUtil = RewardUtil(_rewardUtil);
        rewardUtilConfig = RewardUtilConfig(_rewardUtilConfig);
        redactedcompAddress = _redactedcompAddress;
        uniswapcompAddress = _uniswapcompAddress;
        redactedcompPercent = 50;
        uniswapcompPercent = 50;
        params = ISwapRouter.ExactInputSingleParams(
            address(wethToken),
            address(compToken),
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
            IERC20(tTokenContract).transferFrom(msg.sender, address(redactedcomp), half),
            "Transfer to Redactedcomp failed"
        );
        require(
            IERC20(tTokenContract).transferFrom(msg.sender, address(uniswapcomp), amount.sub(half)),
            "Transfer to Uniswapcomp failed"
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
        redactedcomp.withdraw(half);
        uniswapcomp.withdraw(amount.sub(half));
        uint256 totalcompAmount = calculateTotalcompAmount(amount);
        tTokenContract.burn(msg.sender, amount);
        compToken.safeTransfer(msg.sender, totalcompAmount);
        emit Withdrawal(msg.sender, amount);
    }

    function compoundFees() internal {
        (uint256 compFees, uint256 wethFees) = collectFeesFromChildVaults();
        uint256 convertedcompFromWeth = convertWETHtocomp(wethFees);
        uint256 totalcompFees = compFees.add(convertedcompFromWeth);
        uint256 performanceFees = totalcompFees * performanceFee / 1000;
        compToken.transfer(treasury, performanceFees);
        uint256 remainingcompFees = totalcompFees.sub(performanceFees);
        redepositcomp(remainingcompFees);
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

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = (block.timestamp >= lastCompoundTimestamp + 12 hours);
    }

    function performUpkeep(bytes calldata) external override {
        if ((block.timestamp >= lastCompoundTimestamp + 12 hours)) {
            _compoundFees();
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

    function setAllocation(uint256 _redactedcompPercent, uint256 _uniswapcompPercent) external onlyOwner {
        require(_redactedcompPercent + _uniswapcompPercent == 100, "Total allocation must be 100%");
        redactedcompPercent = _redactedcompPercent;
        uniswapcompPercent = _uniswapcompPercent;
        emit AllocationUpdated(_redactedcompPercent, _uniswapcompPercent);
    }

    function collectFeesFromChildVaults() internal returns (uint256 compFees, uint256 wethFees) {
        (uint256 compFeeFromRedacted, uint256 wethFeeFromRedacted) = redactedcomp.collectFees();
        compFees = compFees.add(compFeeFromRedacted);
        wethFees = wethFees.add(wethFeeFromRedacted);
        (uint256 compFeeFromUniswap, uint256 wethFeeFromUniswap) = uniswapcomp.collectFees();
        compFees = compFees.add(compFeeFromUniswap);
        wethFees = wethFees.add(wethFeeFromUniswap);
        return (compFees, wethFees);
    }

    function calculateTotalcompAmount(uint256 withdrawAmount) internal view returns (uint256) {
        uint256 compBalance = compToken.balanceOf(address(this));
        uint256 wethBalance = wethToken.balanceOf(address(this));
        uint256 convertedcomp = convertWETHtocomp(wethBalance);
        uint256 totalcompAmount = compBalance.add(convertedcomp);
        uint256 totalSupply = tTokenContract.totalSupply();
        return totalcompAmount.mul(withdrawAmount).div(totalSupply);
    }

    function convertWETHtocomp(uint256 wethAmount) internal returns (uint256) {
        require(wethToken.approve(address(uniswapRouter), wethAmount), "WETH approval failed");
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(wethToken),
            tokenOut: address(compToken),
            fee: 3000, // 0.3% pool fee tier
            recipient: address(this),
            deadline: block.timestamp + 15 minutes,
            amountIn: wethAmount,
            amountOutMinimum: 99.5, // Rasonable minimum amount based on slippage tolerance
            sqrtPriceLimitX96: 0
        });
        // Execute the swap and return the amount of comp received
        return uniswapRouter.exactInputSingle(params);
    }

    function calculateMinimumAmountOut(uint256 wethAmount) internal view returns (uint256) {
        uint256 currentPrice = getLatestPrice(); // Price of 1 WETH in terms of comp
        uint256 expectedcomp = wethAmount * currentPrice;
        uint256 slippageTolerance = 5; // Representing 0.5%
        uint256 amountOutMinimum = expectedcomp * (1000 - slippageTolerance) / 1000;
        return amountOutMinimum;
    }

    function getLatestPrice() internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = uniswapV3Pool.slot0();
        // Convert the sqrt price to a regular price
        // Assumes pool consists of WETH and comp, WETH is token0
        return uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18 >> (96 * 2);
    }

    function distributePerformanceFees(uint256 totalFees) internal {
        compToken.transfer(treasury, totalFees);
        emit PerformanceFeesDistributed(treasury, totalFees);
    }

    receive() external payable {}
}

