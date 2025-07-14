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
    // Priviliged Functions
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

    function transferPriviligedAdmin(address newAdmin) external;

    function acceptPriviligedAdmin() external;

    //////////////////
    // View Functions
    //////////////////

    function getPriviligedAdmin() external view returns (address);

    function getPendingPriviligedAdmin() external view returns (address);

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
}
