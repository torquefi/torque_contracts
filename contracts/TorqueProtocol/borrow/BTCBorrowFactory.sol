// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./BTCBorrow.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title RewardsUtil
 * @dev Interface for managing user rewards related to deposits and withdrawals.
 */
interface RewardsUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userDepositBorrowReward(address _userAddress, uint256 _borrowAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
    function userWithdrawBorrowReward(address _userAddress, uint256 _withdrawBorrowAmount) external;
}

/**
 * @title BTCBorrowFactory
 * @dev Factory contract for deploying BTCBorrow contracts and managing user interactions.
 */
contract BTCBorrowFactory is Ownable {
    using SafeMath for uint256;
    event BTCBorrowDeployed(address indexed location, address indexed recipient); // Event emitted when a new BTCBorrow contract is deployed

    mapping (address => address payable) public userContract; // Mapping from user address to contract address
    address public newOwner = 0xC4B853F10f8fFF315F21C6f9d1a1CEa8fbF0Df01; // Address of the new owner
    address public treasury = 0x0f773B3d518d0885DbF0ae304D87a718F68EEED5; // Treasury address for fees
    RewardsUtil public rewardsUtil = RewardsUtil(0x55cEeCBB9b87DEecac2E73Ff77F47A34FDd4Baa4); // Address for rewards utility
    address public asset = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // Address of the asset (WBTC)

    uint public totalBorrow; // Total amount borrowed
    uint public totalSupplied; // Total amount supplied

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Deploy a new BTCBorrow contract for the user.
     * @return Address of the newly deployed BTCBorrow contract.
     */
    function deployBTCContract() internal returns (address) {
        require(!checkIfUserExist(msg.sender), "Contract already exists!");
        BTCBorrow borrow = new BTCBorrow(newOwner, 
        address(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf), 
        address(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae), 
        asset,
        address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),
        address(0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d),
        address(0xfdf7b4486f5de843838EcFd254711E06aF1f0641),
        address(0xf7F6718Cf69967203740cCb431F6bDBff1E0FB68),
        treasury,
        address(this),
        1);
        userContract[msg.sender] = payable(borrow);
        emit BTCBorrowDeployed(address(borrow), msg.sender);
        return address(borrow);
    }

    /**
     * @notice Update the owner of the BTCBorrow contracts.
     * @param _owner New owner's address.
     */
    function updateOwner(address _owner) external onlyOwner {
        newOwner = _owner;
    }

    /**
     * @notice Call borrow function in the user's BTCBorrow contract.
     * @param supplyAmount Amount of collateral supplied.
     * @param borrowAmountUSDC Amount of USDC to borrow.
     * @param tUSDBorrowAmount Amount of TUSD to borrow.
     */
    function callBorrow(uint supplyAmount, uint borrowAmountUSDC, uint tUSDBorrowAmount) external {
        if(!checkIfUserExist(msg.sender)){
            address userAddress = deployBTCContract();
            IERC20(asset).transferFrom(msg.sender,address(this), supplyAmount);
            IERC20(asset).approve(userAddress, supplyAmount);
        }
        BTCBorrow btcBorrow =  BTCBorrow(userContract[msg.sender]);
        btcBorrow.borrow(msg.sender, supplyAmount, borrowAmountUSDC, tUSDBorrowAmount);

        // Final State Update
        totalBorrow = totalBorrow.add(tUSDBorrowAmount);
        totalSupplied = totalSupplied.add(supplyAmount);
        
        rewardsUtil.userDepositReward(msg.sender, supplyAmount);
        rewardsUtil.userDepositBorrowReward(msg.sender, tUSDBorrowAmount);
    }

    /**
     * @notice Call repay function in the user's BTCBorrow contract.
     * @param tusdRepayAmount Amount of TUSD to repay.
     * @param WbtcWithdraw Amount of WBTC to withdraw.
     */
    function callRepay(uint tusdRepayAmount, uint256 WbtcWithdraw) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[msg.sender]);
        btcBorrow.repay(msg.sender, tusdRepayAmount, WbtcWithdraw);

        // Final State Update
        totalBorrow = totalBorrow.sub(tusdRepayAmount);
        totalSupplied = totalSupplied.sub(WbtcWithdraw);

        rewardsUtil.userWithdrawReward(msg.sender, WbtcWithdraw);
        rewardsUtil.userWithdrawBorrowReward(msg.sender, tusdRepayAmount);
    }

    /**
     * @notice Call mint function in the user's BTCBorrow contract.
     * @param _amountToMint Amount of TUSD to mint.
     */
    function callMintTUSD(uint256 _amountToMint) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[msg.sender]);
        btcBorrow.mintTUSD(msg.sender, _amountToMint);

        // Final State Update
        totalBorrow = totalBorrow.add(_amountToMint);

        rewardsUtil.userDepositBorrowReward(msg.sender, _amountToMint);
    }

    /**
     * @notice Call withdraw function in the user's BTCBorrow contract.
     * @param withdrawAmount Amount of WBTC to withdraw.
     */
    function callWithdraw(uint withdrawAmount) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[msg.sender]);
        btcBorrow.withdraw(msg.sender, withdrawAmount);

        // Final State Update
        totalSupplied = totalSupplied.sub(withdrawAmount);
        
        rewardsUtil.userWithdrawReward(msg.sender, withdrawAmount);
    }

    /**
     * @notice Call claim reward function in the user's BTCBorrow contract.
     * @param _address Address of the user for whom to claim rewards.
     */
    function callClaimCReward(address _address) external onlyOwner {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[msg.sender]);
        btcBorrow.claimCReward();
    }

    /**
     * @notice Call transfer function in the user's BTCBorrow contract.
     * @param _userAddress Address of the user whose contract will transfer tokens.
     * @param _tokenAddress Address of the token to transfer.
     * @param _toAddress Address to transfer tokens to.
     * @param _deposit Amount of tokens to transfer.
     */
    function callTokenTransfer(address _userAddress, address _tokenAddress, address _toAddress, uint256 _deposit) external onlyOwner {
        require(checkIfUserExist(_userAddress), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_userAddress]);
        btcBorrow.transferToken(_tokenAddress, _toAddress, _deposit);
    }

    /**
     * @notice Update the rewards utility contract address.
     * @param _rewardsUtil New address for the rewards utility contract.
     */
    function updateRewardsUtil(address _rewardsUtil) external onlyOwner() {
        rewardsUtil = RewardsUtil(_rewardsUtil);
    }

    /**
     * @notice Update the treasury address.
     * @param _treasury New treasury address.
     */
    function updateTreasury(address _treasury) external onlyOwner() {
        treasury = _treasury;
    }

    /**
     * @notice Check if a user already has a contract deployed.
     * @param _address Address of the user to check.
     * @return True if the user exists, false otherwise.
     */
    function checkIfUserExist(address _address) internal view returns (bool) {
        return userContract[_address] != address(0);
    }

    /**
     * @notice Get user details from their BTCBorrow contract.
     * @param _address Address of the user.
     * @return sup Amount supplied, bor Amount borrowed, baseBor Amount base borrowed.
     */
    function getUserDetails(address _address) external view returns (uint256, uint256, uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return (btcBorrow.supplied(), btcBorrow.borrowed(), btcBorrow.baseBorrowed());
    }

    /**
     * @notice Calculate the maximum amount of WBTC that can be withdrawn based on TUSD repayment amount.
     * @param _address Address of the user.
     * @param tusdRepayAmount Amount of TUSD to repay.
     * @return The maximum amount of WBTC that can be withdrawn.
     */
    function getWbtcWithdraw(address _address, uint256 tusdRepayAmount) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return btcBorrow.getWbtcWithdraw(tusdRepayAmount);
    }

    /**
     * @notice Calculate the maximum amount of WBTC that can be withdrawn with slippage consideration.
     * @param _address Address of the user.
     * @param tusdRepayAmount Amount of TUSD to repay.
     * @param _repaySlippage Slippage percentage to consider.
     * @return The maximum amount of WBTC that can be withdrawn with slippage.
     */
    function getWbtcWithdrawWithSlippage(address _address, uint256 tusdRepayAmount, uint256 _repaySlippage) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return btcBorrow.getWbtcWithdrawWithSlippage(tusdRepayAmount, _repaySlippage);
    }

    /**
     * @notice Get the maximum additional amount of TUSD that can be minted for the specified user.
     * @param _address Address of the user.
     * @return The maximum mintable amount of TUSD.
     */
    function maxMoreMintable(address _address) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return btcBorrow.maxMoreMintable();
    }

    /**
     * @notice Get the mintable amount of TUSD based on the supply amount.
     * @param _address Address of the user.
     * @param supplyAmount Amount of collateral supplied.
     * @return The mintable amount of TUSD.
     */
    function mintableTUSD(address _address, uint supplyAmount) external view returns (uint) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return btcBorrow.mintableTUSD(supplyAmount);
    }

    /**
     * @notice Get the borrowable USDC for the specified user based on the supply amount.
     * @param _address Address of the user.
     * @param supply Amount of collateral supplied.
     * @return The borrowable amount of USDC.
     */
    function getBorrowableUsdc(address _address, uint256 supply) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return (btcBorrow.getBorrowableUsdc(supply));
    }
}
