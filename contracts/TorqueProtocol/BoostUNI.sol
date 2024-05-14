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

interface GMXUNI {
    function deposit(uint256 _amount) external payable;
    function withdraw(uint256 _amount, address _userAddress) external payable;
    function compound() external;
}

interface UNIUniswap { 
    function deposit(uint256 _amount) external;
    function withdraw(uint128 withdrawAmount, uint256 totalAllocation) external;
    function compound() external;
}

interface RewardsUtil {
    function userDepositReward(address _userAddress, uint256 _depositAmount) external;
    function userWithdrawReward(address _userAddress, uint256 _withdrawAmount) external;
}

contract BoostUNI is AutomationCompatible, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Math for uint256;
    
    IERC20 public uniToken;
    GMXUNI public gmxV2Uni;
    UNIUniswap public uniswapUni;
    address public treasury;
    RewardsUtil public rewardsUtil;

    uint256 public gmxAllocation;
    uint256 public uniswapAllocation;
    uint256 public lastCompoundTimestamp;
    uint256 public performanceFee = 10;
    uint256 public minUniAmount = 1000000000000000000;
    uint256 public treasuryFee = 0;

    uint256 public totalAssetsAmount = 0;
    uint256 public compoundUniAmount = 0;

    constructor(
    string memory _name, 
    string memory _symbol,
    address _uniToken,
    address payable _gmxV2UniAddress,
    address _uniswapUniAddress,
    address _treasury,
    address _rewardsUtil
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        uniToken = IERC20(_uniToken);
        gmxV2Uni = GMXUNI(_gmxV2UniAddress);
        uniswapUni = UNIUniswap(_uniswapUniAddress);
        gmxAllocation = 50;
        uniswapAllocation = 50;
        treasury = _treasury;
        rewardsUtil = RewardsUtil(_rewardsUtil);
    }

    function depositUNI(uint256 depositAmount) external payable nonReentrant() {
        require(msg.value > 0, "Please pass GMX execution fees");
        require(uniToken.balanceOf(address(this)) >= compoundUniAmount, "Insufficient compound balance");
        require(uniToken.transferFrom(msg.sender, address(this), depositAmount), "Transfer Asset Failed");
        uint256 depositAndCompound = depositAmount + compoundUniAmount;
        compoundUniAmount = 0;
        uint256 uniswapDepositAmount = depositAndCompound.mul(uniswapAllocation).div(100);
        uint256 gmxDepositAmount = depositAndCompound.sub(uniswapDepositAmount);
        uniToken.approve(address(uniswapUni), uniswapDepositAmount);
        uniswapUni.deposit(uniswapDepositAmount);

        uniToken.approve(address(gmxV2Uni), gmxDepositAmount);
        gmxV2Uni.deposit{value: msg.value}(gmxDepositAmount);

        uint256 shares = _convertToShares(depositAmount);
        _mint(msg.sender, shares);
        totalAssetsAmount = totalAssetsAmount.add(depositAndCompound);
        rewardsUtil.userDepositReward(msg.sender, shares);
    }

    function withdrawUNI(uint256 sharesAmount) external payable nonReentrant() {
        require(msg.value > 0, "Please pass GMX execution fees");
        uint256 withdrawAmount = _convertToAssets(sharesAmount);
        uint256 uniswapWithdrawAmount = withdrawAmount.mul(uniswapAllocation).div(100);
        uint256 gmxWithdrawAmount = withdrawAmount.sub(uniswapWithdrawAmount);
        _burn(msg.sender, sharesAmount);
        uint256 totalUniSwapAllocation = totalAssetsAmount.mul(uniswapAllocation).div(100);
        totalAssetsAmount = totalAssetsAmount.sub(withdrawAmount);

        uint256 prevUniAmount = uniToken.balanceOf(address(this));
        uniswapUni.withdraw(uint128(uniswapWithdrawAmount), totalUniSwapAllocation);
        gmxV2Uni.withdraw{value: msg.value}(gmxWithdrawAmount, msg.sender);
        uint256 postUniAmount = uniToken.balanceOf(address(this));
        uint256 uniAmount = postUniAmount - prevUniAmount;
        require(uniToken.transfer(msg.sender, uniAmount), "Transfer Asset Failed");
        rewardsUtil.userWithdrawReward(msg.sender, sharesAmount);
    }

    function compoundFees() external nonReentrant(){
        _compoundFees();
    }

    function _compoundFees() internal {
        uint256 prevUniAmount = uniToken.balanceOf(address(this));
        uniswapUni.compound(); 
        gmxV2Uni.compound();
        uint256 postUniAmount = uniToken.balanceOf(address(this));
        uint256 treasuryAmount = (postUniAmount - prevUniAmount).mul(performanceFee).div(1000);
        treasuryFee = treasuryFee.add(treasuryAmount);
        if(treasuryFee >= minUniAmount){
            require(uniToken.transfer(treasury , treasuryFee), "Transfer Asset Failed");
            treasuryFee = 0;
        }
        uint256 uniAmount = postUniAmount - prevUniAmount - treasuryAmount;
        compoundUniAmount += uniAmount;
        lastCompoundTimestamp = block.timestamp;
    }

    function setAllocation(uint256 _gmxAllocation, uint256 _uniswapAllocation) public onlyOwner {
        require(_gmxAllocation + _uniswapAllocation == 100, "Allocation has to be exactly 100");
        gmxAllocation = _gmxAllocation;
        uniswapAllocation = _uniswapAllocation;
    }

    function setMinUni(uint256 _minUni) public onlyOwner() {
        minUniAmount = _minUni;
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

    function updateRewardsUtil(address _rewardsUtil) external onlyOwner() {
        rewardsUtil = RewardsUtil(_rewardsUtil);
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp >= lastCompoundTimestamp + 12 hours);
    }

    function performUpkeep(bytes calldata) external override {
        if ((block.timestamp >= lastCompoundTimestamp + 12 hours)) {
            _compoundFees();
        }
    }

    receive() external payable {}
}
