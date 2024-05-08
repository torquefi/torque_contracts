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

// Check contract for user exists, else create.

interface RewardsUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userDepositBorrowReward(address _userAddress, uint256 _borrowAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
    function userWithdrawBorrowReward(address _userAddress, uint256 _withdrawBorrowAmount) external;
}

contract BTCBorrowFactory is Ownable {
    using SafeMath for uint256;
    event BTCBorrowDeployed(address indexed location, address indexed recipient);
    
    mapping (address => address payable) public userContract; // User address --> Contract Address
    address public newOwner = 0xC4B853F10f8fFF315F21C6f9d1a1CEa8fbF0Df01;
    address public treasury = 0x0f773B3d518d0885DbF0ae304D87a718F68EEED5;
    RewardsUtil public rewardsUtil = RewardsUtil(0x55cEeCBB9b87DEecac2E73Ff77F47A34FDd4Baa4);
    address public asset = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    uint public totalBorrow;
    uint public totalSupplied;

    constructor() Ownable(msg.sender) {}

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

    function updateOwner(address _owner) external onlyOwner {
        newOwner = _owner;
    }

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

    function callMintTUSD(uint256 _amountToMint) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[msg.sender]);
        btcBorrow.mintTUSD(msg.sender, _amountToMint);

        // Final State Update
        totalBorrow = totalBorrow.add(_amountToMint);

        rewardsUtil.userDepositBorrowReward(msg.sender, _amountToMint);
    }

    function callWithdraw(uint withdrawAmount) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[msg.sender]);
        btcBorrow.withdraw(msg.sender, withdrawAmount);

        //Final State Update
        totalSupplied = totalSupplied.sub(withdrawAmount);
        
        rewardsUtil.userWithdrawReward(msg.sender, withdrawAmount);
    }

    function callClaimCReward(address _address) external onlyOwner {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[msg.sender]);
        btcBorrow.claimCReward();
    }

    function callTokenTransfer(address _userAddress, address _tokenAddress, address _toAddress, uint256 _deposit) external onlyOwner {
        require(checkIfUserExist(_userAddress), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_userAddress]);
        btcBorrow.transferToken(_tokenAddress, _toAddress, _deposit);
    }

    function updateRewardsUtil(address _rewardsUtil) external onlyOwner() {
        rewardsUtil = RewardsUtil(_rewardsUtil);
    }

    function updateTreasury(address _treasury) external onlyOwner() {
        treasury = _treasury;
    }

    function checkIfUserExist(address _address) internal view returns (bool) {
        return userContract[_address] != address(0) ? true : false;

    }

    function getUserDetails(address _address) external view returns (uint256, uint256, uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return (btcBorrow.supplied(), btcBorrow.borrowed(), btcBorrow.baseBorrowed());
    }

    function getWbtcWithdraw(address _address, uint256 tusdRepayAmount) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return btcBorrow.getWbtcWithdraw(tusdRepayAmount);
    }

    function getWbtcWithdrawWithSlippage(address _address, uint256 tusdRepayAmount, uint256 _repaySlippage) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return btcBorrow.getWbtcWithdrawWithSlippage(tusdRepayAmount, _repaySlippage);
    }

    function maxMoreMintable(address _address) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return btcBorrow.maxMoreMintable();
    }

    function mintableTUSD(address _address, uint supplyAmount) external view returns (uint) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return btcBorrow.mintableTUSD(supplyAmount);
    }

    function getBorrowableUsdc(address _address, uint256 supply) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        BTCBorrow btcBorrow =  BTCBorrow(userContract[_address]);
        return (btcBorrow.getBorrowableUsdc(supply));
    }

}
