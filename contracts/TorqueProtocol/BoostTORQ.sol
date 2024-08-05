// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./strategies/UniswapTORQ.sol";

interface TORQRewardUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
}

contract BoostTORQ is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;

    event Deposited(address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    
    IERC20 public torqToken;
    UniswapTORQ public uniswapTorq;
    address public treasury;
    TORQRewardUtil public torqRewardUtil;

    uint256 public gmxAllocation;
    uint256 public uniswapAllocation = 100;
    uint256 public lastTorqoundTimestamp;
    uint256 public performanceFee = 10;
    uint256 public minTorqAmount = 10e24;
    uint256 public treasuryFee = 0;

    uint256 public totalAssetsAmount = 0;
    uint256 public torqoundTorqAmount = 0;

    constructor(
    string memory _name, 
    string memory _symbol,
    address TORQ,
    address _uniswapTorqAddress,
    address _treasury,
    address _torqRewardUtil
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        torqToken = IERC20(TORQ);
        uniswapTorq = UniswapTORQ(_uniswapTorqAddress);
        treasury = _treasury;
        torqRewardUtil = TORQRewardUtil(_torqRewardUtil);
    }

    function depositTORQ(uint256 depositAmount) external payable nonReentrant() {
        require(torqToken.balanceOf(address(this)) >= torqoundTorqAmount, "Insufficient torqound balance");
        require(torqToken.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");
        uint256 uniswapDepositAmount = depositAmount + torqoundTorqAmount;
        torqoundTorqAmount = 0;
        torqToken.approve(address(uniswapTorq), uniswapDepositAmount);
        uniswapTorq.deposit(uniswapDepositAmount);

        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares);
        totalAssetsAmount = totalAssetsAmount.add(uniswapDepositAmount);
        torqRewardUtil.userDepositReward(msg.sender, shares);
        emit Deposited(msg.sender, depositAmount, shares);
    }

    function withdrawTORQ(uint256 sharesAmount) external nonReentrant() {
        uint256 withdrawAmount = _convertToAssets(sharesAmount);
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100);
        _burn(msg.sender, sharesAmount);
        uint256 totalUniSwapAllocation = totalAssetsAmount.mul(uniswapAllocation).div(100);
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount);

        uint256 prevTorqAmount = torqToken.balanceOf(address(this));
        
        if(uniswapWithdrawAmount > 0) {
            uniswapTorq.withdraw(uint128(uniswapWithdrawAmount), totalUniSwapAllocation);
        }
        
        uint256 postTorqAmount = torqToken.balanceOf(address(this));
        uint256 torqAmount = postTorqAmount - prevTorqAmount;
        require(torqToken.transfer(msg.sender, torqAmount), "Transfer Asset Failed");
        torqRewardUtil.userWithdrawReward(msg.sender, sharesAmount);
        emit Withdrawn(msg.sender, torqAmount, sharesAmount);
    }

    function torqoundFees() external nonReentrant(){
        _torqoundFees();
    }

    function _torqoundFees() internal {
        uint256 prevTorqAmount = torqToken.balanceOf(address(this));
        uniswapTorq.compound(); 
        uint256 postTorqAmount = torqToken.balanceOf(address(this));
        uint256 treasuryAmount = (postTorqAmount - prevTorqAmount).mul(performanceFee).div(1000);
        treasuryFee = treasuryFee.add(treasuryAmount);
        if(treasuryFee >= minTorqAmount){
            require(torqToken.transfer(treasury , treasuryFee), "Transfer Asset Failed");
            treasuryFee = 0;
        }
        uint256 torqAmount = postTorqAmount - prevTorqAmount - treasuryAmount;
        torqoundTorqAmount += torqAmount;
        lastTorqoundTimestamp = block.timestamp;
    }

    function setMinTorq(uint256 _minTorq) public onlyOwner() {
        minTorqAmount = _minTorq;
    }

    function setPerformanceFee(uint256 _performanceFee) public onlyOwner {
        require(_performanceFee <= 1000, "Treasury Fee can't be more than 100%");
        performanceFee = _performanceFee;
    }

    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function withdrawTreasuryFees() external onlyOwner() {
        payable(treasury).transfer(address(this).balance);
    }

    function decimals() public view override returns (uint8) {
        return 18;
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (assets==0 || supply==0) ? assets : assets.mulDiv(supply, totalAssets(), Math.Rounding.Down);
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256){
        uint256 supply = totalSupply();
        return (supply==0) ? shares : shares.mulDiv(totalAssets(), supply, Math.Rounding.Down);
    }

    function totalAssets() public view returns (uint256) {
        return totalAssetsAmount;
    }

    function updateTORQRewardUtil(address _torqRewardUtil) external onlyOwner() {
        torqRewardUtil = TORQRewardUtil(_torqRewardUtil);
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp >= lastTorqoundTimestamp + 12 hours);
    }

    function performUpkeep(bytes calldata) external override {
        if ((block.timestamp >= lastTorqoundTimestamp + 12 hours)) {
            _torqoundFees();
        }
    }

    receive() external payable {}
}
