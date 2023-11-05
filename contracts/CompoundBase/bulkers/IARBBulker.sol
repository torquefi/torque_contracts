// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;
library Action {
    
    /// @notice The action for supplying an asset to Comet
    bytes32 public constant ACTION_SUPPLY_ASSET = "ACTION_SUPPLY_ASSET";

    /// @notice The action for supplying a native asset (e.g. ETH on Ethereum mainnet) to Comet
    bytes32 public constant ACTION_SUPPLY_ETH = "ACTION_SUPPLY_NATIVE_TOKEN";

    /// @notice The action for transferring an asset within Comet
    bytes32 public constant ACTION_TRANSFER_ASSET = "ACTION_TRANSFER_ASSET";

    /// @notice The action for withdrawing an asset from Comet
    bytes32 public constant ACTION_WITHDRAW_ASSET = "ACTION_WITHDRAW_ASSET";

    /// @notice The action for withdrawing a native asset from Comet
    bytes32 public constant ACTION_WITHDRAW_ETH = "ACTION_WITHDRAW_NATIVE_TOKEN";

    /// @notice The action for claiming rewards from the Comet rewards contract
    bytes32 public constant ACTION_CLAIM_REWARD = "ACTION_CLAIM_REWARD";

    function buildBorrowAction() pure public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);
        actions[0] = Action.ACTION_SUPPLY_ASSET;
        actions[1] = Action.ACTION_WITHDRAW_ASSET;
        return actions;
    }
    function buildWithdraw() pure public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](1);
        actions[0] = Action.ACTION_WITHDRAW_ASSET;
        return actions;
    }
    function buildRepay() pure public returns(bytes32[] memory) {
        bytes32[] memory actions = new bytes32[](2);

        actions[0] = Action.ACTION_SUPPLY_ASSET;
        actions[1] = Action.ACTION_WITHDRAW_ASSET;
        return actions;
    }
}
interface IBulker {
    function invoke(bytes32[] calldata actions, bytes[] calldata data) external payable ;
}