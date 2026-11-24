// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Test/BSC-testnet stand-in for the Agent ID contract: only the
///         `balanceOf` surface AgentBoard reads, plus a free mint so any
///         test wallet can act as an Agent ID holder. NEVER used on mainnet —
///         the mainnet board is constructed with the real Agent ID contract
///         0x60b9262456de011f7d15a54cdd8c48baaa8b022f.
contract MockAgentId {
    mapping(address => uint256) private _balances;
    uint256 public nextId = 1;

    function mint(address to) external {
        require(_balances[to] == 0, "one per user");
        _balances[to] = 1;
        nextId += 1;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }
}
