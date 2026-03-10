// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Settlement} from "../src/Settlement.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {SolverRegistry} from "../src/SolverRegistry.sol";

/// @title Deploy
/// @notice Foundry deploy script for ARI DEX contracts.
///         Works on any EVM chain. Configure via environment variables:
///         - PERMIT2_ADDRESS: Uniswap Permit2 address (defaults to canonical)
///         - VERIFIER_ADDRESS: ZK verifier address (defaults to zero)
///         - GUARDIAN_ADDRESS: Guardian multisig (defaults to deployer)
///         - ARI_TOKEN_ADDRESS: $ARI ERC-20 token address (required for SolverRegistry)
contract Deploy is Script {
    function run() external {
        // Read config from environment with sensible defaults
        address permit2 = vm.envOr(
            "PERMIT2_ADDRESS",
            address(0x000000000022D473030F116dDEE9F6B43aC78BA3) // canonical Permit2
        );
        address verifier = vm.envOr("VERIFIER_ADDRESS", address(0));
        address guardian = vm.envOr("GUARDIAN_ADDRESS", msg.sender);
        address ariToken = vm.envOr("ARI_TOKEN_ADDRESS", address(0));

        vm.startBroadcast();

        // 1. Deploy Settlement
        Settlement settlement = new Settlement(permit2, verifier, guardian);
        console.log("Settlement deployed at:", address(settlement));

        // 2. Deploy VaultFactory (also deploys Vault implementation internally)
        VaultFactory vaultFactory = new VaultFactory();
        console.log("VaultFactory deployed at:", address(vaultFactory));
        console.log("  Vault implementation:", vaultFactory.implementation());

        // 3. Deploy SolverRegistry (only if ARI token address is provided)
        if (ariToken != address(0)) {
            SolverRegistry solverRegistry = new SolverRegistry(ariToken);
            console.log("SolverRegistry deployed at:", address(solverRegistry));
        } else {
            console.log("SolverRegistry skipped (ARI_TOKEN_ADDRESS not set)");
        }

        vm.stopBroadcast();
    }
}
