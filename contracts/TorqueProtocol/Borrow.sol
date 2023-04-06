// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "../CompoundBase/IWETH9.sol";
import "../CompoundBase/bulkers/IBulker.sol";
import "../CompoundBase/IComet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Borrow  is UUPSUpgradeable, OwnableUpgradeable{
    using SafeMath for uint256;

    address public bucker;
    address public asset;
    address usdc;
    address comet;
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
    
    // constructor(address _comet, address _asset, address _usdc) {
    //     comet = _comet;
    //     asset = _asset;
    //     usdc = _usdc;
    // }
function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(address _comet, address _asset, address _usdc, address _bucker
    ) public initializer {
              comet = _comet;
        asset = _asset;
        usdc = _usdc;
        bucker = _bucker;
        IComet(comet).allow(_bucker, true);
        __Ownable_init();
    }


// Test only
    function setBulker(address _bulker) public {
        bulker = _bulker;
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
    function setAllowTo(address manager, bool _allow) public onlyOwner{
        IComet(comet).allow(manager, _allow);
    }
// End test

    function getBorrowable(uint amount, uint amountBorrow) public view{
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        uint maxBorrow = amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);
    }

    function borrow(uint amount, uint amountBorrow) public payable{
        IComet icomet = IComet(comet);

        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        uint maxBorrow = amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);

        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= amount, "borrow exceed");
        ERC20(asset).approve(comet, amount);
        ERC20(asset).approve(bucker, amount);
        require(ERC20(asset).transferFrom(msg.sender,address(this), amount), "transfer asset fail");

        userBorrowInfo.borrowed += amount;
        userBorrowInfo.supplied += amount;
        

        uint[] memory actions = new uint[](2);

        actions[0] = ACTION_SUPPLY_ASSET;
        actions[1] = ACTION_WITHDRAW_ASSET;

        bytes[] memory callData = new bytes[](2);

        bytes memory supplyAssetCalldata = abi.encode(comet, address(this), asset, amount);
        callData[0] = supplyAssetCalldata;

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), usdc, amountBorrow);
        callData[1] = withdrawAssetCalldata;

        IBulker(bulker).invoke(actions, callData);
        ERC20(usdc).transfer(msg.sender, amountBorrow);
    }


    function repay(uint amount, uint amountClaim) public payable{
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

        bytes memory withdrawAssetCalldata = abi.encode(comet, address(this), usdc, amountClaim);
        callData[1] = withdrawAssetCalldata;

        IBulker(bulker).invoke(actions, callData);
    }
}