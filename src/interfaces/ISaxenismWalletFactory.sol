// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title ISaxenismWalletFactory
 * @notice Protocol-level interface for Saxenism wallet deployment and lifecycle management
 * @dev This interface defines the complete Factory API for:
 *      - Deploying new wallet instances with CREATE2 (cross-chain consistency)
 *      - Managing implementation versions and lifecycle
 *      - Emergency protocol controls (pause/remove implementations)
 *      - Privileged administrative functions
 *
 * Security Design Principles:
 * - Privileged admin controls implementation lifecycle (emergency response)
 * - User autonomy preserved (each wallet chooses upgrade timing)
 * - CREATE2 deployment ensures cross-chain address consistency
 * - Version management enables gradual rollouts and rollbacks
 * - Emergency controls for rapid incident response
 */
interface ISaxenismWalletFactory {
    ////////////
    // Structs
    ////////////

    /**
     * @notice Implementation metadata for version tracking
     * @param implementation Address of the logic contract
     * @param isActive Whether this implementation is currently active/deployable
     * @param isPaused Whether this implementation is emergency paused
     * @param isDeprecated Whether this implementation is deprecated (unsafe for upgrades)
     * @param deployedAt Timestamp when this implementation was added
     * @param pausedAt Timestamp when this implementation was paused (0 if not paused)
     * @param deprecatedAt Timestamp when this implementation was deprecated (0 if not deprecated)
     */
    struct ImplementationInfo {
        address implementation;
        bool isActive;
        bool isPaused;
        bool isDeprecated;
        uint256 deployedAt;
        uint256 pausedAt;
        uint256 deprecatedAt;
    }

    /**
     * @notice Wallet deployment parameters for CREATE2 consistency
     * @param owners Initial owner addresses for the wallet
     * @param threshold Initial signature threshold
     * @param version Implementation version to deploy
     * @param salt Unique salt for CREATE2 address generation
     */
    struct WalletConfig {
        address[] owners;
        uint256 threshold;
        string version;
        bytes32 salt;
    }

    ////////////////////////////////
    // Wallet Deployment Functions
    ////////////////////////////////

    /**
     * @notice Deploy a new Saxenism wallet instance
     * @dev Uses CREATE2 for deterministic addresses across chains.
     *      Deploys a TransparentUpgradeableProxy pointing to the specified implementation.
     *
     * Security validations:
     * - Implementation version must exist and be active (not paused/removed/deprecated)
     * - Owners array must be valid (non-empty, unique, non-zero addresses)
     * - Threshold must be valid (> 0 and <= owners.length)
     * - Salt must generate a currently unused address
     *
     * @param owners Initial owner addresses (must be unique, non-zero)
     * @param threshold Initial signature threshold (must be > 0 and <= owners.length)
     * @param version Implementation version to use (must be active and usable)
     * @param salt Unique salt for CREATE2 deployment
     * @return wallet Address of the deployed wallet proxy
     */
    function createWallet(address[] calldata owners, uint256 threshold, string calldata version, bytes32 salt)
        external
        returns (address wallet);

    //////////////////////////
    // Privileged Functions
    //////////////////////////

    /**
     * @notice Add a new implementation version to the registry
     * @dev PRIVILEGED: Only callable by privileged admin
     *      Enables gradual rollout of new features and bug fixes
     * @param version Human-readable version identifier (e.g., "v1.2.0")
     * @param implementation Address of the logic contract
     * @param setAsLatest Whether to mark this as the latest recommended version
     */
    function addImplementation(string calldata version, address implementation, bool setAsLatest) external;

    /**
     * @notice Emergency pause an implementation version
     * @dev PRIVILEGED: Only callable by privileged admin
     *      Prevents new wallet deployments using this version.
     *      Existing wallets continue to function but should consider upgrading.
     * @param version Version to pause
     * @param reason Human-readable reason for emergency pause
     */
    function pauseImplementation(string calldata version, string calldata reason) external;

    // UNLIKELY to be used often, since if an implementation contract is "PAUSED", then probably
    // it was because of a bug and in that case, the wallets will simply start pointing towards the
    // new implementation when it is deployed. Hence there is no need for an unpause, but keeping it here for completeness.
    // Edge cases where it could be useful: False alarms, operational issues, external dependency issues
    /**
     * @notice Unpause a previously paused implementation
     * @dev PRIVILEGED: Only callable by privileged admin
     * @param version Version to unpause
     */
    function unpauseImplementation(string calldata version) external;

    /**
     * @notice Remove an implementation version from registry
     * @dev PRIVILEGED: Only callable by privileged admin
     *      More severe than pause - completely removes from registry.
     *      Use when implementation is confirmed compromised/dangerous.
     * @param version Version to remove
     * @param reason Human-readable reason for removal
     */
    function removeImplementation(string calldata version, string calldata reason) external;

    /**
     * @notice Mark an implementation version as deprecated (unsafe for upgrades)
     * @dev PRIVILEGED: Only callable by privileged admin
     *      Prevents wallets from upgrading to this version while allowing existing
     *      wallets using this version to continue functioning. Use when version
     *      has known vulnerabilities or breaking changes that make upgrades unsafe.
     * @param version Version to deprecate
     * @param reason Human-readable reason for deprecation
     */
    function deprecateImplementation(string calldata version, string calldata reason) external;

    /**
     * @notice Update the latest recommended implementation version
     * @dev PRIVILEGED: Only callable by privileged admin
     *      Guides new wallet deployments to the most current version
     * @param newLatestVersion Version to mark as latest
     */
    function setLatestVersion(string calldata newLatestVersion) external;

    /**
     * @notice Transfer privileged admin role
     * @dev PRIVILEGED: Only callable by current privileged admin
     *      Uses a two-step process for security (similar to Ownable2Step)
     * @param newAdmin Address of new privileged admin
     */
    function transferPrivilegedAdmin(address newAdmin) external;

    /**
     * @notice Accept privileged admin role transfer
     * @dev Must be called by the pending admin to complete transfer
     */
    function acceptPrivilegedAdmin() external;

    //////////////////
    // View Functions
    //////////////////

    /**
     * @notice Get current privileged admin address
     * @return Address of privileged admin
     */
    function getPrivilegedAdmin() external view returns (address);

    /**
     * @notice Get pending privileged admin address (during transfer)
     * @return Address of pending admin (address(0) if no transfer in progress)
     */
    function getPendingPrivilegedAdmin() external view returns (address);

    /**
     * @notice Get implementation info for a specific version
     * @param version Version string to query
     * @return info Implementation information struct
     */
    function getImplementationInfo(string calldata version) external view returns (ImplementationInfo memory info);

    /**
     * @notice Get implementation address for a specific version
     * @param version Version string to query
     * @return implementation Address of logic contract (address(0) if not found)
     */
    function getImplementation(string calldata version) external view returns (address implementation);

    /**
     * @notice Check if an implementation version is currently active and deployable
     * @dev Checks if version exists, is active, and not paused (for NEW deployments)
     * @param version Version string to check
     * @return True if version exists, is active, and not paused
     */
    function isImplementationActive(string calldata version) external view returns (bool);

    /**
     * @notice Check if an implementation version is safe for wallet upgrades
     * @dev Checks if version exists, is active, not paused, and not deprecated
     *      Use this for validation in wallet upgrade functions to prevent
     *      dangerous downgrades to vulnerable/incompatible versions.
     * @param version Version string to check
     * @return True if version is safe for upgrades (active, not paused, not deprecated)
     */
    function isImplementationUsable(string calldata version) external view returns (bool);

    /**
     * @notice Get the latest recommended implementation version
     * @return Latest version string
     */
    function getLatestVersion() external view returns (string memory);

    /**
     * @notice Get all registered implementation versions
     * @return Array of version strings
     */
    function getAllVersions() external view returns (string[] memory);

    /**
     * @notice Get all active (deployable) implementation versions
     * @return Array of active version strings
     */
    function getActiveVersions() external view returns (string[] memory);

    /**
     * @notice Check if a wallet address was deployed by this factory
     * @param wallet Address to check
     * @return True if wallet was deployed by this factory
     */
    function isWalletDeployed(address wallet) external view returns (bool);

    /**
     * @notice Get total number of wallets deployed by this factory
     * @return Count of deployed wallets
     */
    function getWalletCount() external view returns (uint256);

    /**
     * @notice Get wallet address by deployment index
     * @param index Index of deployment (0 to getWalletCount() - 1)
     * @return Wallet address at the given index
     */
    function getWalletByIndex(uint256 index) external view returns (address);

    ////////////////////////
    // Events
    ////////////////////////

    /**
     * @notice Emitted when a new wallet is deployed
     * @param wallet Address of the deployed wallet proxy
     * @param owners Initial owner addresses
     * @param threshold Initial signature threshold
     * @param version Implementation version used
     * @param salt Salt used for CREATE2 deployment
     * @param implementation Address of logic contract used
     */
    event WalletDeployed(
        address indexed wallet,
        address[] owners,
        uint256 threshold,
        string version,
        bytes32 salt,
        address indexed implementation
    );

    /**
     * @notice Emitted when a new implementation version is added
     * @param version Version string identifier
     * @param implementation Address of the logic contract
     * @param deployer Address that added this implementation
     */
    event ImplementationAdded(string indexed version, address indexed implementation, address indexed deployer);

    /**
     * @notice Emitted when an implementation is emergency paused
     * @param version Version string that was paused
     * @param implementation Address of the paused logic contract
     * @param admin Address that triggered the pause
     * @param reason Human-readable reason for pause
     */
    event ImplementationPaused(
        string indexed version, address indexed implementation, address indexed admin, string reason
    );

    /**
     * @notice Emitted when a paused implementation is unpaused
     * @param version Version string that was unpaused
     * @param implementation Address of the unpaused logic contract
     * @param admin Address that triggered the unpause
     */
    event ImplementationUnpaused(string indexed version, address indexed implementation, address indexed admin);

    /**
     * @notice Emitted when an implementation is removed from registry
     * @param version Version string that was removed
     * @param implementation Address of the removed logic contract
     * @param admin Address that triggered the removal
     * @param reason Human-readable reason for removal
     */
    event ImplementationRemoved(
        string indexed version, address indexed implementation, address indexed admin, string reason
    );

    /**
     * @notice Emitted when an implementation is marked as deprecated
     * @param version Version string that was deprecated
     * @param implementation Address of the deprecated logic contract
     * @param admin Address that triggered the deprecation
     * @param reason Human-readable reason for deprecation
     */
    event ImplementationDeprecated(
        string indexed version, address indexed implementation, address indexed admin, string reason
    );

    /**
     * @notice Emitted when privileged admin address changes
     * @param oldAdmin Previous admin address
     * @param newAdmin New admin address
     */
    event PrivilegedAdminChanged(address indexed oldAdmin, address indexed newAdmin);

    /**
     * @notice Emitted when the latest recommended version changes
     * @param oldVersion Previous latest version
     * @param newVersion New latest version
     * @param admin Address that updated the version
     */
    event LatestVersionUpdated(string oldVersion, string indexed newVersion, address indexed admin);
}
