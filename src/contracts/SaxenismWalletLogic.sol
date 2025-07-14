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

    address[] private _owners;
    
    mapping(address => bool) private _isOwner;

    uint256 private _threshold;

    uint256 private _nonce;

    mapping(address => bool) private _trustedDelegates;

    mapping(address => bool) private _withdrawalRecipients;

    address private _factory;

    string private _version;

    //////////////////////////////
    // Constants and Immutables
    //////////////////////////////

    bytes32 private constant TRANSACTION_TYPEHASH = keccak256(
        "Transaction(address target, uint256 value, bytes data, uint8 operation,uint256 nonce,uint256 chainId,address verifyingContract)"
    );

    // Kinda arbitrary. No super-specific reason for chosing 50
    uint256 private constant MAX_OWNERS = 50;

    // Gas limit for external calls to prevent griefing
    uint256 private constant EXTERNAL_CALL_GAS_LIMIT = 200_000;

    uint16 private constant MAX_RETURN_COPY = 128; //or whatever size you want


    ////////////////////////////////////////////////////
    // Initialization - Two phase self-administration
    ////////////////////////////////////////////////////

    function initialize(
        address[] calldata owners,
        uint256 threshold,
        string calldata version
    ) external initializer {
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
        (bool success, ) = address(this).call(
            abi.encodeWithSignature("changeAdmin(address)", address(this))
        );
        require(success, "SaxenismWalletLogic: admin transfer failed");

        emit OwnersChanged(new address[](0), owners, 0, threshold);
    }

    ///////////////////////////
    // Core Execution Engine
    ///////////////////////////

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
            (success, returnData) = target.excessivelySafeCall(
                EXTERNAL_CALL_GAS_LIMIT,
                value,
                MAX_RETURN_COPY,
                data
            );
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

    function changeOwners(
        address[] calldata newOwners,
        uint256 newThreshold
    ) external override {
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

    function setTrustedDelegate(address delegate, bool trusted) external override {
        require(msg.sender == address(this), "SaxenismWallet: only via executeTransaction");
        require(delegate != address(0), "SaxenismWallet: invalid delegate");
        
        _trustedDelegates[delegate] = trusted;
        emit TrustedDelegateChanged(delegate, trusted);
    }

    function setWithdrawalRecipient(address recipient, bool whitelisted) external override {
        require(msg.sender == address(this), "SaxenismWallet: only via executeTransaction");
        require(recipient != address(0), "SaxenismWallet: invalid recipient");
        
        _withdrawalRecipients[recipient] = whitelisted;
        emit WithdrawalRecipientChanged(recipient, whitelisted);
    }

    function upgradeImplementation(
        address newImplementation,
        string calldata newVersion
    ) external override {
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
        (bool ok, ) = address(this).call(
            abi.encodeWithSignature("upgradeTo(address)", newImplementation)
        );
        require(ok, "SaxenismWallet: upgrade failed");

        // Update version
        _version = newVersion;
        
        emit ImplementationUpgraded(oldImplementation, newImplementation, newVersion);
    }

    function withdrawAllFunds(address recipient) external override {
        require(msg.sender == address(this), "SaxenismWallet: only via executeTransaction");
        require(_withdrawalRecipients[recipient], "SaxenismWallet: recipient not whitelisted");
        
        uint256 balance = address(this).balance;
        require(balance > 0, "SaxenismWallet: no funds to withdraw");
        
        // Transfer all ETH to recipient
        (bool success, ) = recipient.call{value: balance}("");
        require(success, "SaxenismWallet: transfer failed");
        
        emit EmergencyWithdrawal(recipient, balance);
        
        // TODO: Add token withdrawal logic for ERC20/ERC721/ERC1155 tokens
    }

    function cancelNonce(uint256 nonceToCancel) external override {
        require(msg.sender == address(this), "SaxenismWallet: only via executeTransaction");
        require(nonceToCancel >= _nonce, "SaxenismWallet: cannot cancel past nonce");
        
        _nonce = nonceToCancel + 1;
        
        emit NonceCancelled(nonceToCancel, _nonce);
    }

    /////////////////////
    // View Functions
    /////////////////////

    function getOwners() external view override returns (address[] memory) {
        return _owners;
    }

    function getThreshold() external view override returns (uint256) {
        return _threshold;
    }
    
    function getNonce() external view override returns (uint256) {
        return _nonce;
    }
    
    function isTrustedDelegate(address delegate) external view override returns (bool) {
        return _trustedDelegates[delegate];
    }
    
    function isWithdrawalRecipient(address recipient) external view override returns (bool) {
        return _withdrawalRecipients[recipient];
    }
    
    function getImplementation() external view override returns (address) {
        return _getImplementation();
    }
    
    function getVersion() external view override returns (string memory) {
        return _version;
    }
    
    function getTransactionHash(Transaction calldata transaction) external view override returns (bytes32) {
        return _getTransactionHash(transaction);
    }
    
    function verifySignatures(bytes32 txHash, bytes[] calldata signatures) external view override returns (bool) {
        return _verifySignatures(txHash, signatures);
    }

    /////////////////////////
    // Internal Functions
    /////////////////////////

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

    function _setOwners(address[] calldata owners, uint256 threshold) internal {
        delete _owners;
        
        for (uint256 i = 0; i < owners.length; i++) {
            _owners.push(owners[i]);
            _isOwner[owners[i]] = true;
        }
        
        _threshold = threshold;
    }

    function _getTransactionHash(Transaction memory transaction) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            TRANSACTION_TYPEHASH,
            transaction.target,
            transaction.value,
            keccak256(transaction.data),
            transaction.operation,
            transaction.nonce,
            transaction.chainId,
            transaction.verifyingContract
        )));
    }

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
    receive() external payable {}

    // Storage gap for future upgrades
    uint256[50] private __gap;
}
