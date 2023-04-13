// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./../Interfaces/IStakingTorque.sol";
import "./../Interfaces/IRouter.sol";

/**

********\                                                
\__**  __|                                               
   ** | ******\   ******\   ******\  **\   **\  ******\  
   ** |**  __**\ **  __**\ **  __**\ ** |  ** |**  __**\ 
   ** |** /  ** |** |  \__|** /  ** |** |  ** |******** |
   ** |** |  ** |** |      ** |  ** |** |  ** |**   ____|
   ** |\******  |** |      \******* |\******  |\*******\ 
   \__| \______/ \__|       \____** | \______/  \_______|
                                 ** |                    
                                 ** |                    
                                 \__|                    

 */

contract Staking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    uint256 public apr = 3200;
    uint256 constant RATE_PRECISION = 10000;
    uint256 constant ONE_YEAR_IN_SECONDS = 365 days;
    uint256 constant ONE_DAY_IN_SECONDS = 1 days;
    uint256 cooldownTime = 7 days;
    address public USDT;
    IRouter public router;
    uint256 public torqStake;
    uint256 public torqDistribute;

    uint256 constant PERIOD_PRECISION = 10000;
    IERC20 public token;
    IStakingTorque public sTorque;

    bool public enabled;

    modifier noContract() {
        require(tx.origin == msg.sender, "StakingTorque: Contract not allowed to interact");
        _;
    }

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IERC20 _token, address _sTorqueToken) {
        token = _token;
        sTorque = IStakingTorque(_sTorqueToken);
    }

    struct StakeDetail {
        uint256 principal;
        uint256 lastProcessAt;
        uint256 pendingReward;
        uint256 firstStakeAt;
    }

    mapping(address => StakeDetail) public stakers;

    function setEnabled(bool _enabled) external onlyOwner {
        enabled = _enabled;
    }

    function updateRouter(address _router) public onlyOwner {
        router = IRouter(_router);
    }

    function updateUSDT(address _usdt) public onlyOwner {
        USDT = _usdt;
    }

    function updateAPR(uint256 _apr) external onlyOwner {
        apr = _apr;
    }

    function emergencyWithdraw(uint256 _amount) external onlyOwner {
        token.transfer(msg.sender, _amount);
    }

    function setCooldownTime(uint256 _cooldownTime) public onlyOwner {
        cooldownTime = _cooldownTime;
    }

    function getStakeDetail(
        address _staker
    )
        public
        view
        returns (
            uint256 principal,
            uint256 pendingReward,
            uint256 lastProcessAt,
            uint256 firstStakeAt
        )
    {
        StakeDetail memory stakeDetail = stakers[_staker];
        return (
            stakeDetail.principal,
            stakeDetail.pendingReward,
            stakeDetail.lastProcessAt,
            stakeDetail.firstStakeAt
        );
    }

    function getInterest(address _staker) public view returns (uint256) {
        uint256 timestamp = block.timestamp;
        return previewInterest(_staker, timestamp);
    }

    function previewInterest(address _staker, uint256 _timestamp) public view returns (uint256) {
        StakeDetail memory stakeDetail = stakers[_staker];
        uint256 duration = _timestamp.sub(stakeDetail.lastProcessAt);
        uint256 interest = stakeDetail
            .principal
            .mul(apr)
            .mul(duration)
            .div(ONE_YEAR_IN_SECONDS)
            .div(RATE_PRECISION);
        return interest.add(stakeDetail.pendingReward);
    }

    function deposit(uint256 _stakeAmount) external nonReentrant noContract {
        require(enabled, "Staking is not enabled");
        require(_stakeAmount > 0, "StakingTorque: stake amount must be greater than 0");
        token.transferFrom(msg.sender, address(this), _stakeAmount);
        StakeDetail storage stakeDetail = stakers[msg.sender];
        if (stakeDetail.firstStakeAt == 0) {
            stakeDetail.principal = stakeDetail.principal.add(_stakeAmount);
            stakeDetail.firstStakeAt = stakeDetail.firstStakeAt == 0
                ? block.timestamp
                : stakeDetail.firstStakeAt;
        } else {
            uint256 interest = getInterest(msg.sender);
            stakeDetail.principal = stakeDetail.principal.add(_stakeAmount).add(interest);
        }
        stakeDetail.lastProcessAt = block.timestamp;
        emit Deposit(msg.sender, _stakeAmount);
        sTorque.mint(_msgSender(), _stakeAmount);
        torqStake = torqStake.add(_stakeAmount);
    }

    function redeem(uint256 _redeemAmount) external nonReentrant noContract {
        require(enabled, "Staking is not enabled");
        StakeDetail storage stakeDetail = stakers[msg.sender];
        require(stakeDetail.firstStakeAt > 0, "StakingTorque: no stake");
        require(
            stakeDetail.lastProcessAt + cooldownTime <= block.timestamp,
            "Not reach cool down time"
        );

        uint256 interest = getInterest(msg.sender);

        uint256 claimAmount = interest.mul(_redeemAmount).div(stakeDetail.principal);

        uint256 remainAmount = interest.sub(claimAmount);

        stakeDetail.lastProcessAt = block.timestamp;
        require(
            stakeDetail.principal >= _redeemAmount,
            "StakingTorque: redeem amount must be less than principal"
        );
        stakeDetail.principal = stakeDetail.principal.sub(_redeemAmount);
        stakeDetail.pendingReward = remainAmount;
        require(
            token.transfer(msg.sender, _redeemAmount.add(claimAmount)),
            "StakingTorque: transfer failed"
        );
        emit Redeem(msg.sender, _redeemAmount.add(claimAmount));

        sTorque.transferFrom(_msgSender(), address(this), _redeemAmount);
        sTorque.burn(address(this), _redeemAmount);
        torqStake = torqStake.sub(_redeemAmount);
        torqDistribute = torqDistribute.add(claimAmount);
    }

    function getUSDPrice(address _token, uint256 _amount) public view returns (uint256) {
        if (_token == router.WETH()) {
            address[] memory path = new address[](2);
            path[0] = router.WETH();
            path[1] = USDT;
            uint256[] memory amounts = router.getAmountsOut(_amount, path);
            return amounts[1];
        } else {
            address[] memory path = new address[](3);
            path[0] = _token;
            path[1] = router.WETH();
            path[2] = USDT;
            uint256[] memory amounts = router.getAmountsOut(_amount, path);
            return amounts[2];
        }
    }
}
