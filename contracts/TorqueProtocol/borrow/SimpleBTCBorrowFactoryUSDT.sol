// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./SimpleBTCBorrowUSDT.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Check contract for user exists, else create.

interface RewardsUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userDepositBorrowReward(address _userAddress, uint256 _borrowAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
    function userWithdrawBorrowReward(address _userAddress, uint256 _withdrawBorrowAmount) external;
}

contract SimpleBTCBorrowUSDTFactory is Ownable {
    using SafeMath for uint256;
    
    event BTCBorrowDeployed(address indexed location, address indexed recipient);
    
    mapping (address => address payable) public userContract; // User address --> Contract Address
    address public newOwner = 0xC4B853F10f8fFF315F21C6f9d1a1CEa8fbF0Df01;
    address public treasury = 0x0f773B3d518d0885DbF0ae304D87a718F68EEED5;
    RewardsUtil public rewardsUtil = RewardsUtil(0x55cEeCBB9b87DEecac2E73Ff77F47A34FDd4Baa4);
    address public asset = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    uint public totalBorrow;
    uint public totalSupplied;

    /**
     * @notice Initializes the contract with the owner's address.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Deploys a new SimpleBTCBorrowUSDT contract for the user.
     * @return The address of the deployed contract.
     */
    function deployBTCContract() internal returns (address) {
        require(!checkIfUserExist(msg.sender), "Contract already exists!");
        SimpleBTCBorrowUSDT borrow = new SimpleBTCBorrowUSDT(newOwner, 
        address(0xd98Be00b5D27fc98112BdE293e487f8D4cA57d07), 
        address(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae), 
        asset,
        address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9),
        address(0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d),
        treasury,
        address(this),
        1);
        userContract[msg.sender] = payable(borrow);
        emit BTCBorrowDeployed(address(borrow), msg.sender);
        return address(borrow);
    }

    /**
     * @notice Updates the new owner's address.
     * @param _owner The new owner's address.
     */
    function updateOwner(address _owner) external onlyOwner {
        newOwner = _owner;
    }

    /**
     * @notice Allows users to borrow USDT against supplied collateral.
     * @param supplyAmount The amount of collateral supplied.
     * @param borrowAmountUSDT The amount of USDT to borrow.
     */
    function callBorrow(uint supplyAmount, uint borrowAmountUSDT) external {
        if(!checkIfUserExist(msg.sender)){
            address userAddress = deployBTCContract();
            IERC20(asset).transferFrom(msg.sender,address(this), supplyAmount);
            IERC20(asset).approve(userAddress, supplyAmount);
        }

        SimpleBTCBorrowUSDT btcBorrow =  SimpleBTCBorrowUSDT(userContract[msg.sender]);
        btcBorrow.borrow(msg.sender, supplyAmount, borrowAmountUSDT);

        // Final State Update
        totalBorrow = totalBorrow.add(borrowAmountUSDT);
        totalSupplied = totalSupplied.add(supplyAmount);
        
        rewardsUtil.userDepositReward(msg.sender, supplyAmount);
        rewardsUtil.userDepositBorrowReward(msg.sender, borrowAmountUSDT);
    }

    /**
     * @notice Allows users to repay borrowed USDT and withdraw collateral.
     * @param borrowUSDT The amount of USDT to repay.
     * @param WbtcWithdraw The amount of WBTC to withdraw.
     */
    function callRepay(uint borrowUSDT, uint256 WbtcWithdraw) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleBTCBorrowUSDT btcBorrow =  SimpleBTCBorrowUSDT(userContract[msg.sender]);
        btcBorrow.repay(msg.sender, borrowUSDT, WbtcWithdraw);

        // Final State Update
        totalBorrow = totalBorrow.sub(borrowUSDT);
        totalSupplied = totalSupplied.sub(WbtcWithdraw);

        rewardsUtil.userWithdrawReward(msg.sender, WbtcWithdraw);
        rewardsUtil.userWithdrawBorrowReward(msg.sender, borrowUSDT);
    }

    /**
     * @notice Allows users to withdraw a specified amount of collateral.
     * @param withdrawAmount The amount of collateral to withdraw.
     */
    function callWithdraw(uint withdrawAmount) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleBTCBorrowUSDT btcBorrow =  SimpleBTCBorrowUSDT(userContract[msg.sender]);
        btcBorrow.withdraw(msg.sender, withdrawAmount);

        // Final State Update
        totalSupplied = totalSupplied.sub(withdrawAmount);
        
        rewardsUtil.userWithdrawReward(msg.sender, withdrawAmount);
    }

    /**
     * @notice Allows users to borrow more USDT against supplied collateral.
     * @param borrowUSDT The amount of USDT to borrow.
     */
    function callBorrowMore(uint borrowUSDT) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleBTCBorrowUSDT btcBorrow =  SimpleBTCBorrowUSDT(userContract[msg.sender]);
        btcBorrow.borrowMore(msg.sender, borrowUSDT);

        // Final State Update
        totalBorrow = totalBorrow.add(borrowUSDT);
        
        rewardsUtil.userDepositBorrowReward(msg.sender, borrowUSDT);
    }

    /**
     * @notice Allows the owner to claim Comet rewards for a user.
     * @param _address The address of the user to claim rewards for.
     */
    function callClaimCReward(address _address) external onlyOwner(){
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrowUSDT btcBorrow =  SimpleBTCBorrowUSDT(userContract[msg.sender]);
        btcBorrow.claimCReward();
    }

    /**
     * @notice Transfers a specified amount of tokens to a specified address.
     * @param _userAddress The address of the user to transfer tokens for.
     * @param _tokenAddress The address of the token to transfer.
     * @param _toAddress The address to send tokens to.
     * @param _deposit The amount of tokens to transfer.
     */
    function callTokenTransfer(address _userAddress, address _tokenAddress, address _toAddress, uint256 _deposit) external onlyOwner {
        require(checkIfUserExist(_userAddress), "Contract not created!");
        SimpleBTCBorrowUSDT btcBorrow =  SimpleBTCBorrowUSDT(userContract[_userAddress]);
        btcBorrow.transferToken(_tokenAddress, _toAddress, _deposit);
    }

    /**
     * @notice Updates the address of the rewards utility.
     * @param _rewardsUtil The new address for the rewards utility.
     */
    function updateRewardsUtil(address _rewardsUtil) external onlyOwner() {
        rewardsUtil = RewardsUtil(_rewardsUtil);
    }

    /**
     * @notice Updates the treasury address.
     * @param _treasury The new treasury address.
     */
    function updateTreasury(address _treasury) external onlyOwner() {
        treasury = _treasury;
    }

    /**
     * @notice Checks if a user contract exists for the specified address.
     * @param _address The address to check.
     * @return True if the user contract exists, otherwise false.
     */
    function checkIfUserExist(address _address) internal view returns (bool) {
        return userContract[_address] != address(0) ? true : false;
    }

    /**
     * @notice Retrieves the supplied and borrowed amounts for a user.
     * @param _address The address of the user.
     * @return The supplied amount and borrowed amount for the user.
     */
    function getUserDetails(address _address) external view returns (uint256, uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrowUSDT btcBorrow =  SimpleBTCBorrowUSDT(userContract[_address]);
        return (btcBorrow.supplied(), btcBorrow.borrowed());
    }

    /**
     * @notice Retrieves the WBTC withdraw amount considering slippage.
     * @param _address The address of the user.
     * @param usdtRepay The amount of USDT to repay.
     * @param _repaySlippage The slippage percentage.
     * @return The amount of WBTC withdrawable considering slippage.
     */
    function getWbtcWithdrawWithSlippage(address _address, uint256 usdtRepay, uint256 _repaySlippage) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrowUSDT btcBorrow =  SimpleBTCBorrowUSDT(userContract[_address]);
        return btcBorrow.getWbtcWithdrawWithSlippage(usdtRepay, _repaySlippage);
    }

    /**
     * @notice Retrieves the amount of USDT borrowable based on the specified supply.
     * @param _address The address of the user.
     * @param supply The amount of collateral supplied.
     * @return The amount of USDT that can be borrowed.
     */
    function getBorrowableUsdt(address _address, uint256 supply) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrowUSDT btcBorrow =  SimpleBTCBorrowUSDT(userContract[_address]);
        return (btcBorrow.getBorrowableUsdt(supply));
    }

    /**
     * @notice Retrieves the additional USDT borrowable based on the user's collateral.
     * @param _address The address of the user.
     * @return The additional amount of USDT that can be borrowed.
     */
    function getMoreBorrowableUsdt(address _address) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrowUSDT btcBorrow =  SimpleBTCBorrowUSDT(userContract[_address]);
        return (btcBorrow.getMoreBorrowableUsdt());
    }
}
