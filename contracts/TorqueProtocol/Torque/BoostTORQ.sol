// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/INonfungiblePositionManager.sol";

import "./vaults/redactedTORQ.sol";
import "./vaults/UniswapTORQ.sol";

import "./tToken.sol";
import "./RewardUtil";
import "./RewardUtilConfig.sol";

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

contract BoostTORQ is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    address public treasury;
    address public rewardDistributionConfig;
    ISwapRouter public immutable uniswapRouter;
    IERC20 public immutable wethToken;
    IERC20 public immutable torqToken;
    Allocation public currentAllocation;
    RewardUtil public rewardUtil;
    RewardUtilConfig public rewardUtilConfig;
    ISwapRouter.ExactInputSingleParams public params;
    IUniswapV3Pool public uniswapV3Pool;
    RedactedTORQ public redactedTORQ;
    UniswapTORQ public uniswapTORQ;

    struct Allocation {
        uint256 redactedTORQPercent;
        uint256 uniswapTORQPercent;
    }

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event EtherSwept(address indexed treasury, uint256 amount);
    event TokensSwept(address indexed token, address indexed treasury, uint256 amount);
    event UpdatedAllocation(uint256 redactedTORQPercent, uint256 uniswapTORQPercent);
    event RedepositCompleted(uint256 amount);
    event FeesCompounded();
    event FeesCollected();

    mapping(address => uint256) public lastDepositTime;

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
        redactedTORQ = RedactedTORQ(_redactedTORQAddress);
        uniswapTORQ = UniswapTORQ(_uniswapTORQAddress);
        currentAllocation = Allocation(50, 50);
        params = ISwapRouter.ExactInputSingleParams(
            address(wethToken),
            address(torqToken),
            3000, // Fee
            address(this),
            block.timestamp + 15 minutes,
            0, // amountIn can set later
            99.5, // amountOutMinimum
            0 // sqrtPriceLimitX96
        );
    }
    
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "BoostTORQ: Deposit amount must be greater than zero");
        uint256 half = amount.div(2);
        require(
            IERC20(tTokenContract).transferFrom(msg.sender, address(redactedTORQ), half),
            "BoostTORQ: Transfer to RedactedTORQ failed"
        );
        require(
            IERC20(tTokenContract).transferFrom(msg.sender, address(uniswapTORQ), amount.sub(half)),
            "BoostTORQ: Transfer to UniswapTORQ failed"
        );
        lastDepositTime[msg.sender] = block.timestamp;
        tTokenContract.mint(msg.sender, amount);
        emit Deposit(msg.sender, amount);
    }
    
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(tTokenContract.balanceOf(msg.sender) >= amount, "Insufficient balance");
        uint256 fee = 0;
            if (block.timestamp < lastDepositTime[msg.sender] + 7 days) {
            fee = amount / 10;
            amount -= fee; 
            torqToken.safeTransfer(treasury, fee);
        }
        uint256 half = amount.div(2);
        redactedTORQ.withdraw(half);
        uniswapTORQ.withdraw(amount.sub(half));
        uint256 totalTorqAmount = processAndConvertAssets();
        tTokenContract.burn(msg.sender, amount);
        torqToken.safeTransfer(msg.sender, totalTorqAmount);
        emit Withdrawal(msg.sender, amount);
    }

    function sweep(address[] memory _tokens, address _treasury) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = IERC20(_tokens[i]);
            if (tokenAddress == address(0)) {
                uint256 balance = address(this).balance;
                _treasury.transfer(balance);
                emit EtherSwept(_treasury, balance);
            } else {
                IERC20 token = IERC20(tokenAddress);
                uint256 balance = token.balanceOf(address(this));
                token.transfer(_treasury, balance);
                emit TokensSwept(tokenAddress, _treasury, balance);
            }
        }
    }

    function updateAllocation(uint256 _redactedTORQPercent, uint256 _uniswapTORQPercent) external onlyOwner {
        require(_redactedTORQPercent + _uniswapTORQPercent == 100, "Total allocation must be 100%");
        currentAllocation = Allocation(_redactedTORQPercent, _uniswapTORQPercent);
    }

    function compoundFees() external onlyOwner nonReentrant {
        // Logic for auto-compounding fees
        // 12 hr minimum duration between calls
        emit FeesCompounded();
    }

    function collectFees() external onlyOwner nonReentrant {
        // Logic for collecting performance fees
        // 12 hr minimum duration between calls
        emit FeesCollected();
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        require(_performanceFee <= 1000, "Invalid performance fee");
        performanceFee = _performanceFee;
    }

    function setRewardUtil(address _rewardUtil) external onlyOwner {
        rewardUtil = RewardUtil(_rewardUtil);
    }

    function setRewardUtilConfig(address _config) external {
        require(msg.sender == treasury, "Only treasury can set config");
        rewardUtilConfig = _config;
    }

    function collectFeesFromChildVaults() internal returns (uint256 torqFees, uint256 wethFees) {
        // Collect fees from each child vault (e.g., redactedTORQ, uniswapTORQ)
        // Each child vault should have a function that returns the amount of fees in TORQ and WETH
        return (torqFees, wethFees);
        // Execute the swap and return the amount of TORQ received
        uint256 torqReceived = uniswapRouter.exactInputSingle(params);
        return torqReceived;
    }

    function redepositTORQ(uint256 torqAmount) internal {
        require(torqAmount > 0, "No TORQ to redeposit");
        uint256 half = torqAmount / 2;
        uint256 torqBalance = torqToken.balanceOf(address(this));
        require(torqBalance >= torqAmount, "Insufficient TORQ balance");
        require(torqToken.approve(address(redactedTORQ), half), "TORQ approval failed for RedactedTORQ");
        require(torqToken.approve(address(uniswapTORQ), half), "TORQ approval failed for UniswapTORQ");
        redactedTORQ.depositTORQ(half);
        uniswapTORQ.depositTORQ(half); 
        emit RedepositCompleted(torqAmount);
    }

    function processAndConvertAssets() internal returns (uint256) {
        uint256 torqBalance = torqToken.balanceOf(address(this));
        uint256 wethBalance = wethToken.balanceOf(address(this));
        uint256 convertedTorq = convertWETHtoTORQ(wethBalance);
        return torqBalance.add(convertedTorq);
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
}
