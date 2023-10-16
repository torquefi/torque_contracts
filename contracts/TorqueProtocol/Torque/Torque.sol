// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Torque is Ownable, ERC20, ERC20Burnable, ERC20Votes, ERC20Permit {

    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 private constant RESERVE = 180_000_000 ether;
    uint256 private constant DISTRIBUTION = 820_000_000 ether;
    uint256 public constant MAX_BUY = 1_000_000 ether;
    uint256 public constant DEADBLOCK_COUNT = 3;

    mapping(address => bool) private whitelist;
    mapping(address => bool) private poolList;
    mapping(address => uint) private _lastBlockTransfer;

    uint256 public deadblockStart;
    bool private _blockContracts;
    bool private _limitBuys;
    bool private _unrestricted;

    event LiquidityPoolSet(address);

    constructor(address _treasury) ERC20("Torque", "TORQ") ERC20Permit("Torque") {
        whitelist[msg.sender] = true;
        whitelist[_treasury] = true;

        require(RESERVE + DISTRIBUTION == TOTAL_SUPPLY, "Incorrect supply distribution");

        _mint(_treasury, RESERVE);
        _mint(msg.sender, DISTRIBUTION);

        _blockContracts = true;
        _limitBuys = true;
    }

    function setPools(address[] calldata _val) external onlyOwner {
        for (uint256 i = 0; i < _val.length; i++) {
            poolList[_val[i]] = true;
            emit LiquidityPoolSet(_val[i]);
        }
    }

    function setAddressToWhiteList(address _address, bool _allow) external onlyOwner {
        whitelist[_address] = _allow;
    }

    function setBlockContracts(bool _val) external onlyOwner {
        _blockContracts = _val;
    }

    function setLimitBuys(bool _val) external onlyOwner {
        _limitBuys = _val;
    }

    function renounceTorque() external onlyOwner {
        _unrestricted = true;
        renounceOwnership();
    }

    function _isContract(address _address) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }

    function _checkIfBot(address _address) internal view returns (bool) {
        return (block.number < DEADBLOCK_COUNT + deadblockStart || _isContract(_address)) && !whitelist[_address];
    }

    function _beforeTokenTransfer(address sender, address recipient, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._beforeTokenTransfer(sender, recipient, amount);

        if (amount == 0) {
            revert("Zero transfers not allowed");
        }

        if (_unrestricted) {
            return;
        }

        if (block.number == _lastBlockTransfer[sender] || block.number == _lastBlockTransfer[recipient]) {
            revert("Same block transfers not allowed");
        }

        bool isBuy = poolList[sender];
        bool isSell = poolList[recipient];

        if (isBuy) {
            if (_blockContracts && _checkIfBot(recipient)) {
                revert("Bots not allowed");
            }

            if (_limitBuys && amount > MAX_BUY) {
                revert("Max buy limit exceeded");
            }

            _lastBlockTransfer[recipient] = block.number;
        } else if (isSell) {
            _lastBlockTransfer[sender] = block.number;
        }
    }
}
