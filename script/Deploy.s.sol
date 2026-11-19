// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/AgentBadges.sol";

/// @notice Deploys AgentBadges to BSC mainnet (or any EVM chain).
///         Usage (see DEPLOY.md):
///           forge script script/Deploy.s.sol:Deploy \
///             --rpc-url https://bsc-dataseed.binance.org/ \
///             --private-key $PRIVATE_KEY --broadcast --verify \
///             --etherscan-api-key $BSCSCAN_API_KEY --chain bsc
contract Deploy is Script {
    // Agent ID contract, BSC mainnet (SPACE ID Agent ID, ERC-721 soulbound).
    address public constant AGENT_ID_MAINNET = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    function run() external returns (AgentBadges) {
        address agentId = vm.envOr("AGENT_ID", AGENT_ID_MAINNET);

        vm.startBroadcast();
        AgentBadges badges = new AgentBadges(agentId);
        vm.stopBroadcast();

        console.log("AgentBadges deployed at:", address(badges));
        console.log("Agent ID gate:", agentId);
        return badges;
    }
}
