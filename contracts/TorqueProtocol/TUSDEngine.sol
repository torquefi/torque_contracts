// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {OracleLib, AggregatorV3Interface} from "./OracleLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TUSD} from "./TUSD.sol";

contract TUSDEngine is Ownable, ReentrancyGuard {

    error TUSDEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error TUSDEngine__NeedsMoreThanZero();
    error TUSDEngine__TokenNotAllowed(address token);
    error TUSDEngine__TransferFailed();
    error TUSDEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error TUSDEngine__MintFailed();
    error TUSDEngine__HealthFactorOk();
    error TUSDEngine__HealthFactorNotImproved();

    using OracleLib for AggregatorV3Interface;

    TUSD private immutable i_tusd;

    uint256 private constant LIQUIDATION_THRESHOLD = 90; // will set later
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_TUSDMinted;
    
    address[] private s_collateralTokens;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert TUSDEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert TUSDEngine__TokenNotAllowed(token);
        }
        _;
    }
    
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address tusdAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert TUSDEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_tusd = TUSD(tusdAddress);
    }

    function depositCollateralAndMintTusd(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountTusdToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintTusd(amountTusdToMint);
    }

    function redeemCollateralForTusd(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountTusdToBurn) external moreThanZero(amountCollateral) {
        _burnTusd(amountTusdToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) external moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnTusd(uint256 amount) external moreThanZero(amount) {
        _burnTusd(amount, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert TUSDEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnTusd(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert TUSDEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintTusd(uint256 amountTUSDToMint) public moreThanZero(amountTusdToMint) nonReentrant {
        s_TUSDMinted[msg.sender] += amountTusdToMint;
        revertIfHealthFactorIsBroken(msg.sender, collateral);
        bool minted = i_tusd.mint(msg.sender, amountTusdToMint);
        if (minted != true) {
            revert TUSDEngine__MintFailed();
        }
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant isAllowedToken(tokenCollateralAddress) {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert TUSDEngine__TransferFailed();
        }
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert TUSDEngine__TransferFailed();
        }
    }

    function _burnTusd(uint256 amountTusdToBurn, address onBehalfOf, address tusdFrom) private {
        s_TUSDMinted[onBehalfOf] -= amountTusdToBurn;
        bool success = i_tusd.transferFrom(tusdFrom, address(this), amountTusdToBurn);
        if (!success) {
            revert TUSDEngine__TransferFailed();
        }
        i_tusd.burn(amountTusdToBurn);
    }

    function _getAccountInformation(address user) private view returns (uint256 totalTusdMinted, uint256 collateralValueInUsd) {
        totalTusdMinted = s_TUSDMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalTusdMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalTusdMinted, collateralValueInUsd);
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _calculateHealthFactor(uint256 totalTusdMinted, uint256 collateralValueInUsd) internal pure returns (uint256) {
        if (totalTusdMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalTusdMinted;
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert TUSDEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function calculateHealthFactor(uint256 totalTusdMinted, uint256 collateralValueInUsd) external pure returns (uint256) {
        return _calculateHealthFactor(totalTusdMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user) external view returns (uint256 totalTusdMinted, uint256 collateralValueInUsd) {
        return _getAccountInformation(user);
    }

    function getUsdValue(address token, uint256 amount) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getTusd() external view returns (address) {
        return address(i_tusd);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
