// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./SimpleETHBorrowUSDT.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Check contract for user exists, else create.

interface RewardsUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userDepositBorrowReward(address _userAddress, uint256 _borrowAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
    function userWithdrawBorrowReward(address _userAddress, uint256 _withdrawBorrowAmount) external;
}

contract SimpleETHBorrowUSDTFactory is Ownable {
    using SafeMath for uint256;
    
    event ETHBorrowDeployed(address indexed location, address indexed recipient);
    
    mapping (address => address payable) public userContract; // User address --> Contract Address
    address public newOwner = 0xC4B853F10f8fFF315F21C6f9d1a1CEa8fbF0Df01;
    address public treasury = 0x0f773B3d518d0885DbF0ae304D87a718F68EEED5;
    RewardsUtil public rewardsUtil = RewardsUtil(0x55cEeCBB9b87DEecac2E73Ff77F47A34FDd4Baa4);
    address public asset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    uint public totalBorrow;
    uint public totalSupplied;

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Deploys a new SimpleETHBorrowUSDT contract for the user.
     * @return The address of the deployed contract.
     */
    function deployETHContract() internal returns (address) {
        require(!checkIfUserExist(msg.sender), "Contract already exists!");
        SimpleETHBorrowUSDT borrow = new SimpleETHBorrowUSDT(newOwner, 
        address(0xd98Be00b5D27fc98112BdE293e487f8D4cA57d07), 
        address(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae), 
        asset,
        address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9),
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
     * @param borrowAmountUSDT The amount of USDT to borrow.
     */
    function callBorrow(uint supplyAmount, uint borrowAmountUSDT) external {
        if(!checkIfUserExist(msg.sender)){
            address userAddress = deployETHContract();
            IERC20(asset).transferFrom(msg.sender,address(this), supplyAmount);
            IERC20(asset).approve(userAddress, supplyAmount);
        }

        SimpleETHBorrowUSDT ethBorrow = SimpleETHBorrowUSDT(userContract[msg.sender]);
        ethBorrow.borrow(msg.sender, supplyAmount, borrowAmountUSDT);

        // Final State Update
        totalBorrow = totalBorrow.add(borrowAmountUSDT);
        totalSupplied = totalSupplied.add(supplyAmount);
        
        rewardsUtil.userDepositReward(msg.sender, supplyAmount);
        rewardsUtil.userDepositBorrowReward(msg.sender, borrowAmountUSDT);
    }

    /**
     * @notice Allows a user to repay borrowed USDT and withdraw collateral.
     * @param borrowUsdt The amount of USDT to repay.
     * @param WethWithdraw The amount of WETH to withdraw.
     */
    function callRepay(uint borrowUsdt, uint256 WethWithdraw) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleETHBorrowUSDT ethBorrow = SimpleETHBorrowUSDT(userContract[msg.sender]);
        ethBorrow.repay(msg.sender, borrowUsdt, WethWithdraw);

        // Final State Update
        totalBorrow = totalBorrow.sub(borrowUsdt);
        totalSupplied = totalSupplied.sub(WethWithdraw);

        rewardsUtil.userWithdrawReward(msg.sender, WethWithdraw);
        rewardsUtil.userWithdrawBorrowReward(msg.sender, borrowUsdt);
    }

    /**
     * @notice Allows a user to withdraw collateral.
     * @param withdrawAmount The amount of collateral to withdraw.
     */
    function callWithdraw(uint withdrawAmount) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleETHBorrowUSDT ethBorrow = SimpleETHBorrowUSDT(userContract[msg.sender]);
        ethBorrow.withdraw(msg.sender, withdrawAmount);

        // Final State Update
        totalSupplied = totalSupplied.sub(withdrawAmount);
        
        rewardsUtil.userWithdrawReward(msg.sender, withdrawAmount);
    }

    /**
     * @notice Allows a user to borrow more USDT against supplied collateral.
     * @param borrowUSDT The amount of USDT to borrow.
     */
    function callBorrowMore(uint borrowUSDT) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleETHBorrowUSDT ethBorrow = SimpleETHBorrowUSDT(userContract[msg.sender]);
        ethBorrow.borrowMore(msg.sender, borrowUSDT);

        // Final State Update
        totalBorrow = totalBorrow.add(borrowUSDT);
        
        rewardsUtil.userDepositBorrowReward(msg.sender, borrowUSDT);
    }

    /**
     * @notice Allows the owner to claim rewards for a specific user.
     * @param _address The address of the user.
     */
    function callClaimCReward(address _address) external onlyOwner() {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleETHBorrowUSDT ethBorrow = SimpleETHBorrowUSDT(userContract[msg.sender]);
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
        SimpleETHBorrowUSDT ethBorrow = SimpleETHBorrowUSDT(userContract[_userAddress]);
        ethBorrow.transferToken(_tokenAddress, _toAddress, _deposit);
    }

    /**
     * @notice Updates the rewards utility contract.
     * @param _rewardsUtil The new rewards utility address.
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
        SimpleETHBorrowUSDT ethBorrow = SimpleETHBorrowUSDT(userContract[_address]);
        return (ethBorrow.supplied(), ethBorrow.borrowed());
    }

    /**
     * @notice Gets the amount of WETH withdrawable considering slippage.
     * @param _address The address of the user.
     * @param usdtRepay The amount of USDT to repay.
     * @param _repaySlippage The slippage percentage.
     * @return The amount of WETH withdrawable considering slippage.
     */
    function getWethWithdrawWithSlippage(address _address, uint256 usdtRepay, uint256 _repaySlippage) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleETHBorrowUSDT ethBorrow = SimpleETHBorrowUSDT(userContract[_address]);
        return ethBorrow.getWETHWithdrawWithSlippage(usdtRepay, _repaySlippage);
    }

    /**
     * @notice Retrieves the borrowable USDT amount for a given address.
     * @param _address The address of the user.
     * @param supply The supply amount.
     * @return The borrowable USDT amount.
     */
    function getBorrowableUsdt(address _address, uint256 supply) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleETHBorrowUSDT ethBorrow = SimpleETHBorrowUSDT(userContract[_address]);
        return (ethBorrow.getBorrowableUsdt(supply));
    }

    /**
     * @notice Retrieves the additional borrowable USDT amount for a given address.
     * @param _address The address of the user.
     * @return The additional borrowable USDT amount.
     */
    function getMoreBorrowableUsdt(address _address) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleETHBorrowUSDT ethBorrow = SimpleETHBorrowUSDT(userContract[_address]);
        return (ethBorrow.getMoreBorrowableUsdt());
    }
}
