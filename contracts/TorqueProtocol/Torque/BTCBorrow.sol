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

    // Allows a user to borrow Torque USD
    function borrow(
        uint supplyAmount,
        uint borrowAmount,
        uint tusdBorrowAmount
    ) public nonReentrant {
        // Get the amount of TUSD the user is allowed to mint for the given asset
        (uint mintable, bool canMint) = ITUSDEngine(engine).getMintableTUSD(
            baseAsset,
            address(this),
            borrowAmount
        );

        // Ensure user is allowed to mint and doesn't exceed mintable limit
        require(canMint, "User can not mint more TUSD");
        require(mintable > tusdBorrowAmount, "Exceeds borrow amount");

        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];

        // Calculate the maximum borrowable amount for the user based on collateral

        uint maxBorrow = getBorrowableUsdc(supplyAmount.add(userBorrowInfo.supplied));

        // Calculate the amount user can still borrow.
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);

        // Ensure the user isn't trying to borrow more than what's allowed
        require(borrowable >= borrowAmount, "Borrow cap exceeded");

        // Transfer the asset from the user to this contract as collateral
        require(
            ERC20(asset).transferFrom(msg.sender, address(this), supplyAmount),
            "Transfer asset failed"
        );

        // If user has borrowed before, calculate accrued interest and reward
        uint accruedInterest = 0;
        uint reward = 0;
        if (userBorrowInfo.borrowed > 0) {
            accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
            reward = RewardUtil(rewardUtil).calculateReward(
                userBorrowInfo.baseBorrowed,
                userBorrowInfo.borrowTime
            );
        }

        // Update the user's borrowing information
        userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.add(tusdBorrowAmount);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(borrowAmount).add(accruedInterest);
        if (reward > 0) {
            userBorrowInfo.reward = userBorrowInfo.reward.add(reward);
        }
        userBorrowInfo.supplied = userBorrowInfo.supplied.add(supplyAmount);
        userBorrowInfo.borrowTime = block.timestamp;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, supplyAmount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(
            comet,
            address(this),
            baseAsset,
            borrowAmount
        );
        callData[1] = withdrawAssetCalldata;

        // Approve Comet to use the asset
        ERC20(asset).approve(comet, supplyAmount);

        // Invoke actions in the Bulker for optimization
        IBulker(bulker).invoke(buildBorrowAction(), callData);
	    
        // Approve the engine to use the base asset
        ERC20(baseAsset).approve(address(engine), borrowAmount);

        // Check the balance of TUSD before the minting operation
        uint tusdBefore = ERC20(tusd).balanceOf(address(this));

        // Mint the TUSD equivalent of the borrowed asset
        ITUSDEngine(engine).depositCollateralAndMintTusd(baseAsset, borrowAmount, tusdBorrowAmount);

        // Ensure the expected TUSD amount was minted
        uint expectedTusd = tusdBefore.add(tusdBorrowAmount);

        require(expectedTusd == ERC20(tusd).balanceOf(address(this)), "Invalid amount");

        require(ERC20(tusd).transfer(msg.sender, tusdBorrowAmount), "Transfer token failed");
        totalBorrow = totalBorrow.add(tusdBorrowAmount);
        totalSupplied = totalSupplied.add(supplyAmount);
    }

    // Allows users to repay their borrowed assets
    function repay(uint tusdRepayAmount) public nonReentrant {
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];

        (uint withdrawUsdcAmountFromEngine, bool burnable) = ITUSDEngine(engine).getBurnableTUSD(
            baseAsset,
            address(this),
            tusdRepayAmount
        );
        require(burnable, "Not burnable");
        require(
            userBorrowInfo.borrowed >= withdrawUsdcAmountFromEngine,
            "Exceeds current borrowed amount"
        );
        require(
            ERC20(tusd).transferFrom(msg.sender, address(this), tusdRepayAmount),
            "Transfer assets failed"
        );

        uint baseAssetBalanceBefore = ERC20(baseAsset).balanceOf(address(this));

        ERC20(tusd).approve(address(engine), tusdRepayAmount);
        ITUSDEngine(engine).redeemCollateralForTusd(
            baseAsset,
            withdrawUsdcAmountFromEngine,
            tusdRepayAmount
        );

        uint baseAssetBalanceExpected = baseAssetBalanceBefore.add(withdrawUsdcAmountFromEngine);
        require(
            baseAssetBalanceExpected == ERC20(baseAsset).balanceOf(address(this)),
            "Invalid USDC claim to Engine"
        );

        uint accruedInterest = calculateInterest(
            userBorrowInfo.borrowed,
            userBorrowInfo.borrowTime
        );
        uint reward = RewardUtil(rewardUtil).calculateReward(
            userBorrowInfo.baseBorrowed,
            userBorrowInfo.borrowTime
        ) + userBorrowInfo.reward;
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(accruedInterest);

        uint repayUsdcAmount = withdrawUsdcAmountFromEngine;
        if(repayUsdcAmount > userBorrowInfo.borrowed) {
            repayUsdcAmount = userBorrowInfo.borrowed;
        }
        uint repayTusd = userBorrowInfo.baseBorrowed.mul(repayUsdcAmount).div(userBorrowInfo.borrowed);
        uint withdrawAssetAmount = userBorrowInfo.supplied.mul(repayUsdcAmount).div(userBorrowInfo.borrowed);


        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(
            comet,
            address(this),
            baseAsset,
            repayUsdcAmount
        );
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(
            comet,
            address(this),
            asset,
            withdrawAssetAmount
        );
        callData[1] = withdrawAssetCalldata;

        ERC20(baseAsset).approve(comet, repayUsdcAmount);
        IBulker(bulker).invoke(buildRepay(), callData);
        
        userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.sub(repayTusd);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.sub(repayUsdcAmount);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAssetAmount);
        userBorrowInfo.borrowTime = block.timestamp;
        userBorrowInfo.reward = 0;
        if (reward > 0) {
            require(
                ERC20(rewardToken).balanceOf(address(this)) >= reward,
                "Insuffient balance to pay reward"
            );
            require(ERC20(rewardToken).transfer(msg.sender, reward), "Transfer reward failed");
        }

        require(ERC20(asset).transfer(msg.sender, withdrawAssetAmount), "Transfer asset from Compound failed");
        totalBorrow = totalBorrow.sub(repayTusd);
        totalSupplied = totalSupplied.sub(withdrawAssetAmount);
    }

    // View function to get the total amount supplied by a user
    function getTotalAmountSupplied(address user) public view returns (uint) {
        BorrowInfo storage userInfo = borrowInfoMap[user];
        return userInfo.supplied;
    }

    // View function to get the total amount borrowed by a user
    function getTotalAmountBorrowed(address user) public view returns (uint) {
        BorrowInfo storage userInfo = borrowInfoMap[user];
        return userInfo.borrowed;
    }
}
