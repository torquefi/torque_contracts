// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISyntheticReader {
  struct MarketInfo {
    MarketProps market;
    uint256 borrowingFactorPerSecondForLongs;
    uint256 borrowingFactorPerSecondForShorts;
    BaseFundingValues baseFunding;
    GetNextFundingAmountPerSizeResult nextFunding;
    VirtualInventory virtualInventory;
    bool isDisabled;
  }

  struct MarketPrices {
    PriceProps indexTokenPrice;
    PriceProps longTokenPrice;
    PriceProps shortTokenPrice;
  }

  struct MarketProps {
    address marketToken;
    address indexToken;
    address longToken;
    address shortToken;
  }

  struct PriceProps {
    uint256 min;
    uint256 max;
  }

  struct BaseFundingValues {
    PositionType fundingFeeAmountPerSize;
    PositionType claimableFundingAmountPerSize;
  }

  struct VirtualInventory {
    uint256 virtualPoolAmountForLongToken;
    uint256 virtualPoolAmountForShortToken;
    int256 virtualInventoryForPositions;
  }

  struct GetNextFundingAmountPerSizeResult {
    bool longsPayShorts;
    uint256 fundingFactorPerSecond;

    PositionType fundingFeeAmountPerSizeDelta;
    PositionType claimableFundingAmountPerSizeDelta;
  }

  struct PositionType {
    CollateralType long;
    CollateralType short;
  }

  struct CollateralType {
    uint256 longToken;
    uint256 shortToken;
  }

  struct MarketPoolValueInfoProps {
    int256 poolValue;
    int256 longPnl;
    int256 shortPnl;
    int256 netPnl;

    uint256 longTokenAmount;
    uint256 shortTokenAmount;
    uint256 longTokenUsd;
    uint256 shortTokenUsd;

    uint256 totalBorrowingFees;
    uint256 borrowingFeePoolFactor;

    uint256 impactPoolAmount;
  }

  struct SwapFees {
    uint256 feeReceiverAmount;
    uint256 feeAmountForPool;
    uint256 amountAfterFees;

    address uiFeeReceiver;
    uint256 uiFeeReceiverFactor;
    uint256 uiFeeAmount;
  }

  struct ExecutionPriceResult {
    int256 priceImpactUsd;
    uint256 priceImpactDiffUsd;
    uint256 executionPrice;
  }

  function getMarkets(
    address dataStore,
    uint256 start,
    uint256 end
  ) external view returns (MarketProps[] memory);

  function getMarketInfo(
    address dataStore,
    MarketPrices memory prices,
    address marketKey
  ) external view returns (MarketInfo memory);

  function getMarketTokenPrice(
    address dataStore,
    MarketProps memory market,
    PriceProps memory indexTokenPrice,
    PriceProps memory longTokenPrice,
    PriceProps memory shortTokenPrice,
    bytes32 pnlFactorType,
    bool maximize
  ) external view returns (int256, MarketPoolValueInfoProps memory);

  function getSwapAmountOut(
    address dataStore,
    MarketProps memory market,
    MarketPrices memory prices,
    address tokenIn,
    uint256 amountIn,
    address uiFeeReceiver
  ) external view returns (uint256, int256, SwapFees memory fees);

  function getExecutionPrice(
    address dataStore,
    address marketKey,
    PriceProps memory indexTokenPrice,
    uint256 positionSizeInUsd,
    uint256 positionSizeInTokens,
    int256 sizeDeltaUsd,
    bool isLong
  ) external view returns (ExecutionPriceResult memory);

  function getSwapPriceImpact(
    address dataStore,
    address marketKey,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    PriceProps memory tokenInPrice,
    PriceProps memory tokenOutPrice
  ) external view returns (int256, int256);

  function getOpenInterestWithPnl(
    address dataStore,
    MarketProps memory market,
    PriceProps memory indexTokenPrice,
    bool isLong,
    bool maximize
  ) external view returns (int256);
}
