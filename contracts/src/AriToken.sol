// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AriToken
/// @author ARI DEX
/// @notice ERC-20 governance token with capped supply and owner-only minting.
contract AriToken is ERC20, Ownable {
    /// @notice Maximum supply: 1 billion tokens (18 decimals)
    uint256 public constant MAX_SUPPLY = 1_000_000_000e18;

    // ─── Errors ──────────────────────────────────────────────────────────

    error ExceedsMaxSupply();

    // ─── Constructor ─────────────────────────────────────────────────────

    /// @notice Deploy the ARI Token
    /// @param initialOwner Address that will own the contract and can mint
    constructor(address initialOwner) ERC20("ARI Token", "ARI") Ownable(initialOwner) {}

    // ─── External Functions ──────────────────────────────────────────────

    /// @notice Mint new ARI tokens (owner only)
    /// @param to Recipient address
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external onlyOwner {
        if (totalSupply() + amount > MAX_SUPPLY) revert ExceedsMaxSupply();
        _mint(to, amount);
    }

    /// @notice Burn caller's own tokens
    /// @param amount Amount to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
