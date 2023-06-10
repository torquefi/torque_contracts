// SPDX-License: MIT
pragma solidity ^0.8.15;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Marketplace {
    // User => NFT contract => NFT ID => Info
    // mapping(address => mapping(address => mapping(uint256 => AuctionInfor))) public _auctionMapping;
    AuctionInfor[] public auctionInfoSet;
    mapping(address => uint256) public _auctionMapping;
    bool enter;
    modifier isOwner(address _nftContract, uint256 _nftId) {
        IERC721 NFT = IERC721(_nftContract);
        address owner = NFT.ownerOf(_nftId);
        require(msg.sender == owner, "Not owner");
        _;
    }

    event CreateAuction(address lister, address nftContract, uint256 nftId);
    struct AuctionInfor {
        address lister;
        address nftContract;
        uint256 nftId;
        uint256 startTime;
        uint256 endTime;
        address paymentToken;
        uint256 initialPrice;
        uint256 stepAmount;
    }

    function createAuction(
        uint256 _nftId,
        address _nftContract,
        uint256 _startTime,
        uint256 _endTime,
        address _paymentToken,
        uint256 _initialPrice,
        uint256 _stepAmount
    ) public isOwner(_nftContract, _nftId) {
        IERC721 NFT = IERC721(_nftContract);
        address owner = NFT.ownerOf(_nftId);
        AuctionInfor memory auctionInfo = AuctionInfor({
            lister: owner,
            nftContract: _nftContract,
            nftId: _nftId,
            startTime: _startTime,
            endTime: _endTime,
            paymentToken: _paymentToken,
            initialPrice: _initialPrice,
            stepAmount: _stepAmount
        });
        auctionInfoSet.push(auctionInfo);

        _auctionMapping[owner] = auctionInfoSet.length;

        NFT.transferFrom(owner, address(this), _nftId);

        emit CreateAuction(owner, _nftContract, _nftId);
    }
}
