// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/IWETH9.sol";
import "./strategies/GMXV2ETH.sol";
import "./strategies/StargateETH.sol";

contract BoostETH is Ownable, ReentrancyGuard, ERC4626{
    using SafeMath for uint256;

    IWETH9 public weth;
    GMXV2ETH public gmxV2ETH;
    StargateETH public stargateETH;
    address public treasury;

    uint256 public gmxAllocation;
    uint256 public stargateAllocation;
    uint256 public lastCompoundTimestamp;
    uint256 public performanceFee;

    address payable private constant  WETH = payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor(IERC20 asset_, string memory _name, string memory _symbol, address gmxV2ETH_, address stargateETH_, address treasury_) ERC4626(asset_) ERC20(_name, _symbol){
        weth = IWETH9(WETH);
        gmxV2ETH = GMXV2ETH(gmxV2ETH_);
        stargateETH = StargateETH(stargateETH_);
        treasury = treasury_;
        gmxAllocation = 50;
        stargateAllocation = 50;
        performanceFee = 10;
    }

    function depositETH(uint256 depositAmount) external payable {
        weth.deposit{value: depositAmount}();
        uint256 stargateDepositAmount = depositAmount.mul(stargateAllocation).div(100);
        uint256 gmxDepositAmount = depositAmount.sub(stargateDepositAmount);
        weth.approve(address(stargateETH), stargateDepositAmount);
        stargateETH.deposit(stargateDepositAmount);
        weth.approve(address(gmxV2ETH), gmxDepositAmount);
        gmxV2ETH.deposit(gmxDepositAmount);
        uint256 shares = _convertToShares(depositAmount, Math.Rounding.Down);
        _mint(msg.sender, shares);
    }

    function withdrawETH(uint256 sharesAmount) external {
        uint256 withdrawAmount = _convertToAssets(sharesAmount, Math.Rounding.Down);
        uint256 stargateWithdrawAmount = withdrawAmount.mul(stargateAllocation).div(100);
        uint256 gmxWithdrawAmount = withdrawAmount.sub(stargateWithdrawAmount);
        _burn(msg.sender, sharesAmount);
        stargateETH.withdraw(stargateWithdrawAmount);
        gmxV2ETH.withdraw(gmxWithdrawAmount);
        weth.withdraw(withdrawAmount);
        payable(msg.sender).transfer(withdrawAmount);
    }

    function compoundFees() external {
        // uint256 gmxEthBalanceBefore = 
    }

    function setAllocation(uint256 _stargateAllocation, uint256 _gmxAllocation) public onlyOwner {
        require((_stargateAllocation + _gmxAllocation)==100, "All allocation should be 100");
        gmxAllocation = _gmxAllocation;
        stargateAllocation = _stargateAllocation;
    }

    function setPerformanceFee(uint256 _performanceFee) public onlyOwner {
        performanceFee = _performanceFee;
    }

    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }
}