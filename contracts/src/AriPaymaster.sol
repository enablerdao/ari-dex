// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AriPaymaster
/// @author ARI DEX
/// @notice Simplified ERC-4337 Paymaster that sponsors gas for whitelisted
///         ARI intent operations (Settlement.settle and Settlement.settleBatch).
contract AriPaymaster {
    // ─── State ───────────────────────────────────────────────────────────

    /// @notice Contract owner
    address public owner;

    /// @notice ETH balance deposited for gas sponsorship
    uint256 public depositBalance;

    /// @notice Whitelisted function selectors that can be sponsored
    mapping(bytes4 => bool) public whitelistedSelectors;

    /// @notice Whitelisted target contracts
    mapping(address => bool) public whitelistedTargets;

    // ─── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted when ETH is deposited for sponsorship
    event Deposited(address indexed from, uint256 amount);

    /// @notice Emitted when ETH is withdrawn
    event Withdrawn(address indexed to, uint256 amount);

    /// @notice Emitted when a selector is whitelisted or removed
    event SelectorUpdated(bytes4 indexed selector, bool allowed);

    /// @notice Emitted when a target contract is whitelisted or removed
    event TargetUpdated(address indexed target, bool allowed);

    /// @notice Emitted when a user operation is validated for sponsorship
    event UserOpSponsored(address indexed sender, address indexed target, bytes4 selector);

    // ─── Errors ──────────────────────────────────────────────────────────

    error Unauthorized();
    error InsufficientDeposit();
    error OperationNotWhitelisted();
    error WithdrawFailed();
    error ZeroAmount();

    // ─── Modifiers ───────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────

    /// @notice Deploy the paymaster
    /// @param _settlement Address of the Settlement contract to whitelist
    constructor(address _settlement) {
        owner = msg.sender;

        // Whitelist Settlement contract
        whitelistedTargets[_settlement] = true;

        // Whitelist settle() and settleBatch() selectors
        // settle(Intent,Solution,bytes) => first 4 bytes of keccak256
        // We store well-known selectors; owner can add more via addSelector()
        // settle((address,address,uint256,address,uint256,uint256,uint256),(bytes32,address,uint256,bytes),bytes)
        // settleBatch((address,address,uint256,address,uint256,uint256,uint256)[],(bytes32,address,uint256,bytes)[],bytes)
        bytes4 settleSelector = bytes4(keccak256("settle((address,address,uint256,address,uint256,uint256,uint256),(bytes32,address,uint256,bytes),bytes)"));
        bytes4 settleBatchSelector = bytes4(keccak256("settleBatch((address,address,uint256,address,uint256,uint256,uint256)[],(bytes32,address,uint256,bytes)[],bytes)"));

        whitelistedSelectors[settleSelector] = true;
        whitelistedSelectors[settleBatchSelector] = true;
    }

    // ─── External Functions ──────────────────────────────────────────────

    /// @notice Validate whether a user operation should be sponsored
    /// @param sender The user submitting the operation
    /// @param target The contract being called
    /// @param callData The calldata of the operation (selector + params)
    /// @return valid Whether the operation is sponsored
    function validatePaymasterUserOp(
        address sender,
        address target,
        bytes calldata callData
    ) external returns (bool valid) {
        // Check that the target is whitelisted
        if (!whitelistedTargets[target]) revert OperationNotWhitelisted();

        // Extract the function selector (first 4 bytes)
        if (callData.length < 4) revert OperationNotWhitelisted();
        bytes4 selector = bytes4(callData[:4]);

        // Check that the selector is whitelisted
        if (!whitelistedSelectors[selector]) revert OperationNotWhitelisted();

        // Check deposit balance (simplified: just check non-zero)
        if (depositBalance == 0) revert InsufficientDeposit();

        emit UserOpSponsored(sender, target, selector);

        return true;
    }

    /// @notice Deposit ETH for gas sponsorship
    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        depositBalance += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH from the deposit (owner only)
    /// @param amount Amount to withdraw
    function withdraw(uint256 amount) external onlyOwner {
        if (amount > depositBalance) revert InsufficientDeposit();
        depositBalance -= amount;

        (bool success,) = payable(owner).call{value: amount}("");
        if (!success) revert WithdrawFailed();

        emit Withdrawn(owner, amount);
    }

    /// @notice Add or remove a whitelisted function selector
    /// @param selector The 4-byte function selector
    /// @param allowed Whether to allow or disallow
    function setSelector(bytes4 selector, bool allowed) external onlyOwner {
        whitelistedSelectors[selector] = allowed;
        emit SelectorUpdated(selector, allowed);
    }

    /// @notice Add or remove a whitelisted target contract
    /// @param target The contract address
    /// @param allowed Whether to allow or disallow
    function setTarget(address target, bool allowed) external onlyOwner {
        whitelistedTargets[target] = allowed;
        emit TargetUpdated(target, allowed);
    }

    /// @notice Transfer ownership
    /// @param newOwner New owner address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    /// @notice Accept ETH deposits
    receive() external payable {
        depositBalance += msg.value;
        emit Deposited(msg.sender, msg.value);
    }
}
