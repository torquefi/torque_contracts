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

    function borrow(uint borrowAmount, uint tusdBorrowAmount) public payable nonReentrant() {
        // Checks
        require(msg.value > 0, "Supply amount must be greater than 0");
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint supplyAmount = msg.value;
        uint maxBorrow = getBorrowableUsdc(supplyAmount.add(userBorrowInfo.supplied));
        (uint mintable, bool canMint) = ITUSDEngine(engine).getMintableTUSD(msg.sender, maxBorrow);
        require(canMint, "User can not mint more TUSD");
        require(mintable > tusdBorrowAmount, "Exceeds borrow amount");
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= borrowAmount, "Borrow cap exceeded");

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
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), supplyAmount);
        callData[0] = supplyAssetCalldata;
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmount);
        callData[1] = withdrawAssetCalldata;

        // Interactions
        IBulker(bulker).invoke{ value: supplyAmount }(buildBorrowAction(), callData);
        IERC20(baseAsset).approve(address(engine), borrowAmount);
        ITUSDEngine(engine).depositCollateralAndMintTusd{value:0}(baseAsset, borrowAmount, tusdBorrowAmount, msg.sender);

        // Post-Interaction Checks
        uint expectedTusd = IERC20(tusd).balanceOf(address(this)).add(tusdBorrowAmount);
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
        (uint withdrawUsdcAmountFromEngine, bool burnable) = ITUSDEngine(engine).getBurnableTUSD(msg.sender, tusdRepayAmount);
        require(burnable, "Not burnable");
        withdrawUsdcAmountFromEngine = withdrawUsdcAmountFromEngine.mul(100 - repaySlippage).div(100);
        require(userBorrowInfo.borrowed >= withdrawUsdcAmountFromEngine, "Exceeds current borrowed amount");
        require(IERC20(tusd).transferFrom(msg.sender, address(this), tusdRepayAmount), "Transfer asset failed");

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
        (bool success, ) = msg.sender.call{ value: withdrawAssetAmount }("");
        require(success, "Transfer ETH failed");

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

    function buildBorrowAction() pure override public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);
        actions[0] = ACTION_SUPPLY_ETH;
        actions[1] = ACTION_WITHDRAW_ASSET;
        return actions;
    }
    function buildRepay() pure override public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ETH;
        return actions;
    }

    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }
}
