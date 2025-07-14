// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface ISaxenismWalletFactory {
    ////////////
    // Structs
    ////////////

    struct ImplementationInfo {
        address implementation;
        bool isActive;
        bool isPaused;
        bool isDeprecated;
        uint256 deployedAt;
        uint256 pausedAt;
        uint256 deprecatedAt;
    }

    struct WalletConfig {
        address[] owners;
        uint256 threshold;
        string version;
        bytes32 salt;
    }

    ////////////////////////////////
    // Wallet Deployment Functions
    ////////////////////////////////

    function createWallet(
        address[] calldata owners,
        uint256 threshold,
        string calldata version,
        bytes32 salt
    ) external returns (address wallet);

    //////////////////////////
    // Privileged Functions
    //////////////////////////

    function addImplementation(
        string calldata version,
        address implementation,
        bool setAsLatest
    ) external;

    function pauseImplementation(
        string calldata version, 
        string calldata reason
    ) external;

    // UNLIKELY to be used often, since if an implementation contract is "PAUSED", then probably
    // it was because of a bug and in that case, the wallets will simply start pointing towards the
    // new implementation when it is deployed. Hence there is no need for an unpause, but keeping it here for completeness.
    // Edge cases where it could be useful: False alarms, operational issues, external dependency issues
    function unpauseImplementation(string calldata version) external;

    function removeImplementation(string calldata version, string calldata reason) external;

    function deprecateImplementation(string calldata version, string calldata reason) external;

    function setLatestVersion(string calldata newLatestVersion) external;

    function transferPrivilegedAdmin(address newAdmin) external;

    function acceptPrivilegedAdmin() external;

    //////////////////
    // View Functions
    //////////////////

    function getPrivilegedAdmin() external view returns (address);

    function getPendingPrivilegedAdmin() external view returns (address);

    function getImplementationInfo(string calldata version) external view returns (ImplementationInfo memory info);

    function getImplementation(string calldata version) external view returns (address implementation);

    function isImplementationActive(string calldata version) external view returns (bool);
    
    function isImplementationUsable(string calldata version) external view returns (bool);
    
    function getLatestVersion() external view returns (string memory);
    
    function getAllVersions() external view returns (string[] memory);
    
    function getActiveVersions() external view returns (string[] memory);
    
    function isWalletDeployed(address wallet) external view returns (bool);
    
    function getWalletCount() external view returns (uint256);
    
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
    event ImplementationAdded(
        string indexed version,
        address indexed implementation,
        address indexed deployer
    );
    
    /**
     * @notice Emitted when an implementation is emergency paused
     * @param version Version string that was paused
     * @param implementation Address of the paused logic contract
     * @param admin Address that triggered the pause
     * @param reason Human-readable reason for pause
     */
    event ImplementationPaused(
        string indexed version,
        address indexed implementation,
        address indexed admin,
        string reason
    );
    
    /**
     * @notice Emitted when a paused implementation is unpaused
     * @param version Version string that was unpaused
     * @param implementation Address of the unpaused logic contract
     * @param admin Address that triggered the unpause
     */
    event ImplementationUnpaused(
        string indexed version,
        address indexed implementation,
        address indexed admin
    );
    
    /**
     * @notice Emitted when an implementation is removed from registry
     * @param version Version string that was removed
     * @param implementation Address of the removed logic contract
     * @param admin Address that triggered the removal
     * @param reason Human-readable reason for removal
     */
    event ImplementationRemoved(
        string indexed version,
        address indexed implementation,
        address indexed admin,
        string reason
    );
    
    /**
     * @notice Emitted when an implementation is marked as deprecated
     * @param version Version string that was deprecated
     * @param implementation Address of the deprecated logic contract
     * @param admin Address that triggered the deprecation
     * @param reason Human-readable reason for deprecation
     */
    event ImplementationDeprecated(
        string indexed version,
        address indexed implementation,
        address indexed admin,
        string reason
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
    event LatestVersionUpdated(
        string oldVersion,
        string indexed newVersion,
        address indexed admin
    );
}
