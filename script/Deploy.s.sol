// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {AgentBoard} from "../src/AgentBoard.sol";
import {MockAgentId} from "../test/MockAgentId.sol";

/// @notice Deploy AgentBoard.
///         Mainnet:  AGENT_ID_ADDRESS unset -> defaults to the real Agent ID
///                   contract on BNB Chain.
///         Testnet:  DEPLOY_MOCK_AGENT_ID=1 deploys a MockAgentId first and
///                   gates the board on it (testnet has no real Agent ID).
///         PRIVATE_KEY comes from the environment; never commit a key.
contract Deploy is Script {
    address internal constant REAL_AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    function run() external returns (AgentBoard board) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        bool useMock = vm.envOr("DEPLOY_MOCK_AGENT_ID", uint256(0)) == 1;
        address agentIdAddr = vm.envOr("AGENT_ID_ADDRESS", REAL_AGENT_ID);

        vm.startBroadcast(pk);
        if (useMock) {
            MockAgentId mock = new MockAgentId();
            agentIdAddr = address(mock);
        }
        board = new AgentBoard(agentIdAddr);
        vm.stopBroadcast();
    }
}
