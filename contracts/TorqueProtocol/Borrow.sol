// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "../CompoundBase/IWETH9.sol";
import "../CompoundBase/bulkers/IBucker.sol";
import "../CompoundBase/IComet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Borrow is ReentrancyGuard{
    using SafeMath for uint256;

    address public bucker =0xf82AAB8ae0E7F6a2ecBfe2375841d83AeA4cb9cE;
    address public asset = 0xAAD4992D949f9214458594dF92B44165Fb84dC19;
    address usdc = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;
    address comet = 0x3EE77595A8459e93C2888b13aDB354017B198188;
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
    }

    mapping(address => BorrowInfo) public borrowInfoMap;
    
    constructor(address _comet, address _asset, address _usdc) {
        comet = _comet;
        asset = _asset;
        usdc = _usdc;
    }



// Test only
    function setBucker(address _bulker) public {
        bucker = _bulker;
    }
    function setasset(address _asset) public {
        asset = payable(_asset);
    }
    
    function setComet(address _comet) public {
        comet = _comet;
    }
    function allow(address _asset, address spender, uint amount) public{
        ERC20(_asset).approve(spender, amount);
    }
// End test

    function getBorrowable(uint amount, uint amountBorrow) public view{
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        uint maxBorrow = amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);
    }
    function borrow1(uint amount, uint amountBorrow) public payable nonReentrant{
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        uint maxBorrow = amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);

        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= amount, "borrow exceed");
        ERC20(asset).approve(comet, amount);
    }
    function borrow2(uint amount, uint amountBorrow) public payable nonReentrant{
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        uint maxBorrow = amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);

        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= amount, "borrow exceed");
        ERC20(asset).approve(comet, amount);
        require(ERC20(asset).transferFrom(msg.sender,address(this), amount), "transfer asset fail");

        userBorrowInfo.borrowed += amount;
        userBorrowInfo.supplied += amount;
    }
    function borrow3(uint amount, uint amountBorrow) public payable nonReentrant{
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        uint maxBorrow = amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);

        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= amount, "borrow exceed");
        ERC20(asset).approve(comet, amount);
        require(ERC20(asset).transferFrom(msg.sender,address(this), amount), "transfer asset fail");

        userBorrowInfo.borrowed += amount;
        userBorrowInfo.supplied += amount;
        uint[] memory actions = new uint[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, amount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, msg.sender, usdc, amountBorrow);
        callData[1] = withdrawAssetCalldata;
    }
    function borrow(uint amount, uint amountBorrow) public payable nonReentrant{
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        uint maxBorrow = amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);

        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= amount, "borrow exceed");
        ERC20(asset).approve(comet, amount);
        require(ERC20(asset).transferFrom(msg.sender,address(this), amount), "transfer asset fail");

        userBorrowInfo.borrowed += amount;
        userBorrowInfo.supplied += amount;
        

        uint[] memory actions = new uint[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, amount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, msg.sender, usdc, amountBorrow);
        callData[1] = withdrawAssetCalldata;

        IBucker(bucker).invoke(actions, callData);
    }


    function repay1(uint amount, uint amountClaim) public payable nonReentrant{
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        require(userBorrowInfo.borrowed <= amount, "borrow exceed");
        require(userBorrowInfo.supplied >= amountClaim, "supply exceed");
        require(ERC20(usdc).transferFrom(msg.sender,address(this), amount), "transfer asset fail");
    }
    function repay2(uint amount, uint amountClaim) public payable nonReentrant{
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        require(userBorrowInfo.borrowed <= amount, "borrow exceed");
        require(userBorrowInfo.supplied >= amountClaim, "supply exceed");
        require(ERC20(usdc).transferFrom(msg.sender,address(this), amount), "transfer asset fail");

        userBorrowInfo.borrowed = userBorrowInfo.borrowed.sub(amount);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(amountClaim);

        uint[] memory actions = new uint[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), usdc, amount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, msg.sender, usdc, amountClaim);
        callData[1] = withdrawAssetCalldata;

    }
    function repay(uint amount, uint amountClaim) public payable nonReentrant{
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        require(userBorrowInfo.borrowed <= amount, "borrow exceed");
        require(userBorrowInfo.supplied >= amountClaim, "supply exceed");
        require(ERC20(usdc).transferFrom(msg.sender,address(this), amount), "transfer asset fail");

        userBorrowInfo.borrowed = userBorrowInfo.borrowed.sub(amount);
        userBorrowInfo.supplied = userBorrowInfo.supplied.sub(amountClaim);

        uint[] memory actions = new uint[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), usdc, amount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, msg.sender, usdc, amountClaim);
        callData[1] = withdrawAssetCalldata;

        IBucker(bucker).invoke(actions, callData);
    }
}