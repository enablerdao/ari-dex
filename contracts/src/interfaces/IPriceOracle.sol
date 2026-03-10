// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPriceOracle
/// @notice Simple price feed interface for conditional orders
interface IPriceOracle {
    /// @notice Get the current price of a token
    /// @param token The token address to query
    /// @return price The current price with 6 decimals
    function getPrice(address token) external view returns (uint256 price);
}
