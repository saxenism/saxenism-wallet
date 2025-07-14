// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title ISaxenismWallet
 * @notice Core interface for Saxenism multisig wallet functionality
 * @dev This interface defines the complete API for both proxy and logic contracts.
 *      All security-critical operations (ownership changes, upgrades, emergency exits)
 *      are executed through the unified executeTransaction interface to ensure
 *      consistent k-of-n signature validation and security controls.
 *
 * Security Design Principles:
 * - All critical operations require k-of-n signatures via executeTransaction
 * - Trusted delegate validation prevents dangerous proxy interactions
 * - Per-wallet nonce system prevents replay attacks
 * - Emergency exit mechanisms preserve user sovereignty
 * - EIP-712 structured signing with domain separation
 */
interface ISaxenismWallet {
    /**
     * @notice Operation type for transaction execution
     *     @dev CALL: regular contract interaction & DELEGATECALL: proxy-pattern execution
     */
    enum Operation {
        CALL,
        DELEGATECALL
    }

    /**
     * @notice Transaction structure for EIP-712 signing
     * @dev This struct is hashed and signed by wallet owners for execution authorization
     * @param target The contract address to call
     * @param value ETH value to send (in wei)
     * @param data Encoded function call data
     * @param operation CALL or DELEGATECALL execution type
     * @param nonce Per-wallet replay protection nonce (must be current + 1)
     * @param chainId Explicit chain identifier for cross-chain replay protection
     * @param verifyingContract Address of this wallet contract for binding protection
     */
    struct Transaction {
        address target;
        uint256 value;
        bytes data;
        Operation operation;
        uint256 nonce;
        uint256 chainId;
        address verifyingContract;
    }

    ////////////////////////////////
    // Core Execution Interface
    ////////////////////////////////

    /**
     * @notice Execute a transaction with k-of-n signature validation
     * @dev This is the ONLY way to execute security-critical operations.
     *      All ownership changes, upgrades, and emergency actions flow through here.
     *
     * Security validations performed:
     * - Verify k-of-n signature threshold with unique signers
     * - Check nonce for replay protection (must be current nonce + 1)
     * - Validate trusted delegates for DELEGATECALL operations
     * - Use ExcessivelySafeCall for returnbomb protection
     *
     * @param target Contract address to call
     * @param value ETH value to send (wei)
     * @param data Encoded function call data
     * @param operation CALL or DELEGATECALL
     * @param signatures Array of EIP-712 signatures from owners (must be unique)
     * @return success True if transaction executed successfully
     * @return returnData Data returned from the target call
     */
    function executeTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        Operation operation,
        bytes[] calldata signatures
    ) external returns (bool success, bytes memory returnData);

    //////////////////////////////////
    // Security Critical Operations
    //////////////////////////////////

    // All security critical operations are internal and can be called only via `executeTransaction`

    /**
     * @notice Change wallet ownership structure
     * @dev SECURITY CRITICAL: Only callable via executeTransaction with k-of-n signatures
     *
     *      ENFORCED INVARIANTS (must be validated in implementation):
     *      - newThreshold > 0 (cannot have zero threshold)
     *      - newThreshold <= newOwners.length (threshold cannot exceed owner count)
     *      - newOwners.length > 0 (must have at least one owner)
     *      - All newOwners must be unique addresses (no duplicates)
     *      - No newOwners can be zero address
     *
     * @param newOwners Array of new owner addresses (must be unique, non-zero)
     * @param newThreshold New signature threshold (must be > 0 and <= newOwners.length)
     */
    function changeOwners(address[] calldata newOwners, uint256 newThreshold) external;

    /**
     * @notice Add/remove trusted delegate for safe DELEGATECALL operations
     * @dev SECURITY CRITICAL: Only callable via executeTransaction with k-of-n signatures
     *      Trusted delegates are contracts verified to not contain selfdestruct or
     *      dangerous delegatecall patterns that could compromise wallet security.
     * @param delegate Contract address to trust/untrust
     * @param trusted True to add to whitelist, false to remove
     */
    function setTrustedDelegate(address delegate, bool trusted) external;

    /**
     * @notice Add/remove address from emergency withdrawal whitelist
     * @dev SECURITY CRITICAL: Only callable via executeTransaction with k-of-n signatures
     * @param recipient Address to whitelist/delist for emergency withdrawals
     * @param whitelisted True to add to whitelist, false to remove
     */
    function setWithdrawalRecipient(address recipient, bool whitelisted) external;

    /**
     * @notice Upgrade wallet implementation (logic contract)
     * @dev SECURITY CRITICAL: Only callable via executeTransaction with k-of-n signatures
     *      Enables wallet-level autonomy over upgrade decisions. Users can choose
     *      whether/when to upgrade or exit the system entirely.
     * @param newImplementation Address of new logic contract
     * @param version Human-readable version string
     */
    function upgradeImplementation(address newImplementation, string calldata version) external;

    /**
     * @notice Emergency withdrawal of all funds to whitelisted address
     * @dev SECURITY CRITICAL: Only callable via executeTransaction with k-of-n signatures
     *      Provides user sovereignty - ability to exit system if disagreeing with upgrades
     *      or protocol governance decisions.
     * @param recipient Must be in withdrawal whitelist
     */
    function withdrawAllFunds(address recipient) external;

    /**
     * @notice Cancel a specific nonce for governance conflict resolution
     * @dev SECURITY CRITICAL: Only callable via executeTransaction with k-of-n signatures
     *
     *      GOVERNANCE USE CASE:
     *      When multiple conflicting transactions exist for the same nonce (both with valid
     *      k-of-n signatures), this function allows the community to democratically "reject"
     *      all pending proposals for that nonce and force renegotiation at the next nonce.
     *
     *      PRIVACY BENEFIT:
     *      Avoids revealing which specific transaction payload was problematic, maintaining
     *      political neutrality in governance decisions.
     *
     *      SECURITY INVARIANTS:
     *      - nonceToCancel must be >= current nonce (cannot cancel past transactions)
     *      - After cancellation, current nonce becomes max(current, nonceToCancel + 1)
     *      - All pending transactions with nonce <= nonceToCancel become invalid
     *
     * @param nonceToCancel Specific nonce to invalidate (must be >= current nonce)
     */
    function cancelNonce(uint256 nonceToCancel) external;

    ////////////////////
    // View Function
    ////////////////////

    /**
     * @notice Get current wallet owners
     * @return Array of owner addresses
     */
    function getOwners() external view returns (address[] memory);

    /**
     * @notice Get current signature threshold
     * @return Number of signatures required for execution
     */
    function getThreshold() external view returns (uint256);

    /**
     * @notice Get current transaction nonce
     * @return Current nonce value (next transaction must use nonce + 1)
     */
    function getNonce() external view returns (uint256);

    /**
     * @notice Check if address is a trusted delegate
     * @param delegate Address to check
     * @return True if delegate is trusted for DELEGATECALL operations
     */
    function isTrustedDelegate(address delegate) external view returns (bool);

    /**
     * @notice Check if address is whitelisted for emergency withdrawals
     * @param recipient Address to check
     * @return True if recipient can receive emergency withdrawals
     */
    function isWithdrawalRecipient(address recipient) external view returns (bool);

    /**
     * @notice Get current implementation address (logic contract)
     * @return Address of current logic contract
     */
    function getImplementation() external view returns (address);

    /**
     * @notice Get implementation version string
     * @return Human-readable version of current implementation
     */
    function getVersion() external view returns (string memory);

    /**
     * @notice Generate EIP-712 transaction hash for signing
     * @dev This hash should be signed by wallet owners for executeTransaction
     * @param transaction Transaction struct to hash
     * @return EIP-712 compliant hash for signature generation
     */
    function getTransactionHash(Transaction calldata transaction) external view returns (bytes32);

    /**
     * @notice Verify if signatures are valid for a transaction
     * @dev Useful for off-chain validation before submission
     * @param txHash EIP-712 transaction hash
     * @param signatures Array of signatures to verify
     * @return True if signatures meet k-of-n threshold with current owners
     */
    function verifySignatures(bytes32 txHash, bytes[] calldata signatures) external view returns (bool);

    /////////////
    // Events
    /////////////

    /**
     * @notice Emitted when a transaction is successfully executed
     * @param txHash EIP-712 hash of the executed transaction
     * @param target Contract address that was called
     * @param value ETH value sent
     * @param operation Type of call (CALL/DELEGATECALL)
     * @param nonce Nonce used for this transaction
     */
    event TransactionExecuted(
        bytes32 indexed txHash, address indexed target, uint256 value, Operation operation, uint256 nonce
    );

    /**
     * @notice Emitted when wallet ownership structure changes
     * @param oldOwners Previous owner addresses
     * @param newOwners New owner addresses
     * @param oldThreshold Previous signature threshold
     * @param newThreshold New signature threshold
     */
    event OwnersChanged(address[] oldOwners, address[] newOwners, uint256 oldThreshold, uint256 newThreshold);

    /**
     * @notice Emitted when a trusted delegate is added or removed
     * @param delegate Address of the delegate contract
     * @param trusted True if added to whitelist, false if removed
     */
    event TrustedDelegateChanged(address indexed delegate, bool trusted);

    /**
     * @notice Emitted when withdrawal whitelist is modified
     * @param recipient Address added to or removed from withdrawal whitelist
     * @param whitelisted True if added, false if removed
     */
    event WithdrawalRecipientChanged(address indexed recipient, bool whitelisted);

    /**
     * @notice Emitted when implementation is upgraded
     * @param oldImplementation Previous logic contract address
     * @param newImplementation New logic contract address
     * @param version Version string of new implementation
     */
    event ImplementationUpgraded(address indexed oldImplementation, address indexed newImplementation, string version);

    /**
     * @notice Emitted during emergency fund withdrawal
     * @param recipient Address receiving all funds
     * @param ethAmount ETH amount withdrawn
     */
    event EmergencyWithdrawal(address indexed recipient, uint256 ethAmount);

    /**
     * @notice Emitted when a nonce is cancelled for governance conflict resolution
     * @param cancelledNonce The nonce that was invalidated
     * @param newCurrentNonce The current nonce after cancellation
     */
    event NonceCancelled(uint256 indexed cancelledNonce, uint256 newCurrentNonce);
}
