// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//  _________  ________  ________  ________  ___  ___  _______      
// |\___   ___\\   __  \|\   __  \|\   __  \|\  \|\  \|\  ___ \     
// \|___ \  \_\ \  \|\  \ \  \|\  \ \  \|\  \ \  \\\  \ \   __/|    
//     \ \  \ \ \  \\\  \ \   _  _\ \  \\\  \ \  \\\  \ \  \_|/__  
//      \ \  \ \ \  \\\  \ \  \\  \\ \  \\\  \ \  \\\  \ \  \_|\ \ 
//       \ \__\ \ \_______\ \__\\ _\\ \_____  \ \_______\ \_______\
//        \|__|  \|_______|\|__|\|__|\|___| \__\|_______|\|_______|

import "./TUSDEngineAbstract.sol";

contract TUSDEngine is TUSDEngineAbstract {
    ///////////////////
    // Functions
    ///////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        uint256[] memory liquidationThresholds,
        uint256[] memory collateralDecimals,
        address tusdAddress
    )
        TUSDEngineAbstract(
            tokenAddresses,
            priceFeedAddresses,
            liquidationThresholds,
            collateralDecimals,
            tusdAddress
        )
    {}

    ///////////////////
    // External Functions
    ///////////////////
    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountTUSDToMint: The amount of TUSD you want to mint
     * @notice This function will deposit your collateral and mint TUSD in one transaction
     */
    function depositCollateralAndMintTusd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountTusdToMint
    ) external payable override(TUSDEngineAbstract) {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintTusd(amountTusdToMint, tokenCollateralAddress);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountTUSDToBurn: The amount of TUSD you want to burn
     * @notice This function will withdraw your collateral and burn TUSD in one transaction
     */
    function redeemCollateralForTusd(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountTusdToBurn
    ) external payable override(TUSDEngineAbstract) moreThanZero(amountCollateral) {
        _burnTusd(amountTusdToBurn, msg.sender, msg.sender, tokenCollateralAddress);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender, tokenCollateralAddress);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have TUSD minted, you'll not be able to redeem until you burn your TUSD
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external payable override(TUSDEngineAbstract) moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender, tokenCollateralAddress);
    }

    /*
     * @notice You'll burn your TUSD here! Make sure you want to do this..
     * @dev You might want to use this to just to move away from liquidation.
     */
    function burnTusd(
        uint256 amount,
        address collateral
    ) external override(TUSDEngineAbstract) moreThanZero(amount) {
        _burnTusd(amount, msg.sender, msg.sender, collateral);
        revertIfHealthFactorIsBroken(msg.sender, collateral);
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your TUSD to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of TUSD you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external payable override(TUSDEngineAbstract) moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user, collateral);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert TUSDEngine__HealthFactorOk();
        }
        // If covering 100 TUSD, we need to $100 of collateral
        (uint256 tokenAmountFromDebtCovered, bool isLatestPrice) = getTokenAmountFromTusd(
            collateral,
            debtToCover
        );
        if (!isLatestPrice) {
            revert TUSDEngine__NotLatestPrice();
        }
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 TUSD
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        // Burn TUSD equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(
            collateral,
            tokenAmountFromDebtCovered + bonusCollateral,
            user,
            msg.sender
        );
        _burnTusd(debtToCover, user, msg.sender, collateral);

        uint256 endingUserHealthFactor = _healthFactor(user, collateral);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert TUSDEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender, collateral);
    }

    ///////////////////
    // Public Functions
    ///////////////////
    /*
     * @param amountTUSDToMint: The amount of TUSD you want to mint
     * You can only mint TUSD if you have enough collateral
     */
    function mintTusd(
        uint256 amountUsdToMint,
        address collateral
    ) public override(TUSDEngineAbstract) moreThanZero(amountTusdToMint) nonReentrant {
        s_TUSDMinted[msg.sender][collateral] += amountTusdToMint;
        revertIfHealthFactorIsBroken(msg.sender, collateral);
        bool minted = i_tusd.mint(msg.sender, amountTusdToMint);

        if (minted != true) {
            revert TUSDEngine__MintFailed();
        }
    }

    function getMintableTUSD(
        address tokenCollateralAddress,
        address user,
        uint256 amountCollateral
    ) public view override(TUSDEngineAbstract) returns (uint256, bool) {
        uint256 amount = s_collateralDeposited[user][tokenCollateralAddress];
        uint256 normalizedAmount = normalizeTokenAmount(amountCollateral, tokenCollateralAddress);
        (uint256 tusdValue, bool isLatestPrice) = _getTusdValue(
            tokenCollateralAddress,
            amount + normalizedAmount
        );
        uint256 totalTusdMintableAmount = (tusdValue * liquidationThreshold[tokenCollateralAddress]) /
            100;

        (uint256 totalTusdMinted, , ) = _getAccountInformation(user, tokenCollateralAddress);

        if (totalTusdMintableAmount <= totalTusdMinted) {
            uint256 debtTusdAmount = totalTusdMinted - totalTusdMintableAmount;
            return (debtTusdAmount, false); // cannot mint tusd anymore
        } else {
            uint256 mintableTusdAmount = totalTusdMintableAmount - totalTusdMinted;
            return (convertToSafetyValue(mintableTusdAmount), isLatestPrice);
        }
    }

    function getBurnableTUSD(
        address tokenCollateralAddress,
        address user,
        uint256 amountTUSD
    ) public view override(TUSDEngineAbstract) returns (uint256, bool) {
        (uint256 totalTusdMinted, uint256 totalCollateralInTUSD, ) = _getAccountInformation(
            user,
            tokenCollateralAddress
        );
        uint256 totalTusdAfterBurn = 0;
        uint256 tokenAmountInTUSD = 0;
        if (amountTUSD < totalTusdMinted) {
            totalTusdAfterBurn = totalTusdMinted - amountTUSD;
        }
        uint256 inneedTUSDAmount = 0;
        inneedTUSDAmount +=
            (totalCollateralInTUSD * liquidationThreshold[tokenCollateralAddress]) /
            100;

        if (inneedTUSDAmount >= totalTusdAfterBurn) {
            tokenAmountInTUSD = totalCollateralInTUSD;
        } else {
            uint256 backupTokenInTUSD = ((totalTusdAfterBurn - inneedTUSDAmount) * 100) /
                liquidationThreshold[tokenCollateralAddress];
            tokenAmountInTUSD = totalCollateralInTUSD >= backupTokenInTUSD
                ? totalCollateralInTUSD - backupTokenInTUSD
                : 0;
        }

        return getTokenAmountFromTusd(tokenCollateralAddress, tokenAmountInTUSD);
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////
    function _getAccountInformation(
        address user,
        address collateral
    )
        internal
        view
        override(TUSDEngineAbstract)
        returns (uint256 totalTusdMinted, uint256 collateralValueInTusd, bool isLatestPrice)
    {
        totalTusdMinted = s_TUSDMinted[user][collateral];
        (uint256 _collateralValueInTusd, bool _isLatestPrice) = getAccountCollateralValue(
            user,
            collateral
        );
        collateralValueInTusd = _collateralValueInTusd;
        _isLatestPrice = isLatestPrice;
    }

    function _healthFactor(
        address user,
        address collateral
    ) internal view override(TUSDEngineAbstract) returns (uint256) {
        (
            uint256 totalTusdMinted,
            uint256 collateralValueInTusd,
            bool isLatestPrice
        ) = _getAccountInformation(user, collateral);
        return _calculateHealthFactor(totalTusdMinted, collateralValueInTusd, collateral);
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    function getAccountCollateralValue(
        address user,
        address collateral
    ) public view override(TUSDEngineAbstract) returns (uint256, bool) {
        uint256 amount = s_collateralDeposited[user][collateral];
        return _getTusdValue(collateral, amount);
    }

    function getTokenAmountFromTusd(
        address token,
        uint256 tusdAmountInWei
    ) public view override(TUSDEngineAbstract) returns (uint256, bool) {
        uint256 tokenAmount;
        bool isLatestPrice;
        if (s_priceFeeds[token] == WSTETHPriceFeed) {
            (uint256 wstETHToEthPrice, bool isLatestPrice1) = validatePriceFeedAndReturnValue(
                WSTETHPriceFeed
            );
            (uint256 ethToTUSDPrice, bool isLatestPrice2) = validatePriceFeedAndReturnValue(
                ETHPriceFeed
            );
            isLatestPrice = isLatestPrice1 && isLatestPrice2;
            tokenAmount =
                (tusdAmountInWei * PRECISION ** 2) /
                (ADDITIONAL_FEED_PRECISION ** 2 * wstETHToEthPrice * ethToTUSDPrice);
        } else {
            (uint256 price, bool _isLatestPrice) = validatePriceFeedAndReturnValue(
                s_priceFeeds[token]
            );
            isLatestPrice = _isLatestPrice;
            tokenAmount = ((tusdAmountInWei * PRECISION) / (price * ADDITIONAL_FEED_PRECISION));
        }
        uint256 finalAmount = (tokenAmount * 10 ** s_collateralDecimal[token]) / 10 ** 18;
        return (finalAmount, isLatestPrice);
    }
}