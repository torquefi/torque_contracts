// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./SimpleBTCBorrow.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Check contract for user exists, else create.

interface RewardsUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userDepositBorrowReward(address _userAddress, uint256 _borrowAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
    function userWithdrawBorrowReward(address _userAddress, uint256 _withdrawBorrowAmount) external;
}

contract SimpleBTCBorrowFactory is Ownable {
    using SafeMath for uint256;
    
    event BTCBorrowDeployed(address indexed location, address indexed recipient);
    
    mapping (address => address payable) public userContract; // User address --> Contract Address
    address public newOwner = 0x7fb3933a47D20ab591D4F136E36865576c6f305c;
    address public treasury = 0x177f6519A523EEbb542aed20320EFF9401bC47d0;
    RewardsUtil public torqRewardsUtil = RewardsUtil(0x3452faA42fd613937dCd43E0f0cBf7d4205919c5);
    RewardsUtil public arbRewardsUtil = RewardsUtil(0x6965b496De9b7C0bF274F8f6D5Dfa359Ac7D3b72);
    address public asset = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    uint public totalBorrow;
    uint public totalSupplied;

    /**
     * @notice Initializes the contract with the owner's address.
     * @param _owner The address of the owner.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Deploys a new SimpleBTCBorrow contract for the user.
     * @return The address of the deployed contract.
     */
    function deployBTCContract() internal returns (address) {
        require(!checkIfUserExist(msg.sender), "Contract already exists!");
        SimpleBTCBorrow borrow = new SimpleBTCBorrow(newOwner, 
        address(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf), 
        address(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae), 
        asset,
        address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),
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
     * @notice Allows users to borrow USDC against supplied collateral.
     * @param supplyAmount The amount of collateral supplied.
     * @param borrowAmountUSDC The amount of USDC to borrow.
     */
    function callBorrow(uint supplyAmount, uint borrowAmountUSDC) external {
        if(!checkIfUserExist(msg.sender)){
            address userAddress = deployBTCContract();
            IERC20(asset).transferFrom(msg.sender,address(this), supplyAmount);
            IERC20(asset).approve(userAddress, supplyAmount);
        }

        SimpleBTCBorrow btcBorrow =  SimpleBTCBorrow(userContract[msg.sender]);
        btcBorrow.borrow(msg.sender, supplyAmount, borrowAmountUSDC);

        // Final State Update
        totalBorrow = totalBorrow.add(borrowAmountUSDC);
        totalSupplied = totalSupplied.add(supplyAmount);
        
        torqRewardsUtil.userDepositReward(msg.sender, supplyAmount);
        torqRewardsUtil.userDepositBorrowReward(msg.sender, borrowAmountUSDC);
        
        arbRewardsUtil.userDepositReward(msg.sender, supplyAmount);
        arbRewardsUtil.userDepositBorrowReward(msg.sender, borrowAmountUSDC);
    }

    /**
     * @notice Allows users to repay borrowed USDC and withdraw collateral.
     * @param borrowUSDC The amount of USDC to repay.
     * @param WbtcWithdraw The amount of WBTC to withdraw.
     */
    function callRepay(uint borrowUSDC, uint256 WbtcWithdraw) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleBTCBorrow btcBorrow =  SimpleBTCBorrow(userContract[msg.sender]);
        btcBorrow.repay(msg.sender, borrowUSDC, WbtcWithdraw);

        // Final State Update
        totalBorrow = totalBorrow.sub(borrowUSDC);
        totalSupplied = totalSupplied.sub(WbtcWithdraw);

        torqRewardsUtil.userWithdrawReward(msg.sender, WbtcWithdraw);
        torqRewardsUtil.userWithdrawBorrowReward(msg.sender, borrowUSDC);

        arbRewardsUtil.userWithdrawReward(msg.sender, WbtcWithdraw);
        arbRewardsUtil.userWithdrawBorrowReward(msg.sender, borrowUSDC);
    }

    /**
     * @notice Allows users to withdraw a specified amount of collateral.
     * @param withdrawAmount The amount of collateral to withdraw.
     */
    function callWithdraw(uint withdrawAmount) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleBTCBorrow btcBorrow =  SimpleBTCBorrow(userContract[msg.sender]);
        btcBorrow.withdraw(msg.sender, withdrawAmount);

        // Final State Update
        totalSupplied = totalSupplied.sub(withdrawAmount);
        
        torqRewardsUtil.userWithdrawReward(msg.sender, withdrawAmount);
        arbRewardsUtil.userWithdrawReward(msg.sender, withdrawAmount);
    }

    /**
     * @notice Allows users to borrow more USDC against supplied collateral.
     * @param borrowUSDC The amount of USDC to borrow.
     */
    function callBorrowMore(uint borrowUSDC) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleBTCBorrow btcBorrow =  SimpleBTCBorrow(userContract[msg.sender]);
        btcBorrow.borrowMore(msg.sender, borrowUSDC);

        // Final State Update
        totalBorrow = totalBorrow.add(borrowUSDC);
        
        torqRewardsUtil.userDepositBorrowReward(msg.sender, borrowUSDC);
        arbRewardsUtil.userDepositBorrowReward(msg.sender, borrowUSDC);
    }

    /**
     * @notice Allows the owner to claim Comet rewards for a user.
     * @param _address The address of the user to claim rewards for.
     */
    function callClaimCReward(address _address) external onlyOwner(){
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrow btcBorrow =  SimpleBTCBorrow(userContract[msg.sender]);
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
        SimpleBTCBorrow btcBorrow =  SimpleBTCBorrow(userContract[_userAddress]);
        btcBorrow.transferToken(_tokenAddress, _toAddress, _deposit);
    }

    /**
     * @notice Updates the addresses of the rewards utilities.
     * @param _torqRewardsUtil The new address for the Torq rewards utility.
     * @param _arbRewardsUtil The new address for the Arbitrum rewards utility.
     */
    function updateRewardsUtil(address _torqRewardsUtil, address _arbRewardsUtil) external onlyOwner() {
        torqRewardsUtil = RewardsUtil(_torqRewardsUtil);
        arbRewardsUtil = RewardsUtil(_arbRewardsUtil);
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
        SimpleBTCBorrow btcBorrow =  SimpleBTCBorrow(userContract[_address]);
        return (btcBorrow.supplied(), btcBorrow.borrowed());
    }

    /**
     * @notice Retrieves the WBTC withdraw amount considering slippage.
     * @param _address The address of the user.
     * @param usdcRepay The amount of USDC to repay.
     * @param _repaySlippage The slippage percentage.
     * @return The amount of WBTC withdrawable considering slippage.
     */
    function getWbtcWithdrawWithSlippage(address _address, uint256 usdcRepay, uint256 _repaySlippage) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrow btcBorrow =  SimpleBTCBorrow(userContract[_address]);
        return btcBorrow.getWbtcWithdrawWithSlippage(usdcRepay, _repaySlippage);
    }

    /**
     * @notice Retrieves the amount of USDC borrowable based on the specified supply.
     * @param _address The address of the user.
     * @param supply The amount of collateral supplied.
     * @return The amount of USDC that can be borrowed.
     */
    function getBorrowableUsdc(address _address, uint256 supply) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrow btcBorrow =  SimpleBTCBorrow(userContract[_address]);
        return (btcBorrow.getBorrowableUsdc(supply));
    }

    /**
     * @notice Retrieves the additional USDC borrowable based on the user's collateral.
     * @param _address The address of the user.
     * @return The additional amount of USDC that can be borrowed.
     */
    function getMoreBorrowableUsdc(address _address) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrow btcBorrow =  SimpleBTCBorrow(userContract[_address]);
        return (btcBorrow.getMoreBorrowableUsdc());
    }
}
