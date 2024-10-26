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

/// @title GMXV2LINK Contract
/// @notice Handles LINK deposits, withdrawals, and trading on GMX and Uniswap protocols.
contract GMXV2LINK is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public linkToken;       // LINK token interface
    IERC20 public gmToken;         // GM token interface
    IERC20 public usdcToken;       // USDC token interface
    IERC20 public arbToken;        // ARB token interface

    address marketAddress = 0x7f1fa204bb700853D36994DA19F830b6Ad18455C; // GMX market address
    address depositVault;          // Address for the deposit vault
    address withdrawalVault;       // Address for the withdrawal vault
    address router;                // Router address for transactions
    address controller;            // Address controlling the contract

    uint256 public depositedLinkAmount = 0; // Total amount of LINK deposited
    uint256 minUSDCAmount = 0;  // Minimum USDC amount

    uint24 feeAmt = 500;         // Fee amount for swaps
    uint256 minARBAmount = 1 ether; // Minimum ARB amount for swaps
    
    IGMXExchangeRouter public immutable gmxExchange; // GMX exchange router
    ISwapRouter public immutable swapRouter;          // Uniswap swap router

    mapping (address => uint256) public usdcAmount; // USDC amount per user
    mapping (address => uint256) public linkAmount; // LINK amount per user

    address public treasury = 0x0f773B3d518d0885DbF0ae304D87a718F68EEED5; // Treasury address

    address dataStore = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8; // Data store address
    IChainlinkOracle chainlinkOracle = IChainlinkOracle(0xb6C62D5EB1F572351CC66540d043EF53c4Cd2239); // Chainlink oracle
    ISyntheticReader syntheticReader = ISyntheticReader(0xf60becbba223EEA9495Da3f606753867eC10d139); // Synthetic reader
    GMXOracle gmxOracle;  // GMX oracle instance
    
    bytes32 public constant MAX_PNL_FACTOR_FOR_WITHDRAWALS = keccak256(abi.encode("MAX_PNL_FACTOR_FOR_WITHDRAWALS"));

    /// @notice Initializes the GMXV2LINK contract
    /// @param linkToken_ Address of the LINK token
    /// @param gmToken_ Address of the GM token
    /// @param usdcToken_ Address of the USDC token
    /// @param arbToken_ Address of the ARB token
    /// @param exchangeRouter_ Address of the GMX exchange router
    /// @param swapRouter_ Address of the Uniswap swap router
    /// @param depositVault_ Address of the deposit vault
    /// @param withdrawalVault_ Address of the withdrawal vault
    /// @param router_ Address of the router
    constructor(
        address linkToken_,
        address gmToken_, 
        address usdcToken_, 
        address arbToken_, 
        address payable exchangeRouter_, 
        address swapRouter_, 
        address depositVault_, 
        address withdrawalVault_, 
        address router_
    ) Ownable(msg.sender) {
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

    /// @notice Deposits LINK into the GMXV2LINK contract
    /// @param _amount Amount of LINK to deposit
    function deposit(uint256 _amount) external payable {
        require(msg.sender == controller, "Only controller can call this!");
        gmxExchange.sendWnt{value: msg.value}(address(depositVault), msg.value); // Send WNT to deposit vault
        require(linkToken.transferFrom(msg.sender, address(this), _amount), "Transfer Asset Failed");
        linkToken.approve(address(router), _amount); // Approve LINK for router
        gmxExchange.sendTokens(address(linkToken), address(depositVault), _amount);
        
        IGMXExchangeRouter.CreateDepositParams memory depositParams = createDepositParams();
        gmxExchange.createDeposit(depositParams);
        depositedLinkAmount = depositedLinkAmount.add(_amount); // Update deposited LINK amount
    }

    /// @notice Withdraws LINK from the GMXV2LINK contract
    /// @param _amount Amount of LINK to withdraw
    /// @param _userAddress Address of the user withdrawing LINK
    function withdraw(uint256 _amount, address _userAddress) external payable {
        require(msg.sender == controller, "Only controller can call this!");
        gmxExchange.sendWnt{value: msg.value}(address(withdrawalVault), msg.value); // Send WNT to withdrawal vault
        uint256 gmAmountWithdraw = _amount.mul(gmToken.balanceOf(address(this))).div(depositedLinkAmount); // Calculate GM amount to withdraw
        gmToken.approve(address(router), gmAmountWithdraw); // Approve GM token for router
        gmxExchange.sendTokens(address(gmToken), address(withdrawalVault), gmAmountWithdraw);
        
        IGMXExchangeRouter.CreateWithdrawalParams memory withdrawParams = createWithdrawParams();
        gmxExchange.createWithdrawal(withdrawParams);
        depositedLinkAmount = depositedLinkAmount.sub(_amount); // Update deposited LINK amount
        
        (uint256 linkWithdraw, uint256 usdcWithdraw) = calculateGMPrice(gmAmountWithdraw); // Calculate withdrawal amounts
        usdcAmount[_userAddress] = usdcAmount[_userAddress].add(usdcWithdraw);
        linkAmount[_userAddress] = linkAmount[_userAddress].add(linkWithdraw);
    }

    /// @notice Withdraws a specified amount of USDC and LINK based on slippage
    /// @param _slippage Slippage percentage for withdrawal
    /// @return linkAmount Amount of LINK withdrawn
    function withdrawAmount(uint16 _slippage) external returns (uint256) {
        require(_slippage < 1000, "Slippage cant be 1000");
        
        // Adjust user amounts based on slippage
        usdcAmount[msg.sender] = usdcAmount[msg.sender].mul(1000 - _slippage).div(1000);
        linkAmount[msg.sender] = linkAmount[msg.sender].mul(1000 - _slippage).div(1000);
        
        uint256 usdcAmountBalance = usdcToken.balanceOf(address(this));
        uint256 linkAmountBefore = linkToken.balanceOf(address(this));
        
        require(usdcAmount[msg.sender] <= usdcAmountBalance, "Insufficient Funds, Execute Withdrawal not processed");
        require(linkAmount[msg.sender] <= linkAmountBefore, "Insufficient Funds, Execute Withdrawal not processed");
        
        if (usdcAmountBalance >= usdcAmount[msg.sender]) {
            swapUSDCtoLINK(usdcAmount[msg.sender]); // Swap USDC to LINK if sufficient balance
        }
        
        usdcAmount[msg.sender] = 0; // Reset user USDC amount
        uint256 linkAmountAfter = linkToken.balanceOf(address(this));
        uint256 _linkAmount = linkAmount[msg.sender].add(linkAmountAfter).sub(linkAmountBefore);
        
        require(_linkAmount <= linkAmountAfter, "Not enough balance");
        linkAmount[msg.sender] = 0; // Reset user LINK amount
        require(linkToken.transfer(msg.sender, _linkAmount), "Transfer Asset Failed");
        
        return _linkAmount; // Return amount of LINK withdrawn
    }

    /// @notice Compounds the earnings from the GMX and ARB tokens
    function compound() external {
        require(msg.sender == controller, "Only controller can call this!");
        uint256 arbAmount = arbToken.balanceOf(address(this));
        if (arbAmount > minARBAmount) {
            uint256 linkVal = swapARBtoLINK(arbAmount); // Swap ARB to LINK if sufficient amount
            require(linkToken.transfer(msg.sender, linkVal), "Transfer Asset Failed");
        }
    }

    /// @notice Internal function to create deposit parameters for GMX
    /// @return depositParams The deposit parameters
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

    /// @notice Internal function to create withdrawal parameters for GMX
    /// @return withdrawParams The withdrawal parameters
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

    /// @notice Swaps USDC for LINK using Uniswap
    /// @param usdcVal Amount of USDC to swap
    function swapUSDCtoLINK(uint256 usdcVal) internal {
        usdcToken.approve(address(swapRouter), usdcVal); // Approve USDC for swapping
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

        swapRouter.exactInputSingle(params); // Execute swap
    }

    /// @notice Updates the fee amount for swaps
    /// @param fee New fee amount
    function updateFee(uint24 fee) external onlyOwner {
        feeAmt = fee;
    }

    /// @notice Withdraws treasury fees to the treasury address
    function withdrawTreasuryFees() external onlyOwner {
        payable(treasury).transfer(address(this).balance); // Withdraw to treasury
    }

    /// @notice Sets the treasury address
    /// @param _treasury New treasury address
    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    /// @notice Swaps ARB for LINK using Uniswap
    /// @param arbAmount Amount of ARB to swap
    /// @return amountOut Amount of LINK received
    function swapARBtoLINK(uint256 arbAmount) internal returns (uint256 amountOut) {
        arbToken.approve(address(swapRouter), arbAmount); // Approve ARB for swapping
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(arbToken),
                tokenOut: address(linkToken),
                fee: feeAmt,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: arbAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        return swapRouter.exactInputSingle(params); // Execute swap
    }

    /// @notice Calculates the value of GM tokens in terms of LINK and USDC
    /// @param gmAmountWithdraw Amount of GM tokens to withdraw
    /// @return linkWithdraw Amount of LINK received
    /// @return usdcWithdraw Amount of USDC received
    function calculateGMPrice(uint256 gmAmountWithdraw) view public returns (uint256, uint256) {
        (, ISyntheticReader.MarketPoolValueInfoProps memory marketPoolValueInfo) = gmxOracle.getMarketTokenInfo(
            address(gmToken),
            address(usdcToken),
            address(linkToken),
            address(usdcToken),
            MAX_PNL_FACTOR_FOR_WITHDRAWALS,
            false
        );
        uint256 totalGMSupply = gmToken.totalSupply(); 
        uint256 adjustedSupply = getAdjustedSupply(marketPoolValueInfo.longTokenUsd, marketPoolValueInfo.shortTokenUsd, marketPoolValueInfo.totalBorrowingFees, marketPoolValueInfo.netPnl, marketPoolValueInfo.impactPoolAmount);
        return getLinkNUsdcAmount(gmAmountWithdraw, adjustedSupply.div(totalGMSupply), marketPoolValueInfo.longTokenUsd.div(10e11), marketPoolValueInfo.shortTokenUsd, marketPoolValueInfo.longTokenUsd.div(marketPoolValueInfo.longTokenAmount), marketPoolValueInfo.shortTokenUsd.div(marketPoolValueInfo.shortTokenAmount));
    }

    /// @notice Calculates the amount of LINK and USDC based on GM withdrawal
    /// @param gmxWithdraw Amount of GM withdrawn
    /// @param price Price for conversion
    /// @param linkVal LINK value
    /// @param usdcVal USDC value
    /// @param linkPrice LINK price
    /// @param usdcPrice USDC price
    /// @return Amount of LINK and USDC calculated
    function getLinkNUsdcAmount(uint256 gmxWithdraw, uint256 price, uint256 linkVal, uint256 usdcVal, uint256 linkPrice, uint256 usdcPrice) internal pure returns (uint256, uint256) {
        uint256 linkAmountUSD = gmxWithdraw.mul(price).div(10e5).mul(linkVal);
        linkAmountUSD = linkAmountUSD.div(linkVal.add(usdcVal));

        uint256 usdcAmountUSD = gmxWithdraw.mul(price).div(10e5).mul(usdcVal);
        usdcAmountUSD = usdcAmountUSD.div(linkVal.add(usdcVal));
        return (linkAmountUSD.mul(10e17).div(linkPrice), usdcAmountUSD.mul(10e5).div(usdcPrice));
    }

    /// @notice Adjusts the supply of GM tokens based on market conditions
    /// @param linkPool Current LINK pool value
    /// @param usdcPool Current USDC pool value
    /// @param totalBorrowingFees Total borrowing fees
    /// @param pnl Profit and loss value
    /// @param impactPoolPrice Impact pool price
    /// @return Adjusted supply based on market conditions
    function getAdjustedSupply(uint256 linkPool, uint256 usdcPool, uint256 totalBorrowingFees, int256 pnl, uint256 impactPoolPrice) pure internal returns (uint256) {
        linkPool = linkPool.div(10e11);
        totalBorrowingFees = totalBorrowingFees.div(10e4);
        impactPoolPrice = impactPoolPrice.mul(10e6);
        uint256 newPNL = pnl > 0 ? uint256(pnl) : uint256(-pnl);
        newPNL = newPNL.div(10e12);
        return linkPool + usdcPool - totalBorrowingFees - newPNL - impactPoolPrice;
    }

    /// @notice Sets the controller address
    /// @param _controller New controller address
    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    /// @notice Transfers tokens from the contract
    /// @param _tokenAddress Address of the token to transfer
    /// @param _to Recipient address
    /// @param _amount Amount of tokens to transfer
    function transferToken(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        require(IERC20(_tokenAddress).transfer(_to, _amount), "Transfer failed");
    }

    /// @notice Fallback function to receive ETH
    receive() external payable {}
}
