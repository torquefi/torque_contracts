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
    // Approve the contract of WBTC usage
    function borrow(uint supplyAmount, uint borrowAmountUSDC, uint tUSDBorrowAmount) public nonReentrant(){
        require(supplyAmount > 0, "Supply amount must be greater than 0");
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint maxBorrowUSDC = getBorrowableUsdc(supplyAmount.add(userBorrowInfo.supplied));
        uint256 mintable = getMintableToken(maxBorrowUSDC, userBorrowInfo.baseBorrowed, tUSDBorrowAmount); // Returns how much more USDT that can be minted
        require(mintable >= tUSDBorrowAmount, "Exceeds borrowable amount");
        uint borrowable = maxBorrowUSDC.sub(userBorrowInfo.borrowed);
        require(borrowable >= borrowAmountUSDC, "Borrow cap exceeded");
        require(
            IERC20(asset).transferFrom(msg.sender, address(this), supplyAmount),
            "Transfer asset failed"
        );

        // Effects
        uint accruedInterest = 0;
        if (userBorrowInfo.borrowed > 0) {
            accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
        }
        userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.add(tUSDBorrowAmount);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(borrowAmountUSDC).add(accruedInterest);
        userBorrowInfo.supplied = userBorrowInfo.supplied.add(supplyAmount);
        userBorrowInfo.borrowTime = block.timestamp;
        
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
        require(IERC20(tusd).transfer(msg.sender, tUSDBorrowAmount), "Transfer token failed");
        
        // Final State Update
        totalBorrow = totalBorrow.add(tUSDBorrowAmount);
        totalSupplied = totalSupplied.add(supplyAmount);
    }

    function repay(uint tusdRepayAmount, uint256 withdrawBTC) public nonReentrant {
        // Checks
        require(tusdRepayAmount > 0, "Repay amount must be greater than 0");
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint256 withdrawUsdcAmountFromEngine = getBurnableToken(tusdRepayAmount, userBorrowInfo.baseBorrowed, userBorrowInfo.borrowed); // PS CHECK 
        require(userBorrowInfo.borrowed >= withdrawUsdcAmountFromEngine, "Exceeds current borrowed amount");
        require(IERC20(tusd).transferFrom(msg.sender, address(this), tusdRepayAmount), "Transfer assets failed");

        // Effects
        uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(accruedInterest);
        uint repayUsdcAmount = min(withdrawUsdcAmountFromEngine, userBorrowInfo.borrowed); // 1USD
        uint repayTusd = userBorrowInfo.baseBorrowed.mul(repayUsdcAmount).div(userBorrowInfo.borrowed); // .97
        uint withdrawAssetAmount = userBorrowInfo.supplied.mul(repayUsdcAmount).div(userBorrowInfo.borrowed); // Borrowed + intereset = 1.0103 & withdraw is 4949.02
        require(withdrawBTC <= withdrawAssetAmount, "Cannot withdraw this much WBTC");
        userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.sub(repayTusd);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawBTC);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.sub(repayUsdcAmount);
        userBorrowInfo.borrowTime = block.timestamp;

        // Record Balance
        uint baseAssetBalanceBefore = IERC20(baseAsset).balanceOf(address(this));

        // Interactions
        IERC20(tusd).approve(address(engine), tusdRepayAmount);
        ITUSDEngine(engine).redeemCollateralForTusd(withdrawUsdcAmountFromEngine, tusdRepayAmount);// 1USD for 0.98 TUSD

        // Post-Interaction Checks
        uint baseAssetBalanceExpected = baseAssetBalanceBefore.add(withdrawUsdcAmountFromEngine);
        require(baseAssetBalanceExpected == IERC20(baseAsset).balanceOf(address(this)), "Invalid USDC claim to Engine");

        // Pre-Interactions
        bytes[] memory callData = new bytes[](2);
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), baseAsset, repayUsdcAmount);
        callData[0] = supplyAssetCalldata;
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, withdrawBTC);
        callData[1] = withdrawAssetCalldata;
        
        IERC20(baseAsset).approve(comet, repayUsdcAmount);
        IBulker(bulker).invoke(buildRepay(), callData);

        // Transfer Assets
        // Add slippage
        require(IERC20(asset).transfer(msg.sender, withdrawBTC), "Transfer asset from Compound failed");

        // Final State Update
        totalBorrow = totalBorrow.sub(repayTusd);
        totalSupplied = totalSupplied.sub(withdrawBTC);
    }

    function mintableTUSD(uint supplyAmount) external view returns (uint) {
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint maxBorrowUSDC = getBorrowableUsdc(supplyAmount.add(userBorrowInfo.supplied));
        uint256 mintable = getMintableToken(maxBorrowUSDC, userBorrowInfo.baseBorrowed, 0);
        return mintable;
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
