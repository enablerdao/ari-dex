// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPermit2} from "./interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Settlement
/// @author ARI DEX
/// @notice Core settlement contract for intent-based order execution.
///         Solvers submit solutions that are verified via EIP-712 signatures
///         before atomic token settlement.
contract Settlement {
    using SafeERC20 for IERC20;

    // ─── State ───────────────────────────────────────────────────────────

    /// @notice Contract owner (admin)
    address public owner;

    /// @notice ZK proof verifier address (stub for future plonk/groth16 verifier)
    address public verifier;

    /// @notice Uniswap Permit2 instance for gasless approvals
    IPermit2 public immutable permit2;

    /// @notice Guardian multisig that can pause the contract
    address public guardian;

    /// @notice Whether the contract is paused
    bool public paused;

    /// @notice Reentrancy lock
    uint256 private _locked = 1;

    /// @notice Tracks used nonces per sender to prevent replay
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    // ─── EIP-712 ─────────────────────────────────────────────────────────

    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 public constant INTENT_TYPEHASH = keccak256(
        "Intent(address sender,address sellToken,uint256 sellAmount,address buyToken,uint256 minBuyAmount,uint256 deadline,uint256 nonce)"
    );

    // ─── Structs ─────────────────────────────────────────────────────────

    /// @notice Represents a user's trade intent
    struct Intent {
        address sender;
        address sellToken;
        uint256 sellAmount;
        address buyToken;
        uint256 minBuyAmount;
        uint256 deadline;
        uint256 nonce;
        bytes signature;
    }

    /// @notice Represents a solver's proposed fill for an intent
    struct Solution {
        bytes32 intentHash;
        address solver;
        uint256 buyAmount;
        bytes route;
    }

    // ─── Events ──────────────────────────────────────────────────────────

    event IntentSettled(
        bytes32 indexed intentHash,
        address indexed solver,
        address indexed sender,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 buyAmount
    );

    event BatchSettled(bytes32 indexed batchId, address indexed solver, uint256 count);

    event PauseToggled(bool isPaused);

    // ─── Errors ──────────────────────────────────────────────────────────

    error Unauthorized();
    error ContractPaused();
    error Reentrancy();
    error IntentExpired();
    error NonceAlreadyUsed();
    error InsufficientBuyAmount();
    error InvalidSignature();
    error ArrayLengthMismatch();

    // ─── Modifiers ───────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian && msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier nonReentrant() {
        if (_locked == 2) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    // ─── Constructor ─────────────────────────────────────────────────────

    constructor(address _permit2, address _verifier, address _guardian) {
        owner = msg.sender;
        permit2 = IPermit2(_permit2);
        verifier = _verifier;
        guardian = _guardian;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("ARI Exchange"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    // ─── External Functions ──────────────────────────────────────────────

    function settle(
        Intent calldata intent,
        Solution calldata solution,
        bytes calldata /* proof */
    ) external whenNotPaused nonReentrant {
        bytes32 intentHash = _hashIntent(intent);

        // Validate intent
        if (block.timestamp > intent.deadline) revert IntentExpired();
        if (usedNonces[intent.sender][intent.nonce]) revert NonceAlreadyUsed();
        if (solution.buyAmount < intent.minBuyAmount) revert InsufficientBuyAmount();

        // Verify EIP-712 signature
        _verifySignature(intentHash, intent.sender, intent.signature);

        // Mark nonce as used
        usedNonces[intent.sender][intent.nonce] = true;

        // Transfer sellToken from sender to solver
        IERC20(intent.sellToken).safeTransferFrom(intent.sender, solution.solver, intent.sellAmount);

        // Transfer buyToken from solver to sender
        IERC20(intent.buyToken).safeTransferFrom(solution.solver, intent.sender, solution.buyAmount);

        emit IntentSettled(
            intentHash,
            solution.solver,
            intent.sender,
            intent.sellToken,
            intent.sellAmount,
            intent.buyToken,
            solution.buyAmount
        );
    }

    function settleBatch(
        Intent[] calldata intents,
        Solution[] calldata solutions,
        bytes calldata /* batchProof */
    ) external whenNotPaused nonReentrant {
        uint256 len = intents.length;
        if (len != solutions.length) revert ArrayLengthMismatch();

        bytes32[] memory intentHashes = new bytes32[](len);

        for (uint256 i; i < len; ++i) {
            intentHashes[i] = _hashIntent(intents[i]);

            if (block.timestamp > intents[i].deadline) revert IntentExpired();
            if (usedNonces[intents[i].sender][intents[i].nonce]) revert NonceAlreadyUsed();
            if (solutions[i].buyAmount < intents[i].minBuyAmount) revert InsufficientBuyAmount();

            // Verify EIP-712 signature per intent
            _verifySignature(intentHashes[i], intents[i].sender, intents[i].signature);

            usedNonces[intents[i].sender][intents[i].nonce] = true;

            // Transfer sellToken from sender to solver
            IERC20(intents[i].sellToken).safeTransferFrom(
                intents[i].sender, solutions[i].solver, intents[i].sellAmount
            );

            // Transfer buyToken from solver to sender
            IERC20(intents[i].buyToken).safeTransferFrom(
                solutions[i].solver, intents[i].sender, solutions[i].buyAmount
            );

            emit IntentSettled(
                intentHashes[i],
                solutions[i].solver,
                intents[i].sender,
                intents[i].sellToken,
                intents[i].sellAmount,
                intents[i].buyToken,
                solutions[i].buyAmount
            );
        }

        bytes32 batchId = keccak256(abi.encodePacked(intentHashes));
        emit BatchSettled(batchId, msg.sender, len);
    }

    // ─── Admin Functions ─────────────────────────────────────────────────

    function pause() external onlyGuardian {
        paused = true;
        emit PauseToggled(true);
    }

    function unpause() external onlyGuardian {
        paused = false;
        emit PauseToggled(false);
    }

    function setVerifier(address _verifier) external onlyOwner {
        verifier = _verifier;
    }

    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
    }

    // ─── Internal Functions ──────────────────────────────────────────────

    /// @notice Hash an intent using EIP-712 typed data with chain binding
    function _hashIntent(Intent calldata intent) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                INTENT_TYPEHASH,
                intent.sender,
                intent.sellToken,
                intent.sellAmount,
                intent.buyToken,
                intent.minBuyAmount,
                intent.deadline,
                intent.nonce
            )
        );
        return keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
    }

    /// @notice Verify that the signature was produced by the expected signer
    function _verifySignature(
        bytes32 digest,
        address expectedSigner,
        bytes calldata signature
    ) internal pure {
        if (signature.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }

        // Enforce s-value is in lower half to prevent signature malleability
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignature();
        }

        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != expectedSigner) {
            revert InvalidSignature();
        }
    }
}
