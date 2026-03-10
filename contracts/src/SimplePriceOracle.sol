// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

/// @title SimplePriceOracle
/// @notice Owner-settable price oracle for testnet use
contract SimplePriceOracle is IPriceOracle {
    address public owner;
    mapping(address => uint256) private _prices;

    error Unauthorized();
    error PriceNotSet();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Set the price for a token
    /// @param token The token address
    /// @param price The price with 6 decimals
    function setPrice(address token, uint256 price) external onlyOwner {
        _prices[token] = price;
    }

    /// @notice Get the current price of a token
    /// @param token The token address
    /// @return price The current price with 6 decimals
    function getPrice(address token) external view override returns (uint256 price) {
        price = _prices[token];
        if (price == 0) revert PriceNotSet();
    }
}
