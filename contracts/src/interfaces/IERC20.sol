// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC20
/// @notice Standard ERC-20 token interface
interface IERC20 {
    /// @notice Emitted when `value` tokens are moved from `from` to `to`
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when the allowance of a `spender` for an `owner` is set
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Returns the total supply of tokens
    function totalSupply() external view returns (uint256);

    /// @notice Returns the balance of `account`
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfers `amount` tokens to `to`
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Returns the remaining allowance of `spender` for `owner`
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Approves `spender` to spend `amount` tokens
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Transfers `amount` tokens from `from` to `to`
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
