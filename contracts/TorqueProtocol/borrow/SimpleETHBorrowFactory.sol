// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./SimpleETHBorrow.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Check contract for user exists, else create.

interface RewardsUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userDepositBorrowReward(address _userAddress, uint256 _borrowAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
    function userWithdrawBorrowReward(address _userAddress, uint256 _withdrawBorrowAmount) external;
}

contract SimpleETHBorrowFactory is Ownable {
    using SafeMath for uint256;
    
    event ETHBorrowDeployed(address indexed location, address indexed recipient);
    
    mapping (address => address payable) public userContract; // User address --> Contract Address
    address public newOwner = 0x7fb3933a47D20ab591D4F136E36865576c6f305c;
    address public treasury = 0x177f6519A523EEbb542aed20320EFF9401bC47d0;
    RewardsUtil public torqRewardsUtil = RewardsUtil(0x3452faA42fd613937dCd43E0f0cBf7d4205919c5);
    RewardsUtil public arbRewardsUtil = RewardsUtil(0x6965b496De9b7C0bF274F8f6D5Dfa359Ac7D3b72);
    address public asset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    uint public totalBorrow;
    uint public totalSupplied;

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Deploys a new SimpleETHBorrow contract for the user.
     * @return The address of the deployed contract.
     */
    function deployETHContract() internal returns (address) {
        require(!checkIfUserExist(msg.sender), "Contract already exists!");
        SimpleETHBorrow borrow = new SimpleETHBorrow(newOwner, 
        address(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf), 
        address(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae), 
        asset,
        address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),
        address(0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d),
        treasury,
        address(this),
        1);
        userContract[msg.sender] = payable(borrow);
        emit ETHBorrowDeployed(address(borrow), msg.sender);
        return address(borrow);
    }

    /**
     * @notice Updates the owner of the factory.
     * @param _owner The new owner address.
     */
    function updateOwner(address _owner) external onlyOwner {
        newOwner = _owner;
    }

    /**
     * @notice Allows a user to borrow against supplied collateral.
     * @param supplyAmount The amount of collateral supplied.
     * @param borrowAmountUSDC The amount of USDC to borrow.
     */
    function callBorrow(uint supplyAmount, uint borrowAmountUSDC) external {
        if(!checkIfUserExist(msg.sender)) {
            address userAddress = deployETHContract();
            IERC20(asset).transferFrom(msg.sender,address(this), supplyAmount);
            IERC20(asset).approve(userAddress, supplyAmount);
        }

        SimpleETHBorrow ethBorrow = SimpleETHBorrow(userContract[msg.sender]);
        ethBorrow.borrow(msg.sender, supplyAmount, borrowAmountUSDC);

        // Final State Update
        totalBorrow = totalBorrow.add(borrowAmountUSDC);
        totalSupplied = totalSupplied.add(supplyAmount);
        
        torqRewardsUtil.userDepositReward(msg.sender, supplyAmount);
        torqRewardsUtil.userDepositBorrowReward(msg.sender, borrowAmountUSDC);
        
        arbRewardsUtil.userDepositReward(msg.sender, supplyAmount);
        arbRewardsUtil.userDepositBorrowReward(msg.sender, borrowAmountUSDC);
    }

    /**
     * @notice Allows a user to repay borrowed USDC and withdraw collateral.
     * @param borrowUsdc The amount of USDC to repay.
     * @param WethWithdraw The amount of WETH to withdraw.
     */
    function callRepay(uint borrowUsdc, uint256 WethWithdraw) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleETHBorrow ethBorrow = SimpleETHBorrow(userContract[msg.sender]);
        ethBorrow.repay(msg.sender, borrowUsdc, WethWithdraw);

        // Final State Update
        totalBorrow = totalBorrow.sub(borrowUsdc);
        totalSupplied = totalSupplied.sub(WethWithdraw);

        torqRewardsUtil.userWithdrawReward(msg.sender, WethWithdraw);
        torqRewardsUtil.userWithdrawBorrowReward(msg.sender, borrowUsdc);

        arbRewardsUtil.userWithdrawReward(msg.sender, WethWithdraw);
        arbRewardsUtil.userWithdrawBorrowReward(msg.sender, borrowUsdc);
    }

    /**
     * @notice Allows a user to withdraw collateral.
     * @param withdrawAmount The amount of collateral to withdraw.
     */
    function callWithdraw(uint withdrawAmount) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleETHBorrow ethBorrow = SimpleETHBorrow(userContract[msg.sender]);
        ethBorrow.withdraw(msg.sender, withdrawAmount);

        // Final State Update
        totalSupplied = totalSupplied.sub(withdrawAmount);
        
        torqRewardsUtil.userWithdrawReward(msg.sender, withdrawAmount);
        arbRewardsUtil.userWithdrawReward(msg.sender, withdrawAmount);
    }

    /**
     * @notice Allows a user to borrow more USDC against supplied collateral.
     * @param borrowUSDC The amount of USDC to borrow.
     */
    function callBorrowMore(uint borrowUSDC) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleETHBorrow ethBorrow = SimpleETHBorrow(userContract[msg.sender]);
        ethBorrow.borrowMore(msg.sender, borrowUSDC);

        // Final State Update
        totalBorrow = totalBorrow.add(borrowUSDC);
        
        torqRewardsUtil.userDepositBorrowReward(msg.sender, borrowUSDC);
        arbRewardsUtil.userDepositBorrowReward(msg.sender, borrowUSDC);
    }

    /**
     * @notice Allows the owner to claim rewards for a specific user.
     * @param _address The address of the user.
     */
    function callClaimCReward(address _address) external onlyOwner() {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleETHBorrow ethBorrow = SimpleETHBorrow(userContract[msg.sender]);
        ethBorrow.claimCReward();
    }

    /**
     * @notice Allows the owner to transfer tokens on behalf of a user.
     * @param _userAddress The address of the user.
     * @param _tokenAddress The address of the token to transfer.
     * @param _toAddress The address to send tokens to.
     * @param _deposit The amount of tokens to transfer.
     */
    function callTokenTransfer(address _userAddress, address _tokenAddress, address _toAddress, uint256 _deposit) external onlyOwner {
        require(checkIfUserExist(_userAddress), "Contract not created!");
        SimpleETHBorrow ethBorrow = SimpleETHBorrow(userContract[_userAddress]);
        ethBorrow.transferToken(_tokenAddress, _toAddress, _deposit);
    }

    /**
     * @notice Updates the rewards utility contracts.
     * @param _torqRewardsUtil The new Torq rewards utility address.
     * @param _arbRewardsUtil The new Arbitrum rewards utility address.
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
     * @param _address The address of the user.
     * @return True if the user contract exists, false otherwise.
     */
    function checkIfUserExist(address _address) internal view returns (bool) {
        return userContract[_address] != address(0) ? true : false;
    }

    /**
     * @notice Retrieves user details including supplied and borrowed amounts.
     * @param _address The address of the user.
     * @return The supplied and borrowed amounts.
     */
    function getUserDetails(address _address) external view returns (uint256, uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleETHBorrow ethBorrow = SimpleETHBorrow(userContract[_address]);
        return (ethBorrow.supplied(), ethBorrow.borrowed());
    }

    /**
     * @notice Gets the amount of WETH withdrawable considering slippage.
     * @param _address The address of the user.
     * @param usdcRepay The amount of USDC to repay.
     * @param _repaySlippage The slippage percentage.
     * @return The amount of WETH withdrawable considering slippage.
     */
    function getWethWithdrawWithSlippage(address _address, uint256 usdcRepay, uint256 _repaySlippage) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleETHBorrow ethBorrow = SimpleETHBorrow(userContract[_address]);
        return ethBorrow.getWETHWithdrawWithSlippage(usdcRepay, _repaySlippage);
    }

    /**
     * @notice Retrieves the borrowable USDC amount for a given address.
     * @param _address The address of the user.
     * @param supply The supply amount.
     * @return The borrowable USDC amount.
     */
    function getBorrowableUsdc(address _address, uint256 supply) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleETHBorrow ethBorrow = SimpleETHBorrow(userContract[_address]);
        return (ethBorrow.getBorrowableUsdc(supply));
    }

    /**
     * @notice Retrieves the additional borrowable USDC amount for a given address.
     * @param _address The address of the user.
     * @return The additional borrowable USDC amount.
     */
    function getMoreBorrowableUsdc(address _address) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleETHBorrow ethBorrow = SimpleETHBorrow(userContract[_address]);
        return (ethBorrow.getMoreBorrowableUsdc());
    }
}
