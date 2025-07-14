// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface ISaxenismWallet {
    /**
     * @notice Operation type for transaction execution
     *     @dev CALL: regular contract interaction & DELEGATECALL: proxy-pattern execution
     */
    enum Operation {
        CALL,
        DELEGATECALL
    }

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

    function changeOwners(address[] calldata newOwners, uint256 newThreshold) external;

    function setTrustedDelegate(address delegate, bool trusted) external;

    function setWithdrawalRecipient(address recipient, bool whitelisted) external;

    function upgradeImplementation(address newImplementation, string calldata version) external;

    function withdrawAllFunds(address recipient) external;

    function cancelNonce(uint256 nonceToCancel) external;

    ////////////////////
    // View Function
    ////////////////////

    function getOwners() external view returns (address[] memory);

    function getThreshold() external view returns (uint256);

    function getNonce() external view returns (uint256);

    function isTrustedDelegate(address delegate) external view returns (bool);

    function isWithdrawalRecipient(address recipient) external view returns (bool);

    function getImplementation() external view returns (address);

    function getVersion() external view returns (string memory);

    function getTransactionHash(Transaction calldata transaction) external view returns (bytes32);

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
