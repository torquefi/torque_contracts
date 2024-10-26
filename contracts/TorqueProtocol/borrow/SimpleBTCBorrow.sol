// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./SimpleBorrowAbstract.sol";

contract SimpleBTCBorrow is SimpleBorrowAbstract {
    using SafeMath for uint256;
    bool firstTimeFlag = true;

    event Borrow(uint supplyAmount, uint borrowAmountUSDC);
    event Repay(uint usdcRepay, uint256 WbtcWithdraw);

    /**
     * @notice Initializes the contract with required parameters.
     * @param _initialOwner The address of the initial owner.
     * @param _comet Address for Compound V3.
     * @param _cometReward Address for claiming Comet rewards.
     * @param _asset Address for collateral to be staked (WBTC/WETH).
     * @param _baseAsset Address for the borrowing asset (USDC).
     * @param _bulker Address for the Bulker contract.
     * @param _treasury Address for the fees.
     * @param _controller Address for the controller.
     * @param _repaySlippage Slippage percentage for repayments.
     */
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
    ) SimpleBorrowAbstract(
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

    /**
     * @notice Allows users to borrow USDC against supplied collateral.
     * @param _address The address to receive the borrowed USDC.
     * @param supplyAmount The amount of collateral supplied.
     * @param borrowAmountUSDC The amount of USDC to borrow.
     */
    function borrow(address _address, uint supplyAmount, uint borrowAmountUSDC) public nonReentrant() {
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

        borrowed = borrowed.add(borrowAmountUSDC).add(accruedInterest);
        borrowHealth += borrowAmountUSDC;
        supplied = supplied.add(supplyAmount);
        borrowTime = block.timestamp;
        
        // Pre-Interactions
        bytes;
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, supplyAmount);
        callData[0] = supplyAssetCalldata;
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmountUSDC);
        callData[1] = withdrawAssetCalldata;
        
        // Interactions
        IERC20(asset).approve(comet, supplyAmount);
        IBulker(bulker).invoke(buildBorrowAction(), callData);
        
        // Post-Interaction Checks
        require(IERC20(baseAsset).transfer(_address, borrowAmountUSDC), "Transfer token failed");

        emit Borrow(supplyAmount, borrowAmountUSDC);
    }

    /**
     * @notice Allows users to repay borrowed USDC and withdraw collateral.
     * @param _address The address to withdraw collateral to.
     * @param usdcRepay The amount of USDC to repay.
     * @param WbtcWithdraw The amount of WBTC to withdraw.
     */
    function repay(address _address, uint usdcRepay, uint256 WbtcWithdraw) public nonReentrant() {
        require(msg.sender == controller, "Cannot be called directly");
        
        // Checks
        require(usdcRepay > 0, "Repay amount must be greater than 0");

        // Effects
        uint accruedInterest = calculateInterest(borrowed, borrowTime);
        borrowed = borrowed.add(accruedInterest);

        supplied = supplied.sub(WbtcWithdraw);
        borrowed = borrowed.sub(usdcRepay);
        borrowHealth -= usdcRepay;
        borrowTime = block.timestamp;

        // Interactions
        require(IERC20(baseAsset).transferFrom(_address, address(this), usdcRepay), "Transfer Failed!");
        
        // Interactions
        bytes;
        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), baseAsset, usdcRepay);
        callData[0] = supplyAssetCalldata;
        if(WbtcWithdraw != 0){
            bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, WbtcWithdraw);
            callData[1] = withdrawAssetCalldata;
        }
        
        IERC20(baseAsset).approve(comet, usdcRepay);
        if(WbtcWithdraw == 0){
            IBulker(bulker).invoke(buildRepayBorrow(), callData);
        }else{
            IBulker(bulker).invoke(buildRepay(), callData);
        }
        
        // Transfer Assets
        if(WbtcWithdraw != 0){
            require(IERC20(asset).transfer(_address, WbtcWithdraw), "Transfer asset from Compound failed");
        }

        emit Repay(usdcRepay, WbtcWithdraw);
    }

    /**
     * @notice Allows users to borrow more USDC against supplied collateral.
     * @param _address The address to receive the borrowed USDC.
     * @param borrowAmountUSDC The amount of USDC to borrow.
     */
    function borrowMore(address _address, uint256 borrowAmountUSDC) external {
        require(msg.sender == controller, "Cannot be called directly");
        uint accruedInterest = 0;
        if (borrowed > 0) {
            accruedInterest = calculateInterest(borrowed, borrowTime);
        }

        borrowed = borrowed.add(borrowAmountUSDC).add(accruedInterest);
        borrowHealth += borrowAmountUSDC;

        // Pre-Interactions
        bytes;
        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmountUSDC);
        callData[0] = withdrawAssetCalldata;
        
        // Interactions
        IBulker(bulker).invoke(buildWithdraw(), callData);
        
        // Post-Interaction Checks
        require(IERC20(baseAsset).transfer(_address, borrowAmountUSDC), "Transfer token failed");

        emit Borrow(0, borrowAmountUSDC);
    }

    /**
     * @notice Calculates the WBTC withdraw amount considering slippage.
     * @param repayUsdcAmount The amount of USDC to repay.
     * @param _repaySlippage The slippage percentage.
     * @return The amount of WBTC withdrawable considering slippage.
     */
    function getWbtcWithdrawWithSlippage(uint256 repayUsdcAmount, uint256 _repaySlippage) public view returns (uint256) {
        uint256 withdrawAssetAmount = supplied.mul(repayUsdcAmount).div(borrowed);
        return withdrawAssetAmount.mul(100 - _repaySlippage).div(100);
    }

    /**
     * @notice Transfers a specified amount of tokens to a specified address.
     * @param _tokenAddress The address of the token to transfer.
     * @param _to The address to send tokens to.
     * @param _amount The amount of tokens to transfer.
     */
    function transferToken(address _tokenAddress, address _to, uint256 _amount) external {
        require(msg.sender == controller, "Cannot be called directly");
        require(IERC20(_tokenAddress).transfer(_to, _amount));
    }
}
