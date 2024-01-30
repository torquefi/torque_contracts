// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

library Errors {

  /* ===================== AUTHORIZATION ===================== */

  error OnlyKeeperAllowed();
  error OnlyVaultAllowed();
  error OnlyBorrowerAllowed();

  /* ======================== GENERAL ======================== */

  error ZeroAddressNotAllowed();
  error TokenDecimalsMustBeLessThan18();

  /* ========================= ORACLE ======================== */

  error NoTokenPriceFeedAvailable();
  error FrozenTokenPriceFeed();
  error BrokenTokenPriceFeed();
  error TokenPriceFeedAlreadySet();
  error TokenPriceFeedMaxDelayMustBeGreaterOrEqualToZero();
  error TokenPriceFeedMaxDeviationMustBeGreaterOrEqualToZero();
  error InvalidTokenInLPPool();
  error InvalidReservesInLPPool();
  error OrderAmountOutMustBeGreaterThanZero();
  error SequencerDown();
  error GracePeriodNotOver();

  /* ======================== LENDING ======================== */

  error InsufficientBorrowAmount();
  error InsufficientRepayAmount();
  error BorrowerAlreadyApproved();
  error BorrowerAlreadyRevoked();
  error InsufficientLendingLiquidity();
  error InsufficientAssetsBalance();
  error InterestRateModelExceeded();

  /* ===================== VAULT GENERAL ===================== */

  error InvalidExecutionFeeAmount();
  error InsufficientExecutionFeeAmount();
  error InsufficientSlippageAmount();
  error NotAllowedInCurrentVaultStatus();

  /* ===================== VAULT DEPOSIT ===================== */

  error EmptyDepositAmount();
  error InvalidDepositToken();
  error InsufficientDepositAmount();
  error InvalidNativeDepositAmountValue();
  error InsufficientSharesMinted();
  error InsufficientCapacity();
  error OnlyNonNativeDepositToken();
  error InvalidNativeTokenAddress();
  error DepositAndExecutionFeeDoesNotMatchMsgValue();
  error DepositCancellationCallback();

  /* ===================== VAULT WITHDRAW ==================== */

  error EmptyWithdrawAmount();
  error InvalidWithdrawToken();
  error InsufficientWithdrawAmount();
  error InsufficientWithdrawBalance();
  error InvalidEquityAfterWithdraw();
  error InsufficientAssetsReceived();
  error WithdrawNotAllowedInSameDepositBlock();
  error WithdrawalCancellationCallback();
  error NoAssetsToEmergencyRefund();

  /* ==================== VAULT REBALANCE ==================== */

  error InvalidDebtRatio();
  error InvalidDelta();
  error InsufficientLPTokensMinted();
  error InsufficientLPTokensBurned();
  error InvalidRebalancePreConditions();
  error InvalidRebalanceParameters();

  /* ==================== VAULT CALLBACKS ==================== */

  error InvalidCallbackHandler();
}
