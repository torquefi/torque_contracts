// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./SimpleBorrowAbstractUSDT.sol";

contract SimpleBTCBorrowUSDT is SimpleBorrowAbstractUSDT {
    using SafeMath for uint256;
    bool firstTimeFlag = true;

    event Borrow(uint supplyAmount, uint borrowAmountUSDT);
    event Repay(uint usdtRepay, uint256 WbtcWithdraw);

    constructor(
        address _initialOwner,
        address _comet, 
        address _cometReward, 
        address _asset, 
        address _baseAsset, 
        address _bulker,  
        address _treasury, 
        address _controller,
        uint _repaySlippage
    ) SimpleBorrowAbstractUSDT(
        _initialOwner,
        _comet,
        _cometReward,
        _asset,
        _baseAsset,
        _bulker,
        _treasury,
        _controller,
        _repaySlippage
    ) Ownable(msg.sender) {}

    function borrow(address _address, uint supplyAmount, uint borrowAmountUSDT) public nonReentrant() {
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

        borrowed = borrowed.add(borrowAmountUSDT).add(accruedInterest);
        borrowHealth += borrowAmountUSDT;
        supplied = supplied.add(supplyAmount);
        borrowTime = block.timestamp;
        
        // Pre-Interactions
        bytes[] memory callData = new bytes[](2);
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, supplyAmount);
        callData[0] = supplyAssetCalldata;
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmountUSDT);
        callData[1] = withdrawAssetCalldata;
        
        // Interactions
        IERC20(asset).approve(comet, supplyAmount);
        IBulker(bulker).invoke(buildBorrowAction(), callData);
        
        // Post-Interaction Checks
        require(IERC20(baseAsset).transfer(_address, borrowAmountUSDT), "Transfer token failed");

        emit Borrow(supplyAmount, borrowAmountUSDT);
    }

    function repay(address _address, uint usdtRepay, uint256 WbtcWithdraw) public nonReentrant() {
        require(msg.sender == controller, "Cannot be called directly");
        
        // Checks
        require(usdtRepay > 0, "Repay amount must be greater than 0");

        // Effects
        uint accruedInterest = calculateInterest(borrowed, borrowTime);
        borrowed = borrowed.add(accruedInterest);
        
        uint withdrawAssetAmount = supplied.mul(usdtRepay).div(borrowed); 
        
        require(WbtcWithdraw <= withdrawAssetAmount, "Cannot withdraw this much WBTC");

        supplied = supplied.sub(WbtcWithdraw);
        borrowed = borrowed.sub(usdtRepay);
        borrowHealth -= usdtRepay;
        borrowTime = block.timestamp;

        // Interactions
        require(IERC20(baseAsset).transferFrom(_address, address(this), usdtRepay), "Transfer Failed!");
        
        // Interactions
        bytes[] memory callData = new bytes[](2);
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), baseAsset, usdtRepay);
        callData[0] = supplyAssetCalldata;
        if(WbtcWithdraw!=0){
            bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, WbtcWithdraw);
            callData[1] = withdrawAssetCalldata;
        }
        
        IERC20(baseAsset).approve(comet, usdtRepay);
        if(WbtcWithdraw==0){
            IBulker(bulker).invoke(buildRepayBorrow(),callData);
        }else{
            IBulker(bulker).invoke(buildRepay(), callData);
        }
        
        // Transfer Assets
        if(WbtcWithdraw!=0){
            require(IERC20(asset).transfer(_address, WbtcWithdraw), "Transfer asset from Compound failed");
        }

        emit Repay(usdtRepay, WbtcWithdraw);
    }

    function borrowMore(address _address, uint256 borrowAmountUSDT) external {
        require(msg.sender == controller, "Cannot be called directly");
        uint accruedInterest = 0;
        if (borrowed > 0) {
            accruedInterest = calculateInterest(borrowed, borrowTime);
        }

        borrowed = borrowed.add(borrowAmountUSDT).add(accruedInterest);
        borrowHealth += borrowAmountUSDT;

        // Pre-Interactions
        bytes[] memory callData = new bytes[](1);
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmountUSDT);
        callData[0] = withdrawAssetCalldata;
        
        // Interactions
        IBulker(bulker).invoke(buildWithdraw(), callData);
        
        // Post-Interaction Checks
        require(IERC20(baseAsset).transfer(_address, borrowAmountUSDT), "Transfer token failed");

        emit Borrow(0, borrowAmountUSDT);
    }

    function getWbtcWithdrawWithSlippage(uint256 repayUsdtAmount, uint256 _repaySlippage) public view returns (uint256) {
        uint256 withdrawAssetAmount = supplied.mul(repayUsdtAmount).div(borrowed);
        return withdrawAssetAmount.mul(100-_repaySlippage).div(100);
    }

    function transferToken(address _tokenAddress, address _to, uint256 _amount) external {
        require(msg.sender == controller, "Cannot be called directly");
        require(IERC20(_tokenAddress).transfer(_to,_amount));
    }
}
