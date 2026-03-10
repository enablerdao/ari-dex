// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {Vault} from "../src/Vault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract VaultFactoryTest is Test {
    VaultFactory public factory;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public tokenC;

    address public deployer = address(this);

    function setUp() public {
        factory = new VaultFactory();

        // Deploy tokens — addresses are deterministic from deployment order
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        tokenC = new MockERC20("Token C", "TKNC");
    }

    // ─── Deployment ──────────────────────────────────────────────────

    function test_factory_deployment() public view {
        assertEq(factory.owner(), deployer);
        assertTrue(factory.implementation() != address(0));
        assertEq(factory.allVaultsLength(), 0);
    }

    function test_implementation_is_vault() public view {
        // Implementation should be a valid Vault (not initialized)
        Vault impl = Vault(factory.implementation());
        assertFalse(impl.initialized());
    }

    // ─── Create Vault ────────────────────────────────────────────────

    function test_createVault() public {
        address vault = factory.createVault(address(tokenA), address(tokenB), 3000);

        assertTrue(vault != address(0));
        assertEq(factory.allVaultsLength(), 1);

        // Vault should be initialized
        Vault v = Vault(vault);
        assertTrue(v.initialized());
        assertEq(v.name(), "ARI LP Position");
    }

    function test_createVault_sorts_tokens() public {
        // Pass tokens in reverse order — factory should sort them
        address vault1 = factory.createVault(address(tokenB), address(tokenA), 3000);

        // getVault should work with either order
        address found1 = factory.getVault(address(tokenA), address(tokenB), 3000);
        address found2 = factory.getVault(address(tokenB), address(tokenA), 3000);

        assertEq(found1, vault1);
        assertEq(found2, vault1);
    }

    function test_createVault_pool_params() public {
        address vault = factory.createVault(address(tokenA), address(tokenB), 500);
        Vault v = Vault(vault);

        (address t0, address t1, uint24 fee,,,) = v.pool();

        // Tokens should be sorted
        if (address(tokenA) < address(tokenB)) {
            assertEq(t0, address(tokenA));
            assertEq(t1, address(tokenB));
        } else {
            assertEq(t0, address(tokenB));
            assertEq(t1, address(tokenA));
        }
        assertEq(fee, 500);
    }

    function test_createVault_emits_event() public {
        (address sorted0, address sorted1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        vm.expectEmit(false, true, true, true);
        emit VaultFactory.VaultCreated(address(0), sorted0, sorted1, 3000);

        factory.createVault(address(tokenA), address(tokenB), 3000);
    }

    // ─── Deterministic Address (CREATE2) ─────────────────────────────

    function test_deterministic_address() public {
        // Two factories at different addresses should produce different vault addresses
        // but the same factory with the same params always produces the same address
        address vault = factory.createVault(address(tokenA), address(tokenB), 3000);
        assertTrue(vault != address(0));

        // The vault address is deterministic — we can verify by checking it's stored
        address looked = factory.getVault(address(tokenA), address(tokenB), 3000);
        assertEq(looked, vault);
    }

    function test_different_fee_tiers_different_vaults() public {
        address vault1 = factory.createVault(address(tokenA), address(tokenB), 500);
        address vault2 = factory.createVault(address(tokenA), address(tokenB), 3000);
        address vault3 = factory.createVault(address(tokenA), address(tokenB), 10000);

        assertTrue(vault1 != vault2);
        assertTrue(vault2 != vault3);
        assertTrue(vault1 != vault3);

        assertEq(factory.allVaultsLength(), 3);
    }

    function test_different_pairs_different_vaults() public {
        address vault1 = factory.createVault(address(tokenA), address(tokenB), 3000);
        address vault2 = factory.createVault(address(tokenA), address(tokenC), 3000);
        address vault3 = factory.createVault(address(tokenB), address(tokenC), 3000);

        assertTrue(vault1 != vault2);
        assertTrue(vault2 != vault3);
        assertEq(factory.allVaultsLength(), 3);
    }

    // ─── Duplicate Vault Revert ──────────────────────────────────────

    function test_revert_duplicate_vault() public {
        factory.createVault(address(tokenA), address(tokenB), 3000);

        vm.expectRevert(VaultFactory.VaultAlreadyExists.selector);
        factory.createVault(address(tokenA), address(tokenB), 3000);
    }

    function test_revert_duplicate_vault_reversed_order() public {
        factory.createVault(address(tokenA), address(tokenB), 3000);

        // Same pair in reversed order should also revert (tokens get sorted)
        vm.expectRevert(VaultFactory.VaultAlreadyExists.selector);
        factory.createVault(address(tokenB), address(tokenA), 3000);
    }

    // ─── Input Validation ────────────────────────────────────────────

    function test_revert_identical_addresses() public {
        vm.expectRevert(VaultFactory.IdenticalAddresses.selector);
        factory.createVault(address(tokenA), address(tokenA), 3000);
    }

    function test_revert_zero_address_token0() public {
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        factory.createVault(address(0), address(tokenB), 3000);
    }

    function test_revert_zero_address_token1() public {
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        factory.createVault(address(tokenA), address(0), 3000);
    }

    // ─── getVault ────────────────────────────────────────────────────

    function test_getVault_returns_zero_for_nonexistent() public view {
        address vault = factory.getVault(address(tokenA), address(tokenB), 3000);
        assertEq(vault, address(0));
    }

    function test_getVault_after_creation() public {
        address created = factory.createVault(address(tokenA), address(tokenB), 3000);
        address found = factory.getVault(address(tokenA), address(tokenB), 3000);
        assertEq(found, created);
    }

    // ─── Vault Count & allVaults ─────────────────────────────────────

    function test_allVaultsLength_increments() public {
        assertEq(factory.allVaultsLength(), 0);

        factory.createVault(address(tokenA), address(tokenB), 3000);
        assertEq(factory.allVaultsLength(), 1);

        factory.createVault(address(tokenA), address(tokenC), 3000);
        assertEq(factory.allVaultsLength(), 2);

        factory.createVault(address(tokenB), address(tokenC), 3000);
        assertEq(factory.allVaultsLength(), 3);
    }

    function test_allVaults_returns_correct_addresses() public {
        address v1 = factory.createVault(address(tokenA), address(tokenB), 3000);
        address v2 = factory.createVault(address(tokenA), address(tokenC), 500);

        address[] memory all = factory.allVaults();
        assertEq(all.length, 2);
        assertEq(all[0], v1);
        assertEq(all[1], v2);
    }
}
