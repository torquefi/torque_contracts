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
contract ETHBorrow is BorrowAbstract {
    using SafeMath for uint256;

     // Allows a user to borrow Torque USD
    function borrow(uint borrowAmount, uint usdBorrowAmount) public payable nonReentrant(){
        // Get the amount of USD the user is allowed to mint for the given asset
	(uint mintable, bool canMint) = IUSDEngine(engine).getMintableUSD(baseAsset, address(this), borrowAmount);
        // Ensure user is allowed to mint and doesn't exceed mintable limit
	require(canMint, 'User can not mint more USD');
        require(mintable > usdBorrowAmount, "Exceeds borrow amount");

        uint supplyAmount = msg.value;
        IComet icomet = IComet(comet);

        // Fetch the asset information and its price.
        AssetInfo memory info = icomet.getAssetInfoByAddress(asset);
        uint price = icomet.getPrice(info.priceFeed);
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        
        // Calculate the maximum borrowable amount for the user based on collateral
        uint maxBorrow = (supplyAmount.add(userBorrowInfo.supplied)).mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);

        // Calculate the amount user can still borrow.
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        
        // Ensure the user isn't trying to borrow more than what's allowed
        require(borrowable >= borrowAmount, "Borrow cap exceeded");
        
        // Transfer the asset from the user to this contract as collateral
        require(ERC20(asset).transferFrom(msg.sender, address(this), supplyAmount), "Transfer asset failed");

        // If user has borrowed before, calculate accrued interest and reward
        uint accruedInterest = 0;
        uint reward = 0 ;
        if(userBorrowInfo.borrowed > 0) {
            accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
            reward = RewardUtil(rewardUtil).calculateReward(userBorrowInfo.baseBorrowed, userBorrowInfo.borrowTime);
        }

        // Update the user's borrowing information
        userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.add(borrowAmount);
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(borrowAmount).add(accruedInterest);
        if(reward > 0) {
            userBorrowInfo.reward = userBorrowInfo.reward.add(reward);
        }
        userBorrowInfo.supplied = userBorrowInfo.supplied.add(supplyAmount);
        userBorrowInfo.borrowTime = block.timestamp;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), supplyAmount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmount);
        callData[1] = withdrawAssetCalldata;

        // Invoke actions in the Bulker for optimization
        IBulker(bulker).invoke{value: supplyAmount}(buildBorrowAction(), callData);

        ERC20(baseAsset).approve(address(engine), borrowAmount);

        // Check the balance of USD before the minting operation
        uint usdBefore = ERC20(usd).balanceOf(address(this));

        // Mint the USD equivalent of the borrowed asset
        IUSDEngine(engine).depositCollateralAndMintUsd{value:0}(baseAsset, borrowAmount, usdBorrowAmount);

        // Ensure the expected USD amount was minted
        uint expectedUsd = usdBefore.add(usdBorrowAmount);
        require(expectedUsd == ERC20(usd).balanceOf(address(this)), "Invalid amount");

        require(ERC20(usd).transfer(msg.sender, usdBorrowAmount), "Transfer token failed");
    }

    // Allows users to repay their borrowed assets
    function repay(uint usdRepayAmount) public nonReentrant(){

        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];

        (uint withdrawUsdcAmountFromEngine, bool burnable) = IUSDEngine(engine).getBurnableUSD(baseAsset, address(this), usdRepayAmount);
        require(burnable, "Not burnable");
        require(userBorrowInfo.borrowed >= withdrawUsdcAmountFromEngine, "Exceeds current borrowed amount");
        require(ERC20(usd).transferFrom(msg.sender,address(this), usdRepayAmount), "Transfer asset failed");

        uint baseAssetBalanceBefore = ERC20(baseAsset).balanceOf(address(this));

        ERC20(usd).approve(address(engine), usdRepayAmount);

        IUSDEngine(engine).redeemCollateralForUsd(baseAsset, withdrawUsdcAmountFromEngine, usdRepayAmount);

        uint baseAssetBalanceExpected = baseAssetBalanceBefore.add(withdrawUsdcAmountFromEngine);
        require(baseAssetBalanceExpected == ERC20(baseAsset).balanceOf(address(this)), "Invalid USDC claim to Engine");

        uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
        uint reward = RewardUtil(rewardUtil).calculateReward(userBorrowInfo.baseBorrowed, userBorrowInfo.borrowTime) + userBorrowInfo.reward;
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(accruedInterest);

        uint withdrawAssetAmount = userBorrowInfo.supplied.mul(withdrawUsdcAmountFromEngine).div(userBorrowInfo.borrowed);

        uint repayUsdcAmount = withdrawUsdcAmountFromEngine;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), baseAsset, repayUsdcAmount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), withdrawAssetAmount);
        callData[1] = withdrawAssetCalldata;

        ERC20(baseAsset).approve(comet, repayUsdcAmount);
        IBulker(bulker).invoke(buildRepay(), callData);

        if(userBorrowInfo.baseBorrowed < withdrawUsdcAmountFromEngine) {
            userBorrowInfo.baseBorrowed = 0;
        } else {
            userBorrowInfo.baseBorrowed = userBorrowInfo.baseBorrowed.sub(withdrawUsdcAmountFromEngine);
        }
        userBorrowInfo.borrowed = userBorrowInfo.borrowed.sub(withdrawUsdcAmountFromEngine);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(withdrawAssetAmount);
        userBorrowInfo.borrowTime = block.timestamp;
        userBorrowInfo.reward = 0;
        if(reward > 0) {
            require(ERC20(rewardToken).balanceOf(address(this)) >= reward, "Insuffient balance to pay reward");
            require(ERC20(rewardToken).transfer(msg.sender, reward), "Transfer reward failed");
        }


        (bool success, ) = msg.sender.call{ value: withdrawAssetAmount }("");
        require(success, "Transfer ETH failed");
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