// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPair.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IStakingTorque.sol";

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

contract USDFarming is Ownable {
    using SafeMath for uint256;
    using SafeMath for uint112;

    uint256 constant RATE_PRECISION = 10000;
    uint256 constant ONE_YEAR_IN_SECONDS = 365 days;
    uint256 constant ONE_DAY_IN_SECONDS = 1 days;
    uint256 cooldownTime = 7 days;
    address public USDT;
    uint256 public lpTorqStake;
    uint256 public torqDistribute;

    uint256 constant PERIOD_PRECISION = 10000;
    IERC20 public token;
    IStakingTorque public sTorque;
    IRouter public router;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    struct StakeDetail {
        uint256 principal;
        uint256 lastProcessAt;
        uint256 pendingReward;
        uint256 firstStakeAt;
    }

    mapping(address => uint256) public apr;
    mapping(address => bool) public enabled;
    mapping(address => mapping(address => StakeDetail)) public stakers;

    constructor(address _router, address _token, address _sTorqueToken) {
        router = IRouter(_router);
        token = IERC20(_token);
        sTorque = IStakingTorque(_sTorqueToken);
    }

    function updateRouter(address _router) public onlyOwner {
        router = IRouter(_router);
    }

    function updateUSDT(address _usdt) public onlyOwner {
        USDT = _usdt;
    }

    function setEnabled(bool _enabled, address _lptoken) external onlyOwner {
        enabled[_lptoken] = _enabled;
    }

    function updateAPR(uint256 _apr, address _lptoken) external onlyOwner {
        apr[_lptoken] = _apr;
    }

    function emergencyWithdraw(uint256 _amount) external onlyOwner {
        token.transfer(msg.sender, _amount);
    }

    function setCooldownTime(uint256 _cooldownTime) public onlyOwner {
        cooldownTime = _cooldownTime;
    }

    function getStakeDetail(
        address _staker,
        address _lptoken
    )
        public
        view
        returns (
            uint256 principal,
            uint256 lastProcessAt,
            uint256 pendingReward,
            uint256 firstStakeAt
        )
    {
        StakeDetail memory stakeDetail = stakers[_staker][_lptoken];
        return (
            stakeDetail.principal,
            stakeDetail.lastProcessAt,
            stakeDetail.pendingReward,
            stakeDetail.firstStakeAt
        );
    }

    function getInterest(address _staker, address _lptoken) public view returns (uint256) {
        uint256 timestamp = block.timestamp;
        return previewInterest(_staker, timestamp, _lptoken);
    }

    function previewInterest(
        address _staker,
        uint256 _timestamp,
        address _lptoken
    ) public view returns (uint256) {
        StakeDetail memory stakeDetail = stakers[_staker][_lptoken];
        uint256 duration = _timestamp.sub(stakeDetail.lastProcessAt);
        uint256 interest = stakeDetail
            .principal
            .mul(apr[_lptoken])
            .mul(duration)
            .div(ONE_YEAR_IN_SECONDS)
            .div(RATE_PRECISION);
        return interest;
    }

    function getTokenRewardInterest(
        address _staker,
        address _lptoken
    ) external view returns (uint256) {
        return
            getInterest(_staker, _lptoken).mul(getPairPrice(_lptoken)).div(1e18).add(
                stakers[_staker][_lptoken].pendingReward
            );
    }

    function deposit(address _lptoken, uint256 _stakeAmount) external {
        require(enabled[_lptoken], "Staking is not enabled");
        require(_stakeAmount > 0, "USDFarming: stake amount must be greater than 0");
        IPair pair = IPair(_lptoken);
        pair.transferFrom(msg.sender, address(this), _stakeAmount);
        StakeDetail storage stakeDetail = stakers[msg.sender][_lptoken];
        if (stakeDetail.firstStakeAt == 0) {
            stakeDetail.principal = stakeDetail.principal.add(_stakeAmount);
            stakeDetail.firstStakeAt = stakeDetail.firstStakeAt == 0
                ? block.timestamp
                : stakeDetail.firstStakeAt;
        } else {
            stakeDetail.principal = stakeDetail.principal.add(_stakeAmount);
        }
        stakeDetail.lastProcessAt = block.timestamp;
        emit Deposit(msg.sender, _stakeAmount);
        sTorque.mint(_msgSender(), _stakeAmount.mul(2));
        lpTorqStake = lpTorqStake.add(_stakeAmount);
    }

    function getPairPrice(address _lptoken) public view returns (uint256) {
        uint112 reserve0;
        uint112 reserve1;
        IPair pair = IPair(_lptoken);
        (reserve0, reserve1, ) = pair.getReserves();

        uint256 totalPoolValue = reserve1.mul(2);
        uint256 mintedPair = pair.totalSupply();
        uint256 pairPriceInETH = totalPoolValue.mul(1e18).div(mintedPair);
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);
        uint256[] memory amounts = router.getAmountsOut(pairPriceInETH, path);
        return amounts[1];
    }

    function redeem(address _lptoken, uint256 _redeemAmount) external {
        require(enabled[_lptoken], "Staking is not enabled");
        StakeDetail storage stakeDetail = stakers[msg.sender][_lptoken];
        require(stakeDetail.firstStakeAt > 0, "USDFarming: no stake");
        require(
            stakeDetail.lastProcessAt + cooldownTime <= block.timestamp,
            "Not reach cool down time"
        );
        IPair pair = IPair(_lptoken);
        uint256 interest = getInterest(msg.sender, _lptoken);
        uint256 claimAmount = interest.mul(_redeemAmount).div(stakeDetail.principal);
        uint256 claimAmountInToken = claimAmount.mul(getPairPrice(_lptoken)).div(1e18);

        uint256 remainAmount = interest.sub(claimAmount);
        uint256 remainAmountInToken = remainAmount.mul(getPairPrice(_lptoken)).div(1e18);

        stakeDetail.lastProcessAt = block.timestamp;
        require(
            stakeDetail.principal >= _redeemAmount,
            "USDFarming: redeem amount must be less than principal"
        );
        stakeDetail.pendingReward = remainAmountInToken;
        stakeDetail.principal = stakeDetail.principal.sub(_redeemAmount);
        require(pair.transfer(msg.sender, _redeemAmount), "USDFarming: transfer failed");
        require(
            token.transfer(msg.sender, claimAmountInToken),
            "USDFarming: reward transfer failed"
        );
        emit Redeem(msg.sender, _redeemAmount);

        sTorque.transferFrom(_msgSender(), address(this), _redeemAmount.mul(2));
        sTorque.burn(address(this), _redeemAmount.mul(2));
        lpTorqStake = lpTorqStake.sub(_redeemAmount);
        torqDistribute = torqDistribute.add(claimAmountInToken);
    }

    function getUSDPrice(
        address _token,
        uint256 _amount,
        address _lptoken
    ) public view returns (uint256) {
        IPair pair = IPair(_lptoken);
        if (_token == router.WETH()) {
            address[] memory path = new address[](2);
            path[0] = router.WETH();
            path[1] = USDT;
            uint256[] memory amounts = router.getAmountsOut(_amount, path);
            return amounts[1];
        } else if (_token == address(pair)) {
            uint256 pairTokenToToken = getPairPrice(_lptoken);
            uint256 tokenEquivalent = _amount.mul(pairTokenToToken).div(1e18);
            address[] memory path = new address[](3);
            path[0] = address(token);
            path[1] = router.WETH();
            path[2] = USDT;
            uint256[] memory amounts = router.getAmountsOut(tokenEquivalent, path);
            return amounts[2];
        } else {
            address[] memory path = new address[](3);
            path[0] = _token;
            path[1] = router.WETH();
            path[2] = USDT;
            uint256[] memory amounts = router.getAmountsOut(_amount, path);
            return amounts[2];
        }
    }

    // Todo: Update from transfer function to transferFrom a vault that contain Torque token
}