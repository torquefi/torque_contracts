// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./SimpleBTCBorrowV2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Check contract for user exists, else create.

interface RewardsUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userDepositBorrowReward(address _userAddress, uint256 _borrowAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
    function userWithdrawBorrowReward(address _userAddress, uint256 _withdrawBorrowAmount) external;
}

contract SimpleBTCBorrowFactoryV2 is Ownable {
    using SafeMath for uint256;
    
    event BTCBorrowDeployed(address indexed location, address indexed recipient);
    
    mapping (address => address payable) public userContract; // User address --> Contract Address
    mapping (address => bool) public refinanceContract;
    address public newOwner = 0x7fb3933a47D20ab591D4F136E36865576c6f305c;
    address public treasury = 0x177f6519A523EEbb542aed20320EFF9401bC47d0;
    RewardsUtil public torqRewardsUtil = RewardsUtil(0x3452faA42fd613937dCd43E0f0cBf7d4205919c5);
    RewardsUtil public arbRewardsUtil = RewardsUtil(0x6965b496De9b7C0bF274F8f6D5Dfa359Ac7D3b72);
    address public asset = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    uint public totalBorrow;
    uint public totalSupplied;

    constructor() Ownable(msg.sender) {}

    function deployBTCContract(address userAddress) internal returns (address) {
        require(!checkIfUserExist(msg.sender), "Contract already exists!");
        SimpleBTCBorrowV2 borrow = new SimpleBTCBorrowV2(newOwner, 
        address(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf), 
        address(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae), 
        asset,
        address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),
        address(0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d),
        treasury,
        address(this),
        1);
        userContract[userAddress] = payable(borrow);
        emit BTCBorrowDeployed(address(borrow), userAddress);
        return address(borrow);
    }

    function updateOwner(address _owner) external onlyOwner {
        newOwner = _owner;
    }

    function callBorrowRefinance(uint supplyAmount, uint borrowAmountUSDC, address userAddress) external {
        require(refinanceContract[msg.sender], "Restricted Access!");
        IERC20(asset).transferFrom(msg.sender, address(this), supplyAmount);
        if(!checkIfUserExist(userAddress)){
            address userContractAddress = deployBTCContract(userAddress);
            IERC20(asset).approve(userContractAddress, supplyAmount);
        }
        else{
            IERC20(asset).approve(userContract[userAddress], supplyAmount);
        }
        callBorrowInternal(supplyAmount, borrowAmountUSDC, userAddress);
    }

    function callBorrow(uint supplyAmount, uint borrowAmountUSDC) external {
        require(IERC20(asset).transferFrom(msg.sender,address(this), supplyAmount), "Transfer Failed");
        if(!checkIfUserExist(msg.sender)){
            address userContractAddress = deployBTCContract(msg.sender);
            IERC20(asset).approve(userContractAddress, supplyAmount);
        }
        else{
            IERC20(asset).approve(userContract[msg.sender], supplyAmount);
        }
        callBorrowInternal(supplyAmount, borrowAmountUSDC, msg.sender);
    }

    function callBorrowInternal(uint supplyAmount, uint borrowAmountUSDC, address userAddress) internal {
        SimpleBTCBorrowV2 btcBorrow =  SimpleBTCBorrowV2(userContract[userAddress]);
        btcBorrow.borrow(userAddress, supplyAmount, borrowAmountUSDC);

        // Final State Update
        totalBorrow = totalBorrow.add(borrowAmountUSDC);
        totalSupplied = totalSupplied.add(supplyAmount);
        
        torqRewardsUtil.userDepositReward(userAddress, supplyAmount);
        torqRewardsUtil.userDepositBorrowReward(userAddress, borrowAmountUSDC);
        
        arbRewardsUtil.userDepositReward(userAddress, supplyAmount);
        arbRewardsUtil.userDepositBorrowReward(userAddress, borrowAmountUSDC);
    }

    function callRepay(uint borrowUSDC, uint256 WbtcWithdraw) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleBTCBorrowV2 btcBorrow =  SimpleBTCBorrowV2(userContract[msg.sender]);
        btcBorrow.repay(msg.sender, borrowUSDC, WbtcWithdraw);

        // Final State Update
        totalBorrow = totalBorrow.sub(borrowUSDC);
        totalSupplied = totalSupplied.sub(WbtcWithdraw);

        torqRewardsUtil.userWithdrawReward(msg.sender, WbtcWithdraw);
        torqRewardsUtil.userWithdrawBorrowReward(msg.sender, borrowUSDC);

        arbRewardsUtil.userWithdrawReward(msg.sender, WbtcWithdraw);
        arbRewardsUtil.userWithdrawBorrowReward(msg.sender, borrowUSDC);
    }

    function callWithdraw(uint withdrawAmount) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleBTCBorrowV2 btcBorrow =  SimpleBTCBorrowV2(userContract[msg.sender]);
        btcBorrow.withdraw(msg.sender, withdrawAmount);

        //Final State Update
        totalSupplied = totalSupplied.sub(withdrawAmount);
        
        torqRewardsUtil.userWithdrawReward(msg.sender, withdrawAmount);
        arbRewardsUtil.userWithdrawReward(msg.sender, withdrawAmount);
    }

    function callBorrowMore(uint borrowUSDC) external {
        require(checkIfUserExist(msg.sender), "Contract not created!");
        SimpleBTCBorrowV2 btcBorrow =  SimpleBTCBorrowV2(userContract[msg.sender]);
        btcBorrow.borrowMore(msg.sender, borrowUSDC);

        //Final State Update
        totalBorrow = totalBorrow.add(borrowUSDC);
        
        torqRewardsUtil.userDepositBorrowReward(msg.sender, borrowUSDC);
        arbRewardsUtil.userDepositBorrowReward(msg.sender, borrowUSDC);
    }

    function callClaimCReward(address _address) external onlyOwner(){
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrowV2 btcBorrow =  SimpleBTCBorrowV2(userContract[msg.sender]);
        btcBorrow.claimCReward();
    }

    function callTokenTransfer(address _userAddress, address _tokenAddress, address _toAddress, uint256 _deposit) external onlyOwner {
        require(checkIfUserExist(_userAddress), "Contract not created!");
        SimpleBTCBorrowV2 btcBorrow =  SimpleBTCBorrowV2(userContract[_userAddress]);
        btcBorrow.transferToken(_tokenAddress, _toAddress, _deposit);
    }

    function updateRewardsUtil(address _torqRewardsUtil, address _arbRewardsUtil) external onlyOwner() {
        torqRewardsUtil = RewardsUtil(_torqRewardsUtil);
        arbRewardsUtil = RewardsUtil(_arbRewardsUtil);
    }

    function updateTreasury(address _treasury) external onlyOwner() {
        treasury = _treasury;
    }

    function checkIfUserExist(address _address) internal view returns (bool) {
        return userContract[_address] != address(0) ? true : false;

    }

    function getUserDetails(address _address) external view returns (uint256, uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrowV2 btcBorrow =  SimpleBTCBorrowV2(userContract[_address]);
        return (btcBorrow.supplied(), btcBorrow.borrowed());
    }

    function getWbtcWithdrawWithSlippage(address _address, uint256 usdcRepay, uint256 _repaySlippage) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrowV2 btcBorrow =  SimpleBTCBorrowV2(userContract[_address]);
        return btcBorrow.getWbtcWithdrawWithSlippage(usdcRepay, _repaySlippage);
    }

    function getBorrowableUsdc(address _address, uint256 supply) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrowV2 btcBorrow =  SimpleBTCBorrowV2(userContract[_address]);
        return (btcBorrow.getBorrowableUsdc(supply));
    }

    function getMoreBorrowableUsdc(address _address) external view returns (uint256) {
        require(checkIfUserExist(_address), "Contract not created!");
        SimpleBTCBorrowV2 btcBorrow =  SimpleBTCBorrowV2(userContract[_address]);
        return (btcBorrow.getMoreBorrowableUsdc());
    }

    function addRefinanceContract(address _address) external onlyOwner {
        refinanceContract[_address] = true;
    }

}
