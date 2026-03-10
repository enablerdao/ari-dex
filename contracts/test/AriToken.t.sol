// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AriToken} from "../src/AriToken.sol";

contract AriTokenTest is Test {
    AriToken public token;

    address public owner = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        token = new AriToken(owner);
    }

    // ─── Deployment Tests ───────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(token.name(), "ARI Token");
        assertEq(token.symbol(), "ARI");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.owner(), owner);
        assertEq(token.MAX_SUPPLY(), 1_000_000_000e18);
    }

    // ─── Mint Tests ─────────────────────────────────────────────────────

    function test_mint() public {
        token.mint(alice, 1000e18);

        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    function test_mint_up_to_max_supply() public {
        uint256 maxSupply = token.MAX_SUPPLY();
        token.mint(alice, maxSupply);

        assertEq(token.totalSupply(), maxSupply);
        assertEq(token.balanceOf(alice), maxSupply);
    }

    function test_mint_reverts_exceeds_max_supply() public {
        uint256 maxSupply = token.MAX_SUPPLY();
        token.mint(alice, maxSupply);

        vm.expectRevert(AriToken.ExceedsMaxSupply.selector);
        token.mint(alice, 1);
    }

    function test_mint_reverts_single_call_exceeds_max() public {
        vm.expectRevert(AriToken.ExceedsMaxSupply.selector);
        token.mint(alice, 1_000_000_001e18);
    }

    function test_mint_reverts_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        token.mint(alice, 100e18);
    }

    // ─── Burn Tests ─────────────────────────────────────────────────────

    function test_burn() public {
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.burn(400e18);

        assertEq(token.balanceOf(alice), 600e18);
        assertEq(token.totalSupply(), 600e18);
    }

    function test_burn_reverts_insufficient_balance() public {
        token.mint(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert();
        token.burn(200e18);
    }

    function test_anyone_can_burn_own_tokens() public {
        token.mint(bob, 500e18);

        vm.prank(bob);
        token.burn(500e18);

        assertEq(token.balanceOf(bob), 0);
    }

    // ─── Transfer Tests ─────────────────────────────────────────────────

    function test_transfer() public {
        token.mint(alice, 100e18);

        vm.prank(alice);
        token.transfer(bob, 50e18);

        assertEq(token.balanceOf(alice), 50e18);
        assertEq(token.balanceOf(bob), 50e18);
    }
}
