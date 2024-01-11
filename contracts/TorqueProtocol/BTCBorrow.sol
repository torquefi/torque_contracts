// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./BorrowAbstract.sol";

contract BTCBorrow is BorrowAbstract {
    using SafeMath for uint256;

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
        _repaySlippage
    ) {}

    function borrow(uint supplyAmount, uint borrowAmount, uint tusdBorrowAmount) public nonReentrant(){
        // Checks
        require(supplyAmount > 0, "Supply amount must be greater than 0");
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint maxBorrow = getBorrowableUsdc(supplyAmount.add(userBorrowInfo.supplied));
        (uint mintable, bool canMint) = ITUSDEngine(engine).getMintableTUSD(msg.sender, maxBorrow);
        require(canMint, "User can not mint more TUSD");
        require(mintable > tusdBorrowAmount, "Exceeds borrowable amount");
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= borrowAmount, "Borrow cap exceeded");
        require(
            IERC20(asset).transferFrom(msg.sender, address(this), supplyAmount),
            "Transfer asset failed"
        );

        // Effects
        uint accruedInterest = 0;
        if (userBorrowInfo.borrowed > 0) {
            accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
        }
        userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.add(tusdBorrowAmount);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(borrowAmount).add(accruedInterest);
        userBorrowInfo.supplied = userBorrowInfo.supplied.add(supplyAmount);
        userBorrowInfo.borrowTime = block.timestamp;
        
        // Pre-Interactions
        bytes[] memory callData = new bytes[](2);
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, supplyAmount);
        callData[0] = supplyAssetCalldata;
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmount);
        callData[1] = withdrawAssetCalldata;
        
        // Interactions
        IERC20(asset).approve(comet, supplyAmount);
        IBulker(bulker).invoke(buildBorrowAction(), callData);
        IERC20(baseAsset).approve(address(engine), borrowAmount);
        uint tusdBefore = IERC20(tusd).balanceOf(address(this));
        ITUSDEngine(engine).depositCollateralAndMintTusd(baseAsset, borrowAmount, tusdBorrowAmount, msg.sender);
        
        // Post-Interaction Checks
        uint expectedTusd = tusdBefore.add(tusdBorrowAmount);
        require(expectedTusd == IERC20(tusd).balanceOf(address(this)), "Invalid amount");
        require(IERC20(tusd).transfer(msg.sender, tusdBorrowAmount), "Transfer token failed");
        
        // Final State Update
        totalBorrow = totalBorrow.add(tusdBorrowAmount);
        totalSupplied = totalSupplied.add(supplyAmount);
    }

    function repay(uint tusdRepayAmount) public nonReentrant {
        // Checks
        require(tusdRepayAmount > 0, "Repay amount must be greater than 0");
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        (uint256 withdrawUsdcAmountFromEngine, bool burnable) = ITUSDEngine(engine).getBurnableTUSD(msg.sender, tusdRepayAmount);
        require(burnable, "Not burnable");
        withdrawUsdcAmountFromEngine = withdrawUsdcAmountFromEngine.mul(100 - repaySlippage).div(100);
        require(userBorrowInfo.borrowed >= withdrawUsdcAmountFromEngine, "Exceeds current borrowed amount");
        require(IERC20(tusd).transferFrom(msg.sender, address(this), tusdRepayAmount), "Transfer assets failed");

        // Effects
        uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(accruedInterest);
        uint repayUsdcAmount = min(withdrawUsdcAmountFromEngine, userBorrowInfo.borrowed);
        uint repayTusd = userBorrowInfo.baseBorrowed.mul(repayUsdcAmount).div(userBorrowInfo.borrowed);
        uint withdrawAssetAmount = userBorrowInfo.supplied.mul(repayUsdcAmount).div(userBorrowInfo.borrowed);
        userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.sub(repayTusd);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAssetAmount);
        userBorrowInfo.borrowTime = block.timestamp;

        // Pre-Interactions
        bytes[] memory callData = new bytes[](2);
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), baseAsset, repayUsdcAmount);
        callData[0] = supplyAssetCalldata;
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), withdrawAssetAmount);
        callData[1] = withdrawAssetCalldata;

        // Record Balance
        uint baseAssetBalanceBefore = IERC20(baseAsset).balanceOf(address(this));

        // Interactions
        IERC20(baseAsset).approve(comet, repayUsdcAmount);
        IBulker(bulker).invoke(buildRepay(), callData);
        IERC20(tusd).approve(address(engine), tusdRepayAmount);
        ITUSDEngine(engine).redeemCollateralForTusd(baseAsset, withdrawUsdcAmountFromEngine, tusdRepayAmount, msg.sender);

        // Post-Interaction Checks
        uint baseAssetBalanceExpected = baseAssetBalanceBefore.add(withdrawUsdcAmountFromEngine);
        require(baseAssetBalanceExpected == IERC20(baseAsset).balanceOf(address(this)), "Invalid USDC claim to Engine");

        // Transfer Assets
        require(IERC20(asset).transfer(msg.sender, withdrawAssetAmount), "Transfer asset from Compound failed");

        // Final State Update
        totalBorrow = totalBorrow.sub(repayTusd);
        totalSupplied = totalSupplied.sub(withdrawAssetAmount);
    }

    function getTotalAmountSupplied(address user) public view returns (uint) {
        BorrowInfo storage userInfo = borrowInfoMap[user];
        return userInfo.supplied;
    }

    function getTotalAmountBorrowed(address user) public view returns (uint) {
        BorrowInfo storage userInfo = borrowInfoMap[user];
        return userInfo.borrowed;
    }

    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }
}
