// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IWETH9.sol";

import "./strategies/UniswapComp.sol";

contract BoostComp is AutomationCompatible, Ownable, ReentrancyGuard, ERC20{
    using SafeMath for uint256;
    using Math for uint256;

    IERC20 public compToken;
    UniswapComp public uniswapComp;
    UniswapComp public sushiComp;

    address public treasury;
    uint256 public uniswapAllocation;
    uint256 public sushiAllocation;
    uint256 public lastCompoundTimestamp;
    uint256 public performanceFee;
    uint256 public minCompAmount = 20000;
    
    uint256 public totalAssetsAmount = 0;

    constructor(
        string memory _name,
        string memory _symbol,
        address _compAddress,
        address _uniswapCompAddress,
        address _sushiCompAddress,
        address _treasury
    ) ERC20(_name, _symbol) {
        compToken = IERC20(_compAddress);
        uniswapComp = UniswapComp(_uniswapCompAddress);
        sushiComp = UniswapComp(_sushiCompAddress);
        uniswapAllocation = 50;
        sushiAllocation = 50;
        treasury = _treasury;
    }

    function depositComp(uint256 depositAmount) external nonReentrant() {
        compToken.transferFrom(msg.sender, address(this), depositAmount);
        uint256 uniswapDepositAmount = depositAmount.mul(uniswapAllocation).div(100);
        uint256 sushiDepositAmount = depositAmount.sub(uniswapDepositAmount);
        compToken.approve(address(uniswapComp), uniswapDepositAmount);
        uniswapComp.deposit(uniswapDepositAmount);
        compToken.approve(address(sushiComp), sushiDepositAmount);
        sushiComp.deposit(sushiDepositAmount);
        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares);
        totalAssetsAmount = totalAssetsAmount + depositAmount;
    }

    function withdrawComp(uint256 sharesAmount) external nonReentrant() {
        uint256 withdrawAmount = _convertToAssets(sharesAmount);
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100);
        uint256 sushiWithdrawAmount = withdrawAmount.sub(uniswapWithdrawAmount);
        _burn(msg.sender, sharesAmount);
        uint256 totalUniswapAllocation = totalAssetsAmount.mul(uniswapAllocation).div(100);
        uint256 totalSushiAllocation = totalAssetsAmount.sub(totalUniswapAllocation);
        totalAssetsAmount = totalAssetsAmount - withdrawAmount;
        uniswapComp.withdraw(uint128(uniswapWithdrawAmount), totalUniswapAllocation);
        sushiComp.withdraw(uint128(sushiWithdrawAmount), totalSushiAllocation);
        uint256 compAmount = compToken.balanceOf(address(this));
        compToken.transfer(msg.sender, compAmount);
    }

    function compoundFees() external nonReentrant() {
        _compoundFees();
    }

    function _compoundFees() internal {
        uint256 prevCompAmount = compToken.balanceOf(address(this));
        uniswapComp.compound();
        sushiComp.compound();
        uint256 postCompAmount = compToken.balanceOf(address(this));
        if(postCompAmount < minCompAmount){
            return;
        }
        uint256 treasuryFee = (postCompAmount - prevCompAmount).mul(performanceFee).div(100);
        compToken.transfer(treasury, treasuryFee);
        uint256 compAmount = postCompAmount - treasuryFee;
        uint256 uniswapDepositAmount = compAmount.mul(uniswapAllocation).div(100);
        uint256 sushiDepositAmount = compAmount.sub(uniswapDepositAmount);
        totalAssetsAmount = totalAssetsAmount + compAmount;
        compToken.approve(address(uniswapComp), uniswapDepositAmount);
        uniswapComp.deposit(uniswapDepositAmount);
        compToken.approve(address(sushiComp), sushiDepositAmount);
        sushiComp.deposit(sushiDepositAmount);
        lastCompoundTimestamp = block.timestamp;
    }

    function setAllocation(uint256 _uniswapAllocation, uint256 _sushiAllocation) public onlyOwner(){
        require(_uniswapAllocation + _sushiAllocation == 100, "Allocation has to be exactly 100");
        uniswapAllocation = _uniswapAllocation;
        sushiAllocation = _sushiAllocation;
    }

    function setMinComp(uint256 _minComp) public onlyOwner() {
        minCompAmount = _minComp;
    }

    function setPerformanceFee(uint256 _performanceFee) public onlyOwner() {
        performanceFee = _performanceFee;
    }

    function setTreasury(address _treasury) public onlyOwner() {
        treasury = _treasury;
    }

    function totalAssets() public view returns (uint256) {
        return totalAssetsAmount;
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (assets==0 || supply==0) ? assets : assets.mulDiv(supply, totalAssets(), Math.Rounding.Down);
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256){
        uint256 supply = totalSupply();
        return (supply==0) ? shares : shares.mulDiv(totalAssets(), supply, Math.Rounding.Down);
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp >= lastCompoundTimestamp + 12 hours);
    }

    function performUpkeep(bytes calldata) external override {
        if ((block.timestamp >= lastCompoundTimestamp + 12 hours)) {
            _compoundFees();
        }
    }
}