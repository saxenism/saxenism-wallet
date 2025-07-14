// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface ISaxenismWallet {
    
    /**
        @notice Operation type for transaction execution
        @dev CALL: regular contract interaction & DELEGATECALL: proxy-pattern execution
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
    ) external returns(bool success, bytes memory returnData);

    //////////////////////////////////
    // Security Critical Operations
    //////////////////////////////////

    // All security critical operations are internal and can be called only via `executeTransaction`

    

    function changeOwners(address[] calldata newOwners, uint256 newThreshold) external;

    function setTrustedDelegate(address delegate, bool trusted) external;

    function setWithdrawalRecipient(address recipient, bool whitelisted) external;

    function upgradeImplementation(address newImplementation, string calldata version) external;

    function withdrawAll(address recipient) external;

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

}
