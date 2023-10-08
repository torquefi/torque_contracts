// SPDX-License-Identifier: MIT

//  _________  ________  ________  ________  ___  ___  _______
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|
//

pragma solidity 0.8.19;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { USD } from "./USD.sol";
import "./interfaces/IUSDEngine.sol";

abstract contract USDEngineAbstract is ReentrancyGuard, Ownable, IUSDEngine {
    ///////////////////
    // State Variables
    ///////////////////
    USD internal immutable i_usd;

    // uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    mapping(address => uint256) internal liquidationThreshold;
    uint256 internal constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 internal constant MIN_HEALTH_FACTOR = 1e18;
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 internal constant FEED_PRECISION = 1e8;
    uint256 internal constant TIMEOUT = 3 hours;
    address internal WETH = 0xEe01c0CD76354C383B8c7B4e65EA88D00B06f36f;
    address internal WSTETHPriceFeed = 0xb523AE262D20A936BC152e6023996e46FDC2A95D; // For WSTETH priceFeed
    address internal ETHPriceFeed = 0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08;

    /// @dev Mapping of token address to price feed address
    mapping(address collateralToken => address priceFeed) internal s_priceFeeds;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address collateralToken => uint256 amount)) internal s_collateralDeposited;
    /// @dev Amount of USD minted by user
    mapping(address user => mapping(address token => uint256 amount)) internal s_USDMinted;
    /// @dev If we know exactly how many tokens we have, we could make this immutable!
    address[] public s_collateralTokens;

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert USDEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert USDEngine__TokenNotAllowed(token);
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, uint256[] memory liquidationThresholds, address usdAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert USDEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        // These feeds will be the USD pairs
        // For example ETH / USD or MKR / USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
            liquidationThreshold[tokenAddresses[i]] = liquidationThresholds[i];
        }
        i_usd = USD(usdAddress);
    }

    function updateWSTETHPriceFeed(address _wstethPriceFeed, address _ethPriceFeed) public onlyOwner {
        WSTETHPriceFeed = _wstethPriceFeed;
        ETHPriceFeed = _ethPriceFeed;
    }

    function updateAllPriceFeed(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        uint256[] memory liquidationThresholds
    ) public onlyOwner {
        delete s_collateralTokens;
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert USDEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        // These feeds will be the USD pairs
        // For example ETH / USD or MKR / USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
            liquidationThreshold[tokenAddresses[i]] = liquidationThresholds[i];
        }
    }

    function updatepriceFeed(address tokenAddress, address priceFeedAddress) public onlyOwner {
        s_priceFeeds[tokenAddress] = priceFeedAddress;
    }

    function updateWETH(address _WETH) public onlyOwner {
        WETH = _WETH;
    }

    function depositCollateralAndMintUsd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountUsdToMint
    ) external payable virtual {}

    function redeemCollateralForUsd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountUsdToBurn
    ) external payable virtual moreThanZero(amountCollateral) {}

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external payable virtual moreThanZero(amountCollateral) nonReentrant {}

    function burnUsd(uint256 amount, address collateral) external virtual moreThanZero(amount) {}

    function liquidate(address collateral, address user, uint256 debtToCover) external payable virtual moreThanZero(debtToCover) nonReentrant {}

    function mintUsd(uint256 amountUsdToMint, address collateral) public virtual moreThanZero(amountUsdToMint) nonReentrant {}

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public payable moreThanZero(amountCollateral) nonReentrant isAllowedToken(tokenCollateralAddress) {
        if (tokenCollateralAddress == WETH) {
            require(msg.value == amountCollateral, "USD: Not enough balance");
        } else {
            bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
            if (!success) {
                revert USDEngine__TransferFailed();
            }
        }
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    function getMintableUSD(address tokenCollateralAddress, address user, uint256 amountCollateral) public view virtual returns (uint256, bool) {}

    function getBurnableUSD(address tokenCollateralAddress, address user, uint256 amountUSD) public view virtual returns (uint256) {}

    ///////////////////
    // Private Functions
    ///////////////////
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) internal {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        if (tokenCollateralAddress == WETH) {
            (bool success, ) = to.call{ value: amountCollateral }("");
            require(success, "USD: Transfer ETH failed");
        } else {
            bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
            if (!success) {
                revert USDEngine__TransferFailed();
            }
        }
        emit CollateralRedeemed(from, amountCollateral, from, to);
    }

    function _burnUsd(uint256 amountUsdToBurn, address collateral, address onBehalfOf, address usdFrom) internal {
        if (s_USDMinted[onBehalfOf][collateral] >= amountUsdToBurn) {
            s_USDMinted[onBehalfOf][collateral] -= amountUsdToBurn;
        } else {
            s_USDMinted[onBehalfOf][collateral] = 0;
        }

        bool success = i_usd.transferFrom(usdFrom, address(this), amountUsdToBurn);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert USDEngine__TransferFailed();
        }
        i_usd.burn(amountUsdToBurn);
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////

    function _getAccountInformation(
        address user,
        address collateral
    ) internal view virtual returns (uint256 totalUsdMinted, uint256 collateralValueInUsd) {}

    function _healthFactor(address user, address collateral) internal view virtual returns (uint256) {}

    // function _getUsdValue(address token, uint256 amount) internal view virtual returns (uint256) {}
    function _getUsdValue(address token, uint256 amount) internal view returns (uint256) {
        uint256 usdValue;
        if (s_priceFeeds[token] == WSTETHPriceFeed) {
            AggregatorV3Interface wstPriceFeed = AggregatorV3Interface(WSTETHPriceFeed);
            (, int256 wstToETHPrice, , , ) = wstPriceFeed.latestRoundData();
            AggregatorV3Interface ethPriceFeed = AggregatorV3Interface(ETHPriceFeed);
            (, int256 ethToUSDPrice, , , ) = ethPriceFeed.latestRoundData();
            usdValue = (amount * uint256(wstToETHPrice) * uint256(ethToUSDPrice) * ADDITIONAL_FEED_PRECISION ** 2) / PRECISION ** 2;
        } else {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
            (, int256 price, , , ) = priceFeed.latestRoundData();
            usdValue = ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
        }
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return usdValue;
    }

    function _calculateHealthFactor(uint256 totalUsdMinted, uint256 collateralValueInUsd, address collateral) internal view returns (uint256) {
        if (totalUsdMinted == 0) return type(uint256).max;
        return (collateralValueInUsd * liquidationThreshold[collateral] * 1e18) / (totalUsdMinted * 100);
    }

    function revertIfHealthFactorIsBroken(address user, address collateral) internal view {
        uint256 userHealthFactor = _healthFactor(user, collateral);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert USDEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function validatePriceFeedAndReturnValue(address _priceFeed) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeed);
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();
        return uint256(price);
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    function calculateHealthFactor(uint256 totalUsdMinted, uint256 collateralValueInUsd, address collateral) external view returns (uint256) {
        return _calculateHealthFactor(totalUsdMinted, collateralValueInUsd, collateral);
    }

    function getAccountInformation(address user, address collateral) external view returns (uint256 totalUsdMinted, uint256 collateralValueInUsd) {
        return _getAccountInformation(user, collateral);
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user, address collateral) public view virtual returns (uint256 totalCollateralValueInUsd) {}

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view virtual returns (uint256) {}

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold(address _token) external view returns (uint256) {
        return liquidationThreshold[_token];
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getUsd() external view returns (address) {
        return address(i_usd);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user, address collateral) external view returns (uint256) {
        return _healthFactor(user, collateral);
    }
}
