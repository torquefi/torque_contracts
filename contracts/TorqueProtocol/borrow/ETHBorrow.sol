// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./BorrowAbstract.sol";

contract ETHBorrow is BorrowAbstract {
    using SafeMath for uint256;
    bool firstTimeFlag = true;

    event Borrow(uint supplyAmount, uint borrowAmountUSDC, uint tUSDBorrowAmount); // Event emitted when borrowing
    event Repay(uint tusdRepayAmount, uint256 WethWithdraw); // Event emitted when repaying
    event MintTUSD(uint256 _amount); // Event emitted when minting TUSD

    constructor(
        address _initialOwner,
        address _comet, 
        address _cometReward, 
        address _asset, 
        address _baseAsset, 
        address _bulker, 
        address _engine, 
        address _tusd, 
        address _treasury, 
        address _controller,
        uint _repaySlippage
    ) BorrowAbstract(
        _initialOwner,
        _comet,
        _cometReward,
        _asset,
        _baseAsset,
        _bulker,
        _engine,
        _tusd,
        _treasury,
        _controller,
        _repaySlippage
    ) Ownable(msg.sender) {}

    /**
     * @notice Borrow assets against supplied collateral.
     * @param _address Address of the user.
     * @param supplyAmount Amount of collateral supplied.
     * @param borrowAmountUSDC Amount of USDC to borrow.
     * @param tUSDBorrowAmount Amount of TUSD to borrow.
     */
    function borrow(address _address, uint supplyAmount, uint borrowAmountUSDC, uint tUSDBorrowAmount) public nonReentrant() {
        require(msg.sender == controller, "Cannot be called directly");
        require(supplyAmount > 0, "Supply amount must be greater than 0");
        if(firstTimeFlag){
            require(
                IERC20(asset).transferFrom(msg.sender, address(this), supplyAmount),
                "Transfer asset failed"
            );
            firstTimeFlag = false;
        }
        else{
            require(
                IERC20(asset).transferFrom(_address, address(this), supplyAmount),
                "Transfer asset failed"
            );
        }

        // Effects
        uint accruedInterest = 0;
        if (borrowed > 0) {
            accruedInterest = calculateInterest(borrowed, borrowTime);
        }
        baseBorrowed = baseBorrowed.add(tUSDBorrowAmount);
        borrowed = borrowed.add(borrowAmountUSDC).add(accruedInterest);
        borrowHealth += borrowAmountUSDC;
        supplied = supplied.add(supplyAmount);
        borrowTime = block.timestamp;
        
        // Pre-Interactions
        bytes[] memory callData = new bytes[](2);
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, supplyAmount);
        callData[0] = supplyAssetCalldata;
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmountUSDC);
        callData[1] = withdrawAssetCalldata;
        
        // Interactions
        IERC20(asset).approve(comet, supplyAmount);
        IBulker(bulker).invoke(buildBorrowAction(), callData);
        IERC20(baseAsset).approve(address(engine), borrowAmountUSDC);
        uint tusdBefore = IERC20(tusd).balanceOf(address(this));
        ITUSDEngine(engine).depositCollateralAndMintTusd(borrowAmountUSDC, tUSDBorrowAmount);
        
        // Post-Interaction Checks
        uint expectedTusd = tusdBefore.add(tUSDBorrowAmount);
        require(expectedTusd == IERC20(tusd).balanceOf(address(this)), "Invalid amount");
        require(IERC20(tusd).transfer(_address, tUSDBorrowAmount), "Transfer token failed");

        emit Borrow(supplyAmount, borrowAmountUSDC, tUSDBorrowAmount);
    }

    /**
     * @notice Repay borrowed assets and withdraw collateral.
     * @param _address Address of the user.
     * @param tusdRepayAmount Amount of TUSD to repay.
     * @param WETHWithdraw Amount of WETH to withdraw.
     */
    function repay(address _address, uint tusdRepayAmount, uint256 WETHWithdraw) public nonReentrant() {
        require(msg.sender == controller, "Cannot be called directly");
        // Checks
        require(tusdRepayAmount > 0, "Repay amount must be greater than 0");
        uint256 withdrawUsdcAmountFromEngine = getBurnableToken(tusdRepayAmount, baseBorrowed, borrowed);
        require(borrowed >= withdrawUsdcAmountFromEngine, "Exceeds current borrowed amount");
        require(IERC20(tusd).transferFrom(_address, address(this), tusdRepayAmount), "Transfer assets failed");

        // Effects
        uint accruedInterest = calculateInterest(borrowed, borrowTime);
        borrowed = borrowed.add(accruedInterest);
        uint repayUsdcAmount = min(withdrawUsdcAmountFromEngine, borrowed);  
        uint withdrawAssetAmount = supplied.mul(repayUsdcAmount).div(borrowed); 
        require(WETHWithdraw <= withdrawAssetAmount, "Cannot withdraw this much WETH");
        baseBorrowed = baseBorrowed.sub(tusdRepayAmount);
        supplied = supplied.sub(WETHWithdraw);
        borrowed = borrowed.sub(repayUsdcAmount);
        borrowHealth -= repayUsdcAmount;
        borrowTime = block.timestamp;

        // Record Balance
        uint baseAssetBalanceBefore = IERC20(baseAsset).balanceOf(address(this));

        // Interactions
        IERC20(tusd).approve(address(engine), tusdRepayAmount);
        ITUSDEngine(engine).redeemCollateralForTusd(withdrawUsdcAmountFromEngine, tusdRepayAmount);

        // Post-Interaction Checks
        uint baseAssetBalanceExpected = baseAssetBalanceBefore.add(withdrawUsdcAmountFromEngine);
        require(baseAssetBalanceExpected == IERC20(baseAsset).balanceOf(address(this)), "Invalid USDC claim to Engine");

        // Interactions
        bytes[] memory callData = new bytes[](2);
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), baseAsset, repayUsdcAmount);
        callData[0] = supplyAssetCalldata;
        if(WETHWithdraw!=0){
            bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, WETHWithdraw);
            callData[1] = withdrawAssetCalldata;
        }
        
        IERC20(baseAsset).approve(comet, repayUsdcAmount);
        if(WETHWithdraw==0){
            IBulker(bulker).invoke(buildRepayBorrow(),callData);
        }else{
            IBulker(bulker).invoke(buildRepay(), callData);
        }

        // Transfer Assets
        if(WETHWithdraw!=0){
            require(IERC20(asset).transfer(_address, WETHWithdraw), "Transfer asset from Compound failed");
        }

        emit Repay(tusdRepayAmount, WETHWithdraw);
    }

    /**
     * @notice Calculate the mintable amount of TUSD based on the supply amount.
     * @param supplyAmount Amount of collateral supplied.
     * @return The mintable amount of TUSD.
     */
    function mintableTUSD(uint supplyAmount) external view returns (uint) {
        uint maxBorrowUSDC = getBorrowableUsdc(supplyAmount.add(supplied));
        uint256 mintable = getMintableToken(maxBorrowUSDC, baseBorrowed, 0);
        return mintable;
    }

    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }

    /**
     * @notice Calculate the amount of WETH that can be withdrawn based on TUSD repayment amount.
     * @param tusdRepayAmount Amount of TUSD to repay.
     * @return The amount of WETH that can be withdrawn.
     */
    function getWETHWithdraw(uint256 tusdRepayAmount) public view returns (uint256) {
        require(tusdRepayAmount > 0, "Repay amount must be greater than 0");
        uint256 withdrawUsdcAmountFromEngine = getBurnableToken(tusdRepayAmount, baseBorrowed, borrowed);
        uint accruedInterest = calculateInterest(borrowed, borrowTime);
        uint256 totalBorrowed = borrowed.add(accruedInterest);
        uint repayUsdcAmount = min(withdrawUsdcAmountFromEngine, totalBorrowed);
        uint256 withdrawAssetAmount = supplied.mul(repayUsdcAmount).div(borrowed);
        return withdrawAssetAmount;
    }

    /**
     * @notice Calculate the amount of WETH that can be withdrawn with slippage consideration.
     * @param tusdRepayAmount Amount of TUSD to repay.
     * @param _repaySlippage Slippage percentage to consider.
     * @return The amount of WETH that can be withdrawn with slippage.
     */
    function getWETHWithdrawWithSlippage(uint256 tusdRepayAmount, uint256 _repaySlippage) public view returns (uint256) {
        require(tusdRepayAmount > 0, "Repay amount must be greater than 0");
        uint256 withdrawUsdcAmountFromEngine = getBurnableToken(tusdRepayAmount, baseBorrowed, borrowed);
        uint accruedInterest = calculateInterest(borrowed, borrowTime);
        uint256 totalBorrowed = borrowed.add(accruedInterest);
        uint repayUsdcAmount = min(withdrawUsdcAmountFromEngine, totalBorrowed);
        uint256 withdrawAssetAmount = supplied.mul(repayUsdcAmount).div(borrowed);
        return withdrawAssetAmount.mul(100-_repaySlippage).div(100);
    }

    /**
     * @notice Mint TUSD for the specified user.
     * @param _address Address of the user.
     * @param _amountToMint Amount of TUSD to mint.
     */
    function mintTUSD(address _address, uint256 _amountToMint) public nonReentrant() {
        uint256 mintTUSDTotal = baseBorrowed + _amountToMint;
        uint256 borrowedAmount = borrowHealth;
        borrowedAmount =  borrowedAmount.mul(decimalAdjust)
            .mul(LIQUIDATION_PRECISION)
            .div(LIQUIDATION_THRESHOLD);
        require(borrowedAmount >= mintTUSDTotal, "Health factor is broken");
        baseBorrowed += _amountToMint;

        uint tusdBefore = IERC20(tusd).balanceOf(address(this));
        
        ITUSDEngine(engine).mintTusd(_amountToMint);

        // Post-Interaction Checks
        uint expectedTusd = tusdBefore.add(_amountToMint);
        require(expectedTusd == IERC20(tusd).balanceOf(address(this)), "Invalid amount");
        require(IERC20(tusd).transfer(_address, _amountToMint), "Transfer token failed");

        emit MintTUSD(_amountToMint);
    }

    /**
     * @notice Calculate the maximum additional amount of TUSD that can be minted.
     * @return The maximum mintable amount of TUSD.
     */
    function maxMoreMintable() public view returns (uint256) {
        uint256 borrowedTUSD = baseBorrowed;
        uint256 borrowedAmount = borrowHealth;
        borrowedAmount =  borrowedAmount.mul(decimalAdjust)
            .mul(LIQUIDATION_PRECISION)
            .div(LIQUIDATION_THRESHOLD);
        return borrowedAmount - borrowedTUSD;
    }

    /**
     * @notice Transfer a specified amount of tokens to a given address.
     * @param _tokenAddress Address of the token to transfer.
     * @param _to Address to receive the tokens.
     * @param _amount Amount of tokens to transfer.
     */
    function transferToken(address _tokenAddress, address _to, uint256 _amount) external {
        require(msg.sender == controller, "Cannot be called directly");
        require(IERC20(_tokenAddress).transfer(_to,_amount));
    }
}
