// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "../CompoundBase/IWETH9.sol";
import "../CompoundBase/bulkers/IBulker.sol";
import "../CompoundBase/IComet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract Borrow  is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable{
    using SafeMath for uint256;

    address public bulker;
    address public asset;
    address public baseAsset;
    address public comet;
    uint public constant ACTION_SUPPLY_ASSET = 1;
    uint public constant ACTION_SUPPLY_ETH = 2;
    uint public constant ACTION_TRANSFER_ASSET = 3;
    uint public constant ACTION_WITHDRAW_ASSET = 4;
    uint public constant ACTION_WITHDRAW_ETH = 5;
    uint public constant ACTION_CLAIM_REWARD = 6;
    uint constant BASE_ASSET_MANTISA = 1e6;
    uint constant PRICE_MANTISA = 1e2;
    uint constant SCALE = 1e18;

    struct BorrowInfo {
        address user;
        uint borrowed;
        uint supplied;

        uint accruedInterest;
        uint borrowTime;
    }
    struct BorrowSnapshoot {
        uint amount;
        uint borrowTime;
    }

    mapping(address => BorrowInfo) public borrowInfoMap;
    event UserBorrow(address user, address collateralAddress, uint amount);
    event UserRepay(address user, address collateralAddress, uint repayAmount, uint claimAmount);
    
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(address _comet, address _asset, address _baseAsset, address _bulker) public initializer {
        comet = _comet;
        asset = _asset;
        baseAsset = _baseAsset;
        bulker = _bulker;
        IComet(comet).allow(_bulker, true);
        __Ownable_init();
        __ReentrancyGuard_init();
    }


// Test only
    function setBulker(address _bulker) public onlyOwner{
        bulker = _bulker;
    }
    function setasset(address _asset) public onlyOwner{
        asset = payable(_asset);
    }
    
    function setComet(address _comet) public onlyOwner{
        comet = _comet;
    }
    function allow(address _asset, address spender, uint amount) public onlyOwner{
        ERC20(_asset).approve(spender, amount);
    }
    function setAllowTo(address manager, bool _allow) public onlyOwner{
        IComet(comet).allow(manager, _allow);
    }
// End test

    function getBorrowable(uint amount) public view returns (uint){
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        return amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);
    }

    function borrow(uint supplyAmount, uint borrowAmount) public nonReentrant(){
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        uint maxBorrow = supplyAmount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);

        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= supplyAmount, "borrow cap exceed");
        require(ERC20(asset).transferFrom(msg.sender, address(this), supplyAmount), "transfer asset fail");

        if(userBorrowInfo.borrowed > 0) {
            uint accruedInterest = calculateInterest(userBorrowInfo.borrowed, userBorrowInfo.borrowTime);
            userBorrowInfo.accruedInterest += accruedInterest;
        }

        userBorrowInfo.borrowed = userBorrowInfo.borrowed.add(borrowAmount);
        userBorrowInfo.supplied = userBorrowInfo.supplied.add(supplyAmount);
        userBorrowInfo.borrowTime = block.timestamp;
        

        uint[] memory actions = new uint[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, supplyAmount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), baseAsset, borrowAmount);
        callData[1] = withdrawAssetCalldata;

        ERC20(asset).approve(comet, supplyAmount);
        IBulker(bulker).invoke(actions, callData);
        
        ERC20(baseAsset).transfer(msg.sender, borrowAmount);
    }


    function repay(uint borrowAmount) public nonReentrant(){
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        require(userBorrowInfo.borrowed >= borrowAmount, "exceed current borrowed amount");

        uint supplyAmount = userBorrowInfo.supplied.mul(borrowAmount).div(userBorrowInfo.borrowed);
        uint extraInterest = userBorrowInfo.accruedInterest.mul(borrowAmount).div(userBorrowInfo.borrowed);

        uint interest = calculateInterest(borrowAmount, userBorrowInfo.borrowTime) + extraInterest;

        uint repayAmount = borrowAmount + interest;
        require(ERC20(baseAsset).transferFrom(msg.sender,address(this), repayAmount), "transfer asset fail");

        uint[] memory actions = new uint[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), baseAsset, repayAmount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), asset, supplyAmount);
        callData[1] = withdrawAssetCalldata;

        ERC20(baseAsset).approve(comet, repayAmount);
        IBulker(bulker).invoke(actions, callData);

        userBorrowInfo.borrowed = userBorrowInfo.borrowed.sub(borrowAmount);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(supplyAmount);
        userBorrowInfo.accruedInterest = userBorrowInfo.accruedInterest.sub(extraInterest);

        ERC20(asset).transfer(msg.sender, supplyAmount);
    }
    function borrowBalanceOf(address user) public view returns (uint) {
        
        BorrowInfo storage userBorrowInfo = borrowInfoMap[user];
        if(userBorrowInfo.borrowed == 0) {
            return 0;
        }

        uint borrowAmount = userBorrowInfo.borrowed;
        uint extraInterest = userBorrowInfo.accruedInterest.mul(borrowAmount).div(userBorrowInfo.borrowed);

        uint interest = calculateInterest(borrowAmount, userBorrowInfo.borrowTime) + extraInterest;

        return borrowAmount + interest;
    }

    function partialBorrowBalanceOf(address user, uint borrowAmount) public view returns (uint) {
        
        BorrowInfo storage userBorrowInfo = borrowInfoMap[user];
        if(userBorrowInfo.borrowed == 0) {
            return 0;
        }

        uint extraInterest = userBorrowInfo.accruedInterest.mul(borrowAmount).div(userBorrowInfo.borrowed);

        uint interest = calculateInterest(borrowAmount, userBorrowInfo.borrowTime) + extraInterest;

        return borrowAmount + interest;
    }

    function calculateInterest(uint borrowAmount, uint borrowTime) public view returns (uint) {
        IComet icomet = IComet(comet);
        uint totalSecond = block.timestamp - borrowTime;
        return borrowAmount.mul(icomet.getBorrowRate(icomet.getUtilization())).mul(totalSecond).div(1e18);
    }
}