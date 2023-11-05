// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;
library Action {
    uint constant ACTION_SUPPLY_ASSET = 1;
    uint constant ACTION_SUPPLY_ETH = 2;
    uint constant ACTION_TRANSFER_ASSET = 3;
    uint constant ACTION_WITHDRAW_ASSET = 4;
    uint constant ACTION_WITHDRAW_ETH = 5;
    uint constant ACTION_CLAIM_REWARD = 6;

    function buildBorrowAction() pure public returns(uint[] memory) {
        uint[] memory actions = new uint[](2);
        actions[0] = Action.ACTION_SUPPLY_ASSET;
        actions[1] = Action.ACTION_WITHDRAW_ASSET;
        return actions;
    }
    function buildWithdraw() pure public returns(uint[] memory) {
        uint[] memory actions = new uint[](1);
        actions[0] = Action.ACTION_WITHDRAW_ASSET;
        return actions;
    }
    function buildRepay() pure public returns(uint[] memory) {
        uint[] memory actions = new uint[](2);

        actions[0] = Action.ACTION_SUPPLY_ASSET;
        actions[1] = Action.ACTION_WITHDRAW_ASSET;
        return actions;
    }
}
interface IBulker {
    function invoke(uint[] calldata actions, bytes[] calldata data) external payable ;
}