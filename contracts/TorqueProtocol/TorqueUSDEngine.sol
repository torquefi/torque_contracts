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
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TorqueUSD } from "./TorqueUSD.sol";
import { OFTCore } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { ILayerZeroEndpoint } from "@layerzerolabs/oft-evm/contracts/interfaces/ILayerZeroEndpoint.sol";

/// @title TorqueUSDEngine Contract
/// @notice This contract facilitates the collateralized minting, burning, and management of TorqueUSD, with cross-chain functionality using LayerZero.
/// @dev This contract is integrated with LayerZero for omnichain operations and supports USDC as collateral.
contract TorqueUSDEngine is Ownable, ReentrancyGuard, OFTCore {

    /// @notice Errors to manage contract exceptions
    error TorqueUSDEngine__NeedsMoreThanZero();
    error TorqueUSDEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error TorqueUSDEngine__MintFailed();
    error TorqueUSDEngine__HealthFactorOk();
    error TorqueUSDEngine__HealthFactorNotImproved();

    using OracleLib for AggregatorV3Interface;

    /// @notice TorqueUSD stablecoin contract
    TorqueUSD public immutable i_torqueUSD; 
    /// @notice USDC token contract used for collateral
    IERC20 public immutable usdcToken; 
    /// @notice Chainlink price feed for USDC/USD
    AggregatorV3Interface public immutable usdcPriceFeed;

    // Constants defining protocol parameters
    uint256 private constant LIQUIDATION_THRESHOLD = 98; // 98% collateral threshold
    uint256 private constant LIQUIDATION_BONUS = 20; // 20% bonus for liquidators
    uint256 private constant LIQUIDATION_PRECISION = 100; // Precision factor for liquidation calculations
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // Minimum health factor (1.0)
    uint256 private constant PRECISION = 1e18; // Precision factor for calculations
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // Extra precision for feed calculations
    uint256 private constant FEED_PRECISION = 1e8; // Price feed precision
    uint256 private constant USDC_DECIMAL = 1e6; // USDC decimal precision

    /// @notice Tracks collateral deposited by users
    mapping(address => uint256) private s_collateralDeposited;
    /// @notice Tracks TorqueUSD minted by users
    mapping(address => uint256) private s_TorqueUSDMinted;

    /// @notice Treasury address to manage protocol reserves
    address public treasuryAddress;

    /// @notice Event emitted when collateral is deposited
    /// @param user The address of the depositor
    /// @param amount The amount of collateral deposited
    event CollateralDeposited(address indexed user, uint256 amount);

    /// @notice Event emitted when collateral is redeemed
    /// @param from The address of the redeemer
    /// @param to The address receiving the collateral
    /// @param amount The amount of collateral redeemed
    event CollateralRedeemed(address indexed from, address indexed to, uint256 amount);

    /// @notice Event emitted when TorqueUSD is minted
    /// @param user The address minting TorqueUSD
    /// @param amount The amount of TorqueUSD minted
    event TorqueUSDMinted(address indexed user, uint256 amount);

    /// @notice Event emitted when TorqueUSD is burned
    /// @param user The address burning TorqueUSD
    /// @param amount The amount of TorqueUSD burned
    event TorqueUSDBurned(address indexed user, uint256 amount);

    /// @notice Modifier to ensure non-zero amount
    /// @param amount The amount to check
    modifier moreThanZero(uint256 amount) {
        require(amount > 0, "Amount must be more than zero");
        _;
    }

    /// @notice Constructor to initialize contract variables
    /// @param usdcTokenAddress Address of the USDC token contract
    /// @param usdcPriceFeedAddress Address of the USDC price feed contract
    /// @param torqueUsdAddress Address of the TorqueUSD contract
    /// @param lzEndpoint Address of the LayerZero endpoint
    constructor(
        address usdcTokenAddress, 
        address usdcPriceFeedAddress, 
        address torqueUsdAddress,
        address lzEndpoint
    ) OFTCore(lzEndpoint) Ownable() {
        i_torqueUSD = TorqueUSD(torqueUsdAddress);
        usdcToken = IERC20(usdcTokenAddress);
        usdcPriceFeed = AggregatorV3Interface(usdcPriceFeedAddress);
    }

    /// @notice Deposit collateral and mint TorqueUSD with cross-chain support
    /// @param amountCollateral The amount of collateral to deposit
    /// @param amountTorqueUSDToMint The amount of TorqueUSD to mint
    /// @param dstChainId ID of the destination chain
    /// @param dstAddress Address receiving TorqueUSD on the destination chain
    /// @param adapterParams LayerZero adapter parameters
    function depositCollateralAndMintTorqueUSD(
        uint256 amountCollateral, 
        uint256 amountTorqueUSDToMint, 
        uint16 dstChainId, 
        bytes calldata dstAddress, 
        bytes calldata adapterParams
    ) external payable moreThanZero(amountCollateral) {
        depositCollateral(amountCollateral);
        _lzSend(
            dstChainId,
            abi.encode(amountTorqueUSDToMint, msg.sender),
            payable(msg.sender),
            address(0),
            adapterParams
        );
    }

    /// @notice Handles incoming cross-chain messages and mints TorqueUSD
    /// @param _payload Payload containing mint amount and user address
    function _nonblockingLzReceive(
        uint16, // _srcChainId
        bytes memory, // _srcAddress
        uint64, // _nonce
        bytes memory _payload
    ) internal override {
        (uint256 amountTorqueUSDToMint, address user) = abi.decode(_payload, (uint256, address));
        _mintTorqueUSD(amountTorqueUSDToMint, user);
    }

    /// @notice Mints TorqueUSD to a specified address
    /// @param amountTorqueUSDToMint The amount of TorqueUSD to mint
    /// @param to The address receiving the minted TorqueUSD
    function _mintTorqueUSD(uint256 amountTorqueUSDToMint, address to) private moreThanZero(amountTorqueUSDToMint) {
        s_TorqueUSDMinted[to] += amountTorqueUSDToMint;
        require(i_torqueUSD.mint(to, amountTorqueUSDToMint), "Mint failed");
        emit TorqueUSDMinted(to, amountTorqueUSDToMint);
    }

    /// @notice Redeems collateral for TorqueUSD with cross-chain support
    /// @param amountCollateral The amount of collateral to redeem
    /// @param amountTorqueUSDToBurn The amount of TorqueUSD to burn
    /// @param dstChainId ID of the destination chain
    /// @param dstAddress Address receiving collateral on the destination chain
    /// @param adapterParams LayerZero adapter parameters
    function redeemCollateralForTorqueUSD(
        uint256 amountCollateral, 
        uint256 amountTorqueUSDToBurn, 
        uint16 dstChainId, 
        bytes calldata dstAddress, 
        bytes calldata adapterParams
    ) external moreThanZero(amountCollateral) {
        _burnTorqueUSD(amountTorqueUSDToBurn, msg.sender);
        _redeemCollateral(amountCollateral, msg.sender, msg.sender);
        _lzSend(
            dstChainId,
            abi.encode(amountTorqueUSDToBurn, msg.sender),
            payable(msg.sender),
            address(0),
            adapterParams
        );
    }

    /// @notice Burns TorqueUSD for a specified user
    /// @param amountTorqueUSDToBurn The amount of TorqueUSD to burn
    /// @param from The address burning the TorqueUSD
    function _burnTorqueUSD(uint256 amountTorqueUSDToBurn, address from) private {
        require(s_TorqueUSDMinted[from] >= amountTorqueUSDToBurn, "Insufficient TorqueUSD balance");
        s_TorqueUSDMinted[from] -= amountTorqueUSDToBurn;
        require(i_torqueUSD.transferFrom(from, address(this), amountTorqueUSDToBurn), "Transfer failed");
        i_torqueUSD.burn(amountTorqueUSDToBurn);
        emit TorqueUSDBurned(from, amountTorqueUSDToBurn);
    }

    /// @notice Deposits collateral into the protocol
    /// @param amountCollateral The amount of collateral to deposit
    function depositCollateral(uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        s_collateralDeposited[msg.sender] += amountCollateral;
        require(usdcToken.transferFrom(msg.sender, address(this), amountCollateral), "Transfer failed");
        emit CollateralDeposited(msg.sender, amountCollateral);
    }

    /// @notice Liquidates a user's position if health factor is below threshold
    /// @param user The address of the user to liquidate
    /// @param debtToCover The amount of debt to cover
    function liquidate(address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert TorqueUSDEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        _redeemCollateral(tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnTorqueUSD(debtToCover, user);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert TorqueUSDEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Redeems collateral for a specified user
    /// @param amountCollateral The amount of collateral to redeem
    /// @param from The address of the user redeeming collateral
    /// @param to The address receiving the collateral
    function _redeemCollateral(uint256 amountCollateral, address from, address to) private {
        require(s_collateralDeposited[from] >= amountCollateral, "Insufficient collateral");
        s_collateralDeposited[from] -= amountCollateral;
        require(usdcToken.transfer(to, amountCollateral), "Transfer failed");
        emit CollateralRedeemed(from, to, amountCollateral);
    }

    /// @notice Sets the treasury address for protocol reserves
    /// @param _treasuryAddress The new treasury address
    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        require(_treasuryAddress != address(0), "Invalid treasury address");
        treasuryAddress = _treasuryAddress;
    }

    /// @notice Deploys reserves to the treasury
    /// @param amount The amount of reserves to deploy
    function deployReserves(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(usdcToken.balanceOf(address(this)) >= amount, "Insufficient balance");
        require(usdcToken.transfer(treasuryAddress, amount), "Transfer failed");
    }

    /// @notice Calculates the health factor of a user
    /// @param user The address of the user
    /// @return The calculated health factor
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /// @notice Retrieves user account info
    /// @param user The address of the user
    /// @return totalTorqueUSDMinted Amount of TorqueUSD minted
    /// @return collateralValueInUsd Collateral value in USD
    function getAccountInformation(address user) external view returns (uint256 totalTorqueUSDMinted, uint256 collateralValueInUsd) {
        return _getAccountInformation(user);
    }

    /// @notice Converts a USD amount to token equivalent
    /// @param usdAmountInWei Amount in USD (Wei)
    /// @return Token equivalent
    function getTokenAmountFromUsd(uint256 usdAmountInWei) public view returns (uint256) {
        (, int256 price,,,) = usdcPriceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    /// @notice Gets collateral balance of a user
    /// @param user The address of the user
    /// @return Amount of collateral deposited
    function getCollateralBalanceOfUser(address user) external view returns (uint256) {
        return s_collateralDeposited[user];
    }

    /// @notice Gets the collateral value of a user in USD
    /// @param user The address of the user
    /// @return totalCollateralValueInUsd The collateral value in USD
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 amountCollateral = s_collateralDeposited[user];
        return _getUsdValue(amountCollateral);
    }
}
