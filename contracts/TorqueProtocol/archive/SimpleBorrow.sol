// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "../interfaces/IWETH9.sol";
import "../interfaces/IBulker.sol";
import "../interfaces/IComet.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SimpleBorrow is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    address public bulker = 0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d; // 0xf82AAB8ae0E7F6a2ecBfe2375841d83AeA4cb9cE
    address public asset = 0x82af49447d8a07e3bd95bd0d56f35241523fbab1; // 0xAAD4992D949f9214458594dF92B44165Fb84dC19
    address usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // 0x07865c6E87B9F70255377e024ace6630C1Eaa37F
    address comet = 0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf; // 0x3EE77595A8459e93C2888b13aDB354017B198188

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

    function borrow(uint amount, uint amountBorrow) public payable nonReentrant {
        IComet icomet = IComet(comet);
        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        uint maxBorrow = amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        uint borrowable = maxBorrow.sub(userBorrowInfo.borrowed);
        require(borrowable >= amount, "Borrow exceeded");
        ERC20(asset).approve(comet, amount);
        require(
            ERC20(asset).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
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
        IBulker(bulker).invoke(actions, callData);
    }

    function repay(uint amount, uint amountClaim) public payable nonReentrant {
        BorrowInfo storage userBorrowInfo = borrowInfoMap[msg.sender];
        require(userBorrowInfo.borrowed <= amount, "Borrow exceeded");
        require(userBorrowInfo.supplied >= amountClaim, "Supply exceeded");
        require(ERC20(usdc).transferFrom(msg.sender, address(this), amount), "Transfer failed");
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
        IBulker(bulker).invoke(actions, callData);
    }

    function getBorrowable(uint amount, uint amountBorrow) public view {
        IComet icomet = IComet(comet);
        AssetInfo memory info = icomet.getAssetInfo(0);
        uint price = icomet.getPrice(info.priceFeed);
        uint maxBorrow = amount.mul(info.borrowCollateralFactor).mul(price).div(PRICE_MANTISA).div(SCALE);
    }
}
