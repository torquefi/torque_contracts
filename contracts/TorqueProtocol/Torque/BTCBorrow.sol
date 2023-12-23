// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./BorrowAbstract.sol";

contract BTCBorrow is BorrowAbstract{
    using SafeMath for uint256;

    function borrow(uint supplyAmount, uint borrowAmount, uint tusdBorrowAmount) public nonReentrant(){
        // Checks
        require(supplyAmount > 0, "Supply amount must be greater than 0");
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        (uint mintable, bool canMint) = ITUSDEngine(engine).getMintableTUSD(baseAsset, msg.sender, borrowAmount);
        require(canMint, "User can not mint more TUSD");
        require(mintable > tusdBorrowAmount, "Exceeds borrowable amount");
        uint maxBorrow = getBorrowableUsdc(supplyAmount.add(userBorrowInfo.supplied));
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= borrowAmount, "Borrow cap exceeded");
        require(
            ERC20(asset).transferFrom(msg.sender, address(this), supplyAmount),
            "Transfer asset failed"
        );
        
        // Effects
        uint accruedInterest = 0;
        uint reward = 0;
        if (userBorrowInfo.borrowed > 0) {
            accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
            reward = RewardUtil(rewardUtil).calculateReward(
                userBorrowInfo.baseBorrowed,
                userBorrowInfo.borrowTime
            );
        }
        userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.add(tusdBorrowAmount);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(borrowAmount).add(accruedInterest);
        if (reward > 0) {
            userBorrowInfo.reward = userBorrowInfo.reward.add(reward);
        }
        userBorrowInfo.supplied = userBorrowInfo.supplied.add(supplyAmount);
        userBorrowInfo.borrowTime = block.timestamp;
        
        // Pre-Interactions
        bytes[] memory callData = new bytes[](2);
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, supplyAmount);
        callData[0] = supplyAssetCalldata;
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmount);
        callData[1] = withdrawAssetCalldata;
        
        // Interactions
        ERC20(asset).approve(comet, supplyAmount);
        IBulker(bulker).invoke(buildBorrowAction(), callData);
        ERC20(baseAsset).approve(address(engine), borrowAmount);
        uint tusdBefore = ERC20(tusd).balanceOf(address(this));
        ITUSDEngine(engine).depositCollateralAndMintTusd(baseAsset, borrowAmount, tusdBorrowAmount, msg.sender);
        
        // Post-Interaction Checks
        uint expectedTusd = tusdBefore.add(tusdBorrowAmount);
        require(expectedTusd == ERC20(tusd).balanceOf(address(this)), "Invalid amount");
        require(ERC20(tusd).transfer(msg.sender, tusdBorrowAmount), "Transfer token failed");
        
        // Final State Update
        totalBorrow = totalBorrow.add(tusdBorrowAmount);
        totalSupplied = totalSupplied.add(supplyAmount);
    }

    function repay(uint tusdRepayAmount) public nonReentrant {
        // Checks
        require(tusdRepayAmount > 0, "Repay amount must be greater than 0");
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        (uint withdrawUsdcAmountFromEngine, bool burnable) = ITUSDEngine(engine).getBurnableTUSD(baseAsset, msg.sender, tusdRepayAmount);
        require(burnable, "Not burnable");
        withdrawUsdcAmountFromEngine = withdrawUsdcAmountFromEngine.mul(100 - repaySlippage).div(100);
        require(userBorrowInfo.borrowed >= withdrawUsdcAmountFromEngine, "Exceeds current borrowed amount");
        require(ERC20(tusd).transferFrom(msg.sender, address(this), tusdRepayAmount), "Transfer assets failed");

        // Pre-Interactions
        uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(accruedInterest);
        uint repayUsdcAmount = min(withdrawUsdcAmountFromEngine, userBorrowInfo.borrowed);

        // Effects
        uint reward = RewardUtil(rewardUtil).calculateReward(userBorrowInfo.baseBorrowed, userBorrowInfo.borrowTime) + userBorrowInfo.reward;
        uint repayTusd = userBorrowInfo.baseBorrowed.mul(repayUsdcAmount).div(userBorrowInfo.borrowed);
        uint withdrawAssetAmount = userBorrowInfo.supplied.mul(repayUsdcAmount).div(userBorrowInfo.borrowed);
        userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.sub(repayTusd);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAssetAmount);
        userBorrowInfo.borrowTime = block.timestamp;
        userBorrowInfo.reward = 0;

        // Preparing for Interactions
        bytes[] memory callData = new bytes[](2);
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), baseAsset, repayUsdcAmount);
        callData[0] = supplyAssetCalldata;
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), withdrawAssetAmount);
        callData[1] = withdrawAssetCalldata;

        // Interactions
        ERC20(baseAsset).approve(comet, repayUsdcAmount);
        IBulker(bulker).invoke(buildRepay(), callData);
        ERC20(tusd).approve(address(engine), tusdRepayAmount);
        ITUSDEngine(engine).redeemCollateralForTusd(baseAsset, withdrawUsdcAmountFromEngine, tusdRepayAmount, msg.sender);

        // Post-Interaction Checks
        uint baseAssetBalanceExpected = ERC20(baseAsset).balanceOf(address(this)).add(withdrawUsdcAmountFromEngine);
        require(baseAssetBalanceExpected == ERC20(baseAsset).balanceOf(address(this)), "Invalid USDC claim to Engine");

        // Transfer rewards and assets
        if (reward > 0) {
            require(ERC20(rewardToken).balanceOf(address(this)) >= reward, "Insufficient balance to pay reward");
            require(ERC20(rewardToken).transfer(msg.sender, reward), "Transfer reward failed");
        }
        require(ERC20(asset).transfer(msg.sender, withdrawAssetAmount), "Transfer asset from Compound failed");

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
}
