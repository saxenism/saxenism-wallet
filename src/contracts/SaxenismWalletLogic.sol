// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {ISaxenismWallet} from "../interfaces/ISaxenismWallet.sol";
import {ISaxenismWalletFactory} from "../interfaces/ISaxenismWalletFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ExcessivelySafeCall} from "@excessively-safe-call/ExcessivelySafeCall.sol";

/**
 * @title SaxenismWalletLogic
 * @notice Implementation contract for Saxenism multisig wallets
 * @dev This is the logic contract that all wallet proxies delegatecall to.
 *      Implements enterprise-grade multisig functionality with:
 *      - k-of-n signature validation using battle-tested ecrecover
 *      - EIP-712 structured data signing with replay protection
 *      - Self-administration (wallet controls its own upgrades)
 *      - Emergency controls and user sovereignty mechanisms
 *      - Trusted delegate validation for safe proxy interactions
 *
 * Security Architecture:
 * - All critical operations flow through executeTransaction (unified security model)
 * - Per-wallet nonce prevents replay attacks across all operations
 * - ExcessivelySafeCall prevents returnbomb attacks
 * - Trusted delegate whitelist prevents dangerous proxy interactions
 * - Emergency withdrawal preserves user sovereignty
 *
 * Upgrade Philosophy:
 * - Each wallet is self-administered (proxy admin = wallet address)
 * - Upgrades require k-of-n governance through executeTransaction
 * - Users can exit via withdrawAllFunds if disagreeing with protocol changes
 *
 * @author saxenism
 */
contract SaxenismWalletLogic is
    ISaxenismWallet,
    Initializable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
    using ECDSA for bytes32;
    using ExcessivelySafeCall for address;

    //////////////////
    // Storage
    //////////////////

    /// @notice Array of wallet owner addresses
    address[] private _owners;

    /// @notice Mapping for O(1) owner validation
    mapping(address => bool) private _isOwner;

    /// @notice Number of signatures required for transaction execution
    uint256 private _threshold;

    /// @notice Current transaction nonce (increments on each execution)
    uint256 private _nonce;

    /// @notice Mapping of trusted delegate contracts for safe DELEGATECALL operations
    mapping(address => bool) private _trustedDelegates;

    /// @notice Mapping of addresses whitelisted for emergency withdrawals
    mapping(address => bool) private _withdrawalRecipients;

    /// @notice Factory contract address for implementation validation
    address private _factory;

    /// @notice Current implementation version string
    string private _version;

    //////////////////////////////
    // Constants and Immutables
    //////////////////////////////

    /// @notice EIP-712 typehash for Transaction struct
    bytes32 private constant TRANSACTION_TYPEHASH = keccak256(
        "Transaction(address target, uint256 value, bytes data, uint8 operation,uint256 nonce,uint256 chainId,address verifyingContract)"
    );

    /// @notice Maximum number of owners to prevent gas issues
    uint256 private constant MAX_OWNERS = 50;

    /// @notice Gas limit for external calls to prevent griefing
    uint256 private constant EXTERNAL_CALL_GAS_LIMIT = 200_000;

    /// @notice Maximum bytes to copy from return data to prevent returnbomb attacks
    uint16 private constant MAX_RETURN_DATA_COPY = 256; //or whatever size you want

    ////////////////////////////////////////////////////
    // Initialization - Two phase self-administration
    ////////////////////////////////////////////////////

    /**
     * @notice Initialize wallet with two-phase self-administration
     * @dev This function is called during proxy deployment and performs the critical
     *      admin transfer that enables wallet self-sovereignty:
     *
     *      1. Standard wallet initialization (owners, threshold, version)
     *      2. CRITICAL: Transfer proxy admin from factory to wallet itself
     *      3. Wallet becomes self-administered for all future upgrades
     *
     *      This ensures all upgrades flow through executeTransaction (k-of-n governance)
     *      while maintaining technical compatibility with OpenZeppelin proxy patterns.
     *
     * @param owners Initial owner addresses (must be unique, non-zero)
     * @param threshold Signature threshold (must be > 0 and <= owners.length)
     * @param version Implementation version string
     */
    function initialize(address[] calldata owners, uint256 threshold, string calldata version) external initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __EIP712_init("SaxenismWallet", "1");

        // Validate initialization parameters
        _validateOwnerConfig(owners, threshold);

        // Set factory address (msg.sender during initialization is the factory)
        _factory = msg.sender;

        _version = version;

        _setOwners(owners, threshold);

        _nonce = 0;

        // CRITICAL STEP: Transfer proxy admin from factory to wallet itself
        // This enables true self-administration while maintaining technical feasibility
        // Using low-level call since changeAdmin is not in the interface
        (bool success,) = address(this).call(abi.encodeWithSignature("changeAdmin(address)", address(this)));
        require(success, "SaxenismWalletLogic: admin transfer failed");

        emit OwnersChanged(new address[](0), owners, 0, threshold);
    }

    ///////////////////////////
    // Core Execution Engine
    ///////////////////////////

    /**
     * @notice Execute a transaction with k-of-n signature validation
     * @dev This is the ONLY entry point for all security-critical operations.
     *      Provides unified security validation for:
     *      - Regular transactions (transfers, contract calls)
     *      - Ownership changes (changeOwners)
     *      - Emergency actions (withdrawAllFunds)
     *      - Upgrade operations (upgradeImplementation)
     *      - Configuration changes (trusted delegates, withdrawal whitelist)
     *
     * @inheritdoc ISaxenismWallet
     */
    function executeTransaction(
        address target,
        uint256 value,
        bytes calldata data,
        Operation operation,
        bytes[] calldata signatures
    ) external override nonReentrant whenNotPaused returns (bool success, bytes memory returnData) {
        Transaction memory txn = Transaction({
            target: target,
            value: value,
            data: data,
            operation: operation,
            nonce: _nonce,
            chainId: block.chainid,
            verifyingContract: address(this)
        });

        // Generate EIP-712 hash
        bytes32 txHash = _getTransactionHash(txn);

        // Verify k-of-n signatures
        require(_verifySignatures(txHash, signatures), "SaxenismWalletLogic: invalid signatures");

        // Validate operation-specific requirements
        if (operation == Operation.DELEGATECALL) {
            require(_trustedDelegates[target], "SaxenismWalletLogic: untrusted delegate");
        }

        // increment the nonce for replay protection
        _nonce++;

        // Execute the transaction
        if (operation == Operation.CALL) {
            (success, returnData) =
                target.excessivelySafeCall(EXTERNAL_CALL_GAS_LIMIT, value, MAX_RETURN_DATA_COPY, data);
        } else {
            // ExcessivelySafeCall doesn't support delegatecall
            // Raw delegatecall is safe here since we only allow trusted delegate addresses
            (success, returnData) = target.delegatecall(data);
        }

        emit TransactionExecuted(txHash, target, value, operation, _nonce - 1);

        // We don't revert on failed calls to allow batch operations and give users control over error handling
    }

    ///////////////////////////////////////////////////////////////////
    // Security Critical Operations (called via executeTransaction)
    ///////////////////////////////////////////////////////////////////

    /**
     * @notice Change wallet ownership structure
     * @dev SECURITY CRITICAL: Only callable via executeTransaction with k-of-n signatures
     * @inheritdoc ISaxenismWallet
     */
    function changeOwners(address[] calldata newOwners, uint256 newThreshold) external override {
        require(msg.sender == address(this), "SaxenismWalletLogic: only via executeTransaction");

        // Validate new configuration
        _validateOwnerConfig(newOwners, newThreshold);

        // Store old values for event
        address[] memory oldOwners = _owners;
        uint256 oldThreshold = _threshold;

        // Clear existing owners
        for (uint256 i = 0; i < _owners.length; i++) {
            _isOwner[_owners[i]] = false;
        }

        // Set new owners
        _setOwners(newOwners, newThreshold);

        emit OwnersChanged(oldOwners, newOwners, oldThreshold, newThreshold);
    }

    /**
     * @notice Add/remove trusted delegate for safe DELEGATECALL operations
     * @inheritdoc ISaxenismWallet
     */
    function setTrustedDelegate(address delegate, bool trusted) external override {
        require(msg.sender == address(this), "SaxenismWallet: only via executeTransaction");
        require(delegate != address(0), "SaxenismWallet: invalid delegate");

        _trustedDelegates[delegate] = trusted;
        emit TrustedDelegateChanged(delegate, trusted);
    }

    /**
     * @notice Add/remove address from emergency withdrawal whitelist
     * @inheritdoc ISaxenismWallet
     */
    function setWithdrawalRecipient(address recipient, bool whitelisted) external override {
        require(msg.sender == address(this), "SaxenismWallet: only via executeTransaction");
        require(recipient != address(0), "SaxenismWallet: invalid recipient");

        _withdrawalRecipients[recipient] = whitelisted;
        emit WithdrawalRecipientChanged(recipient, whitelisted);
    }

    /**
     * @notice Upgrade wallet implementation (logic contract)
     * @inheritdoc ISaxenismWallet
     */
    function upgradeImplementation(address newImplementation, string calldata newVersion) external override {
        require(msg.sender == address(this), "SaxenismWallet: only via executeTransaction");
        require(newImplementation != address(0), "SaxenismWallet: invalid implementation");

        // Validate implementation via factory
        require(
            ISaxenismWalletFactory(_factory).isImplementationUsable(newVersion),
            "SaxenismWallet: implementation not usable"
        );

        address oldImplementation = _getImplementation();

        // Perform upgrade - wallet is its own proxy admin
        // Calling upgrade on the proxy.
        (bool ok,) = address(this).call(abi.encodeWithSignature("upgradeTo(address)", newImplementation));
        require(ok, "SaxenismWallet: upgrade failed");

        // Update version
        _version = newVersion;

        emit ImplementationUpgraded(oldImplementation, newImplementation, newVersion);
    }

    /**
     * @notice Emergency withdrawal of all funds to whitelisted address
     * @inheritdoc ISaxenismWallet
     */
    function withdrawAllFunds(address recipient) external override {
        require(msg.sender == address(this), "SaxenismWallet: only via executeTransaction");
        require(_withdrawalRecipients[recipient], "SaxenismWallet: recipient not whitelisted");

        uint256 balance = address(this).balance;
        require(balance > 0, "SaxenismWallet: no funds to withdraw");

        // Transfer all ETH to recipient
        (bool success,) = recipient.call{value: balance}("");
        require(success, "SaxenismWallet: transfer failed");

        emit EmergencyWithdrawal(recipient, balance);

        // TODO: Add token withdrawal logic for ERC20/ERC721/ERC1155 tokens
    }

    /**
     * @notice Cancel a specific nonce for governance conflict resolution
     * @inheritdoc ISaxenismWallet
     */
    function cancelNonce(uint256 nonceToCancel) external override {
        require(msg.sender == address(this), "SaxenismWallet: only via executeTransaction");
        require(nonceToCancel >= _nonce, "SaxenismWallet: cannot cancel past nonce");

        _nonce = nonceToCancel + 1;

        emit NonceCancelled(nonceToCancel, _nonce);
    }

    /////////////////////
    // View Functions
    /////////////////////

    /**
     * @notice Get current wallet owners
     * @inheritdoc ISaxenismWallet
     */
    function getOwners() external view override returns (address[] memory) {
        return _owners;
    }

    /**
     * @notice Get current signature threshold
     * @inheritdoc ISaxenismWallet
     */
    function getThreshold() external view override returns (uint256) {
        return _threshold;
    }

    /**
     * @notice Get current transaction nonce
     * @inheritdoc ISaxenismWallet
     */
    function getNonce() external view override returns (uint256) {
        return _nonce;
    }

    /**
     * @notice Check if address is a trusted delegate
     * @inheritdoc ISaxenismWallet
     */
    function isTrustedDelegate(address delegate) external view override returns (bool) {
        return _trustedDelegates[delegate];
    }

    /**
     * @notice Check if address is whitelisted for emergency withdrawals
     * @inheritdoc ISaxenismWallet
     */
    function isWithdrawalRecipient(address recipient) external view override returns (bool) {
        return _withdrawalRecipients[recipient];
    }

    /**
     * @notice Get current implementation address (logic contract)
     * @inheritdoc ISaxenismWallet
     */
    function getImplementation() external view override returns (address) {
        return _getImplementation();
    }

    /**
     * @notice Get implementation version string
     * @inheritdoc ISaxenismWallet
     */
    function getVersion() external view override returns (string memory) {
        return _version;
    }

    /**
     * @notice Generate EIP-712 transaction hash for signing
     * @inheritdoc ISaxenismWallet
     */
    function getTransactionHash(Transaction calldata transaction) external view override returns (bytes32) {
        return _getTransactionHash(transaction);
    }

    /**
     * @notice Verify if signatures are valid for a transaction
     * @inheritdoc ISaxenismWallet
     */
    function verifySignatures(bytes32 txHash, bytes[] calldata signatures) external view override returns (bool) {
        return _verifySignatures(txHash, signatures);
    }

    /////////////////////////
    // Internal Functions
    /////////////////////////

    /**
     * @notice Internal function to validate owner configuration
     * @param owners Array of owner addresses
     * @param threshold Signature threshold
     */
    function _validateOwnerConfig(address[] calldata owners, uint256 threshold) internal pure {
        require(owners.length > 0, "SaxenismWallet: no owners provided");
        require(owners.length <= MAX_OWNERS, "SaxenismWallet: too many owners");
        require(threshold > 0, "SaxenismWallet: threshold cannot be zero");
        require(threshold <= owners.length, "SaxenismWallet: threshold exceeds owner count");

        // Check for duplicate owners and zero addresses
        for (uint256 i = 0; i < owners.length; i++) {
            require(owners[i] != address(0), "SaxenismWallet: invalid owner address");

            // Check for duplicates
            for (uint256 j = i + 1; j < owners.length; j++) {
                require(owners[i] != owners[j], "SaxenismWallet: duplicate owner");
            }
        }
    }

    /**
     * @notice Internal function to set owners and threshold
     * @param owners Array of owner addresses
     * @param threshold Signature threshold
     */
    function _setOwners(address[] calldata owners, uint256 threshold) internal {
        delete _owners;

        for (uint256 i = 0; i < owners.length; i++) {
            _owners.push(owners[i]);
            _isOwner[owners[i]] = true;
        }

        _threshold = threshold;
    }

    /**
     * @notice Internal function to generate EIP-712 transaction hash
     * @param transaction Transaction struct to hash
     * @return EIP-712 compliant hash
     */
    function _getTransactionHash(Transaction memory transaction) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    TRANSACTION_TYPEHASH,
                    transaction.target,
                    transaction.value,
                    keccak256(transaction.data),
                    transaction.operation,
                    transaction.nonce,
                    transaction.chainId,
                    transaction.verifyingContract
                )
            )
        );
    }

    /**
     * @notice Internal function to verify k-of-n signatures
     * @param txHash EIP-712 transaction hash
     * @param signatures Array of signatures to verify
     * @return True if signatures meet threshold requirement
     */
    function _verifySignatures(bytes32 txHash, bytes[] calldata signatures) internal view returns (bool) {
        require(signatures.length >= _threshold, "SaxenismWallet: insufficient signatures");
        require(signatures.length <= _owners.length, "SaxenismWallet: too many signatures");

        address lastOwner = address(0);
        uint256 validSignatures = 0;

        for (uint256 i = 0; i < signatures.length; i++) {
            address recoveredOwner = txHash.recover(signatures[i]);

            // Check if recovered address is an owner
            if (!_isOwner[recoveredOwner]) {
                continue;
            }

            // Ensure signatures are in ascending order (prevents duplicates)
            require(recoveredOwner > lastOwner, "SaxenismWallet: invalid signature order");
            lastOwner = recoveredOwner;

            validSignatures++;
        }

        return validSignatures >= _threshold;
    }

    /**
     * @notice Internal function to get current implementation address
     * @return Implementation address from proxy storage
     */
    function _getImplementation() internal view returns (address) {
        // Implementation address is stored in EIP-1967 storage slot
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address impl;
        assembly {
            impl := sload(slot)
        }
        return impl;
    }

    // Accept ETH deposits
    /**
     * @notice Receive function to accept ETH deposits
     */
    receive() external payable {}

    // Storage gap for future upgrades
    uint256[50] private __gap;
}
