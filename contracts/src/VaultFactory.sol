// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vault} from "./Vault.sol";

/// @title VaultFactory
/// @author ARI DEX
/// @notice Factory contract that deploys Vault clones using CREATE2 for
///         deterministic addresses. Each unique (token0, token1, feeTier) triple
///         maps to exactly one vault.
contract VaultFactory {
    // ─── State ───────────────────────────────────────────────────────────

    /// @notice Contract owner
    address public owner;

    /// @notice Implementation contract used for cloning
    address public immutable implementation;

    /// @notice Mapping from pool key hash to vault address
    mapping(bytes32 => address) private _vaults;

    /// @notice Array of all deployed vaults
    address[] private _allVaults;

    // ─── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted when a new vault is created
    /// @param vault  Address of the newly created vault
    /// @param token0  Token0 of the pool
    /// @param token1  Token1 of the pool
    /// @param feeTier  Fee tier of the pool
    event VaultCreated(
        address indexed vault, address indexed token0, address indexed token1, uint24 feeTier
    );

    // ─── Errors ──────────────────────────────────────────────────────────

    error VaultAlreadyExists();
    error IdenticalAddresses();
    error ZeroAddress();
    error Unauthorized();
    error DeploymentFailed();

    // ─── Constructor ─────────────────────────────────────────────────────

    /// @notice Deploy the factory with a Vault implementation for cloning
    constructor() {
        owner = msg.sender;
        // Deploy a single implementation contract for clone proxies
        implementation = address(new Vault());
    }

    // ─── External Functions ──────────────────────────────────────────────

    /// @notice Create a new vault for a token pair and fee tier
    /// @dev Uses CREATE2 with a minimal clone (EIP-1167) for deterministic addresses
    /// @param token0  Address of the first token
    /// @param token1  Address of the second token
    /// @param feeTier  Fee tier in hundredths of a bip (e.g., 3000 = 0.3%)
    /// @return vault  Address of the created vault
    function createVault(address token0, address token1, uint24 feeTier)
        external
        returns (address vault)
    {
        if (token0 == token1) revert IdenticalAddresses();
        if (token0 == address(0) || token1 == address(0)) revert ZeroAddress();

        // Sort tokens
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        bytes32 key = _poolKey(token0, token1, feeTier);
        if (_vaults[key] != address(0)) revert VaultAlreadyExists();

        // Deploy clone via CREATE2
        bytes32 salt = key;
        vault = _deployClone(salt);
        if (vault == address(0)) revert DeploymentFailed();

        // Initialize the vault
        Vault(vault).initialize(token0, token1, feeTier);

        // Store references
        _vaults[key] = vault;
        _allVaults.push(vault);

        emit VaultCreated(vault, token0, token1, feeTier);
    }

    /// @notice Get the vault address for a token pair and fee tier
    /// @param token0  Address of the first token
    /// @param token1  Address of the second token
    /// @param feeTier  Fee tier
    /// @return vault  Address of the vault (address(0) if not created)
    function getVault(address token0, address token1, uint24 feeTier)
        external
        view
        returns (address vault)
    {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        vault = _vaults[_poolKey(token0, token1, feeTier)];
    }

    /// @notice Get all deployed vault addresses
    /// @return Array of vault addresses
    function allVaults() external view returns (address[] memory) {
        return _allVaults;
    }

    /// @notice Get the total number of vaults
    /// @return Count of deployed vaults
    function allVaultsLength() external view returns (uint256) {
        return _allVaults.length;
    }

    // ─── Internal Functions ──────────────────────────────────────────────

    /// @notice Compute the pool key hash for a sorted token pair and fee tier
    function _poolKey(address token0, address token1, uint24 feeTier)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(token0, token1, feeTier));
    }

    /// @notice Deploy a minimal EIP-1167 clone using CREATE2
    /// @param salt  CREATE2 salt for deterministic addressing
    /// @return instance  Address of the deployed clone
    function _deployClone(bytes32 salt) internal returns (address instance) {
        address impl = implementation;
        /// @solidity memory-safe-assembly
        assembly {
            // EIP-1167 minimal proxy bytecode
            // 3d602d80600a3d3981f3363d3d373d3d3d363d73<impl>5af43d82803e903d91602b57fd5bf3
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(96, impl))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create2(0, ptr, 0x37, salt)
        }
    }
}
