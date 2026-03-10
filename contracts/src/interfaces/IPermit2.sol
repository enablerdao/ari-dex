// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPermit2
/// @notice Interface for Uniswap's Permit2 contract for gasless token approvals
interface IPermit2 {
    /// @notice Token and amount in a permit message
    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    /// @notice The permit data for a transfer
    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    /// @notice Specifies the recipient address and amount for a single transfer
    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    /// @notice Transfers a token using a signed permit message
    /// @param permit The permit data signed over by the owner
    /// @param transferDetails The spender's requested transfer details for the permitted token
    /// @param owner The owner of the tokens to transfer
    /// @param signature The signature over the permit data
    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}
