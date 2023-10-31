// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./IWithdrawal.sol";
import "./IEvent.sol";

// @title IWithdrawalCallbackReceiver
// @dev interface for a withdrawal callback contract
interface IWithdrawalCallbackReceiver {
  // @dev called after a withdrawal execution
  // @param key the key of the withdrawal
  // @param withdrawal the withdrawal that was executed
  function afterWithdrawalExecution(
    bytes32 key,
    IWithdrawal.Props memory withdrawal,
    IEvent.Props memory eventData
  ) external;

  // @dev called after a withdrawal cancellation
  // @param key the key of the withdrawal
  // @param withdrawal the withdrawal that was cancelled
  function afterWithdrawalCancellation(
    bytes32 key,
    IWithdrawal.Props memory withdrawal,
    IEvent.Props memory eventData
) external;
}