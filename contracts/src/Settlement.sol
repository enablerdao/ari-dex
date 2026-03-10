// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPermit2} from "./interfaces/IPermit2.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @title Settlement
/// @author ARI DEX
/// @notice Core settlement contract for intent-based order execution.
///         Solvers submit solutions (fill routes) that are verified via ZK proofs
///         before atomic token settlement through Permit2.
contract Settlement {
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

    // ─── Structs ─────────────────────────────────────────────────────────

    /// @notice Represents a user's trade intent
    /// @param sender  The user who wants to trade
    /// @param sellToken  Token the user is selling
    /// @param sellAmount  Amount of sellToken offered
    /// @param buyToken  Token the user wants to receive
    /// @param minBuyAmount  Minimum acceptable amount of buyToken
    /// @param deadline  Unix timestamp after which the intent expires
    /// @param nonce  Unique nonce to prevent replay attacks
    struct Intent {
        address sender;
        address sellToken;
        uint256 sellAmount;
        address buyToken;
        uint256 minBuyAmount;
        uint256 deadline;
        uint256 nonce;
    }

    /// @notice Represents a solver's proposed fill for an intent
    /// @param intentHash  Keccak256 hash of the corresponding Intent
    /// @param solver  Address of the solver providing the fill
    /// @param buyAmount  Actual amount of buyToken the solver will deliver
    /// @param route  Encoded routing data for the fill (opaque bytes)
    struct Solution {
        bytes32 intentHash;
        address solver;
        uint256 buyAmount;
        bytes route;
    }

    // ─── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted when a single intent is settled
    /// @param intentHash  Hash of the settled intent
    /// @param solver  Solver that filled the order
    /// @param sender  User whose intent was filled
    /// @param sellToken  Token sold
    /// @param sellAmount  Amount sold
    /// @param buyToken  Token bought
    /// @param buyAmount  Amount bought
    event IntentSettled(
        bytes32 indexed intentHash,
        address indexed solver,
        address indexed sender,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 buyAmount
    );

    /// @notice Emitted when a batch of intents is settled
    /// @param batchId  Unique identifier for the batch (hash of all intent hashes)
    /// @param solver  Solver that filled the batch
    /// @param count  Number of intents in the batch
    event BatchSettled(bytes32 indexed batchId, address indexed solver, uint256 count);

    /// @notice Emitted when the contract is paused or unpaused
    /// @param isPaused  New pause state
    event PauseToggled(bool isPaused);

    // ─── Errors ──────────────────────────────────────────────────────────

    error Unauthorized();
    error ContractPaused();
    error Reentrancy();
    error IntentExpired();
    error NonceAlreadyUsed();
    error InsufficientBuyAmount();
    error InvalidProof();
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

    /// @notice Deploys the Settlement contract
    /// @param _permit2  Address of the Permit2 contract
    /// @param _verifier  Address of the ZK proof verifier
    /// @param _guardian  Address of the guardian multisig
    constructor(address _permit2, address _verifier, address _guardian) {
        owner = msg.sender;
        permit2 = IPermit2(_permit2);
        verifier = _verifier;
        guardian = _guardian;
    }

    // ─── External Functions ──────────────────────────────────────────────

    /// @notice Settle a single intent with a solver's solution
    /// @param intent  The user's trade intent
    /// @param solution  The solver's proposed fill
    /// @param proof  ZK proof validating the solution's correctness
    function settle(
        Intent calldata intent,
        Solution calldata solution,
        bytes calldata proof
    ) external whenNotPaused nonReentrant {
        bytes32 intentHash = _hashIntent(intent);

        // Validate intent
        if (block.timestamp > intent.deadline) revert IntentExpired();
        if (usedNonces[intent.sender][intent.nonce]) revert NonceAlreadyUsed();
        if (solution.buyAmount < intent.minBuyAmount) revert InsufficientBuyAmount();

        // Verify ZK proof
        if (!_verifyProof(intentHash, solution, proof)) revert InvalidProof();

        // Mark nonce as used
        usedNonces[intent.sender][intent.nonce] = true;

        // Transfer sellToken from sender to solver
        IERC20(intent.sellToken).transferFrom(intent.sender, solution.solver, intent.sellAmount);

        // Transfer buyToken from solver to sender
        IERC20(intent.buyToken).transferFrom(solution.solver, intent.sender, solution.buyAmount);

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

    /// @notice Settle a batch of intents atomically
    /// @param intents  Array of user trade intents
    /// @param solutions  Array of solver solutions (must match intents length)
    /// @param batchProof  ZK proof validating the entire batch
    function settleBatch(
        Intent[] calldata intents,
        Solution[] calldata solutions,
        bytes calldata batchProof
    ) external whenNotPaused nonReentrant {
        uint256 len = intents.length;
        if (len != solutions.length) revert ArrayLengthMismatch();

        bytes32[] memory intentHashes = new bytes32[](len);

        for (uint256 i; i < len; ++i) {
            intentHashes[i] = _hashIntent(intents[i]);

            if (block.timestamp > intents[i].deadline) revert IntentExpired();
            if (usedNonces[intents[i].sender][intents[i].nonce]) revert NonceAlreadyUsed();
            if (solutions[i].buyAmount < intents[i].minBuyAmount) revert InsufficientBuyAmount();

            usedNonces[intents[i].sender][intents[i].nonce] = true;

            // Transfer sellToken from sender to solver
            IERC20(intents[i].sellToken).transferFrom(
                intents[i].sender, solutions[i].solver, intents[i].sellAmount
            );

            // Transfer buyToken from solver to sender
            IERC20(intents[i].buyToken).transferFrom(
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

    /// @notice Pause the contract (circuit breaker)
    function pause() external onlyGuardian {
        paused = true;
        emit PauseToggled(true);
    }

    /// @notice Unpause the contract
    function unpause() external onlyGuardian {
        paused = false;
        emit PauseToggled(false);
    }

    /// @notice Update the ZK verifier address
    /// @param _verifier  New verifier contract address
    function setVerifier(address _verifier) external onlyOwner {
        verifier = _verifier;
    }

    /// @notice Update the guardian multisig
    /// @param _guardian  New guardian address
    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
    }

    // ─── Internal Functions ──────────────────────────────────────────────

    /// @notice Hash an intent for uniqueness and verification
    /// @param intent  The intent to hash
    /// @return The keccak256 hash of the encoded intent
    function _hashIntent(Intent calldata intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                intent.sender,
                intent.sellToken,
                intent.sellAmount,
                intent.buyToken,
                intent.minBuyAmount,
                intent.deadline,
                intent.nonce
            )
        );
    }

    /// @notice Verify a ZK proof for a solution (stub — always returns true)
    /// @dev Replace with actual plonk/groth16 verification when verifier is deployed
    /// @param intentHash  Hash of the intent being verified
    /// @param solution  The solution to verify
    /// @param proof  The ZK proof bytes
    /// @return valid  Whether the proof is valid
    function _verifyProof(
        bytes32 intentHash,
        Solution calldata solution,
        bytes calldata proof
    ) internal view returns (bool valid) {
        // TODO: Integrate actual ZK verifier contract
        // For now, return true to allow testing of settlement logic
        (intentHash, solution, proof); // silence unused warnings
        return true;
    }
}
