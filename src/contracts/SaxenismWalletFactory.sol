// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {ISaxenismWalletFactory} from "../interfaces/ISaxenismWalletFactory.sol";
import {ISaxenismWallet} from "../interfaces/ISaxenismWallet.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title SaxenismWalletFactory
 * @notice Protocol-level factory for deploying and managing Saxenism multisig wallets
 * @dev Implements enterprise-grade wallet deployment with:
 *      - CREATE2 deterministic addresses for cross-chain consistency
 *      - Self-administering proxies (wallet controls its own upgrades)
 *      - Versioned implementation management with lifecycle controls
 *      - Emergency response capabilities (pause/deprecate/remove)
 *      - Privileged admin controls with 2-step transfer security
 *
 * Standard Self-Administration Architecture:
 * Each wallet is deployed as a TransparentUpgradeableProxy using a simple two-phase approach:
 * 1. Factory deploys proxy with itself as initial admin
 * 2. Wallet's initialize() function transfers admin to wallet itself (address(this))
 * 3. All future upgrades flow through wallet's executeTransaction() (k-of-n governance)
 *
 * This achieves true user sovereignty through proven, boring patterns.
 *
 * @author saxenism
 */
contract SaxenismWalletFactory is ISaxenismWalletFactory, Ownable2Step {
    //////////////////////
    // Factory Storage
    //////////////////////

    /// @notice Registry of all implementation versions
    mapping(string => ImplementationInfo) private _implementations;

    /// @notice Array of all registered version strings (for enumeration)
    string[] private _allVersions;

    /// @notice Current latest recommended version
    string private _latestVersion;

    /// @notice Array of all deployed wallet addresses
    address[] private _deployedWallets;

    /// @notice Mapping to check if address was deployed by this factory
    mapping(address => bool) private _isWalletDeployed;

    //////////////////////
    // Constant(s)
    //////////////////////

    /// @notice Salt prefix for CREATE2 deployment consistency
    bytes32 private constant SALT_PREFIX = keccak256("SaxenismWalletFactory.v1");

    //////////////////////
    // Constructor
    //////////////////////

    /**
     * @notice Initialize the factory with privileged admin
     * @param initialPrivilegedAdmin Address of the initial privileged admin
     */
    constructor(address initialPrivilegedAdmin) Ownable(initialPrivilegedAdmin) {
        require(initialPrivilegedAdmin != address(0), "SaxenismWalletFactor");
    }

    //////////////////////////////////
    // Core Logic (Wallet Creation)
    //////////////////////////////////

    /**
     * @notice Deploy a new Saxenism wallet instance with two-phase self-administration
     * @dev Simple and secure approach using standard proxy patterns:
     *
     *      1. Deploy TransparentUpgradeableProxy with factory as initial admin
     *      2. During initialize(), wallet calls changeAdmin(address(this)) to become self-administered
     *      3. All future upgrades flow through wallet's executeTransaction (k-of-n governance)
     *
     * @inheritdoc ISaxenismWalletFactory
     */
    function createWallet(address[] calldata owners, uint256 threshold, string calldata version, bytes32 salt)
        external
        override
        returns (address wallet)
    {
        require(_isImplementationUsable(version), "SaxenismWalletFactory: implementation not usable");
        _validateWalletConfig(owners, threshold);

        address implementation = _implementations[version].implementation;
        bytes32 create2Salt = keccak256(abi.encodePacked(SALT_PREFIX, salt));

        // The initialize function will handle admin transfer to achieve self-administration
        bytes memory initData =
            abi.encodeWithSignature("initialize(address[],uint256,string)", owners, threshold, version);

        // Deploy proxy with factory as initial admin (standard approach)
        // The wallet's initialize() function will transfer admin to itself
        wallet = address(
            new TransparentUpgradeableProxy{salt: create2Salt}(
                implementation,
                address(this), // Factory starts as admin for clean initialization
                initData
            )
        );

        // Record deployment
        _deployedWallets.push(wallet);
        _isWalletDeployed[wallet] = true;

        emit WalletDeployed(wallet, owners, threshold, version, salt, implementation);
    }

    ////////////////////////////////////////////////////
    // Implementationn Lifecycle (Privileged Functions)
    ////////////////////////////////////////////////////

    /**
     * @notice Add a new implementation version to the registry
     * @inheritdoc ISaxenismWalletFactory
     */
    function addImplementation(string calldata version, address implementation, bool setAsLatest)
        external
        override
        onlyOwner
    {
        require(implementation != address(0), "SaxenismWalletFactory: invalid implementation");
        require(bytes(version).length > 0, "SaxenismWalletFactory: empty version");
        require(_implementations[version].implementation == address(0), "SaxenismWalletFactory: version already exists");

        // Add to registry
        _implementations[version] = ImplementationInfo({
            implementation: implementation,
            isActive: true,
            isPaused: false,
            isDeprecated: false,
            deployedAt: block.timestamp,
            pausedAt: 0,
            deprecatedAt: 0
        });

        // Add to version array
        _allVersions.push(version);

        // Set as latest if requested
        if (setAsLatest) {
            _latestVersion = version;
        }

        emit ImplementationAdded(version, implementation, msg.sender);
    }

    /**
     * @notice Emergency pause an implementation version
     * @inheritdoc ISaxenismWalletFactory
     */
    function pauseImplementation(string calldata version, string calldata reason) external override onlyOwner {
        require(_implementations[version].implementation != address(0), "SaxenismWalletFactory: version not found");
        require(!_implementations[version].isPaused, "SaxenismWalletFactory: already paused");

        _implementations[version].isPaused = true;
        _implementations[version].pausedAt = block.timestamp;

        emit ImplementationPaused(version, _implementations[version].implementation, msg.sender, reason);
    }

    /**
     * @notice Unpause a previously paused implementation
     * @dev UNLIKELY to be used often, since if an implementation contract is "PAUSED", then probably
     *      it was because of a bug and in that case, the wallets will simply start pointing towards the
     *      new implementation when it is deployed. Hence there is no need for an unpause, but keeping it here for completeness.
     * @inheritdoc ISaxenismWalletFactory
     */
    function unpauseImplementation(string calldata version) external override onlyOwner {
        require(_implementations[version].implementation != address(0), "SaxenismWalletFactory: version not found");
        require(_implementations[version].isPaused, "SaxenismWalletFactory: not paused");

        _implementations[version].isPaused = false;
        _implementations[version].pausedAt = 0;

        emit ImplementationUnpaused(version, _implementations[version].implementation, msg.sender);
    }

    // If you remove the latest version, then go ahead and call `setLatestVersion` too. Since it will otherwise default to an empty string
    /**
     * @notice Remove an implementation version from registry
     * @inheritdoc ISaxenismWalletFactory
     */
    function removeImplementation(string calldata version, string calldata reason) external override onlyOwner {
        require(_implementations[version].implementation != address(0), "SaxenismWalletFactory: version not found");

        address implementation = _implementations[version].implementation;

        // Remove from registry
        delete _implementations[version];

        // Remove from version array
        _removeFromVersionArray(version);

        // Clear latest version if this was it
        if (keccak256(bytes(_latestVersion)) == keccak256(bytes(version))) {
            _latestVersion = "";
        }

        emit ImplementationRemoved(version, implementation, msg.sender, reason);
    }

    /**
     * @notice Mark an implementation version as deprecated (unsafe for upgrades)
     * @inheritdoc ISaxenismWalletFactory
     */
    function deprecateImplementation(string calldata version, string calldata reason) external override onlyOwner {
        require(_implementations[version].implementation != address(0), "SaxenismWalletFactory: version not found");
        require(!_implementations[version].isDeprecated, "SaxenismWalletFactory: already deprecated");

        _implementations[version].isDeprecated = true;
        _implementations[version].deprecatedAt = block.timestamp;

        emit ImplementationDeprecated(version, _implementations[version].implementation, msg.sender, reason);
    }

    /**
     * @notice Update the latest recommended implementation version
     * @inheritdoc ISaxenismWalletFactory
     */
    function setLatestVersion(string calldata newLatestVersion) external override onlyOwner {
        require(
            _implementations[newLatestVersion].implementation != address(0), "SaxenismWalletFactory: version not found"
        );
        require(_implementations[newLatestVersion].isActive, "SaxenismWalletFactory: version not active");

        string memory oldLatest = _latestVersion;
        _latestVersion = newLatestVersion;

        emit LatestVersionUpdated(oldLatest, newLatestVersion, msg.sender);
    }

    /**
     * @notice Transfer privileged admin role
     * @inheritdoc ISaxenismWalletFactory
     */
    function transferPrivilegedAdmin(address newAdmin) external override onlyOwner {
        transferOwnership(newAdmin);
    }

    /**
     * @notice Accept privileged admin role transfer
     * @inheritdoc ISaxenismWalletFactory
     */
    function acceptPrivilegedAdmin() external override {
        acceptOwnership();
    }

    ////////////////////////////////////////////////////
    // View Functions
    ////////////////////////////////////////////////////

    /**
     * @notice Get current privileged admin address
     * @inheritdoc ISaxenismWalletFactory
     */
    function getPrivilegedAdmin() external view override returns (address) {
        return owner();
    }

    /**
     * @notice Get pending privileged admin address
     * @inheritdoc ISaxenismWalletFactory
     */
    function getPendingPrivilegedAdmin() external view override returns (address) {
        return pendingOwner();
    }

    /**
     * @notice Get implementation info for a specific version
     * @inheritdoc ISaxenismWalletFactory
     */
    function getImplementationInfo(string calldata version)
        external
        view
        override
        returns (ImplementationInfo memory)
    {
        return _implementations[version];
    }

    /**
     * @notice Get implementation address for a specific version
     * @inheritdoc ISaxenismWalletFactory
     */
    function getImplementation(string calldata version) external view override returns (address) {
        return _implementations[version].implementation;
    }

    /**
     * @notice Check if an implementation version is currently active and deployable
     * @inheritdoc ISaxenismWalletFactory
     */
    function isImplementationActive(string calldata version) external view override returns (bool) {
        return _isImplementationActive(version);
    }

    /**
     * @notice Check if an implementation version is safe for wallet upgrades
     * @inheritdoc ISaxenismWalletFactory
     */
    function isImplementationUsable(string calldata version) external view override returns (bool) {
        return _isImplementationUsable(version);
    }

    /**
     * @notice Get the latest recommended implementation version
     * @inheritdoc ISaxenismWalletFactory
     */
    function getLatestVersion() external view override returns (string memory) {
        return _latestVersion;
    }

    /**
     * @notice Get all registered implementation versions
     * @inheritdoc ISaxenismWalletFactory
     */
    function getAllVersions() external view override returns (string[] memory) {
        return _allVersions;
    }

    /**
     * @notice Get all active implementation versions
     * @inheritdoc ISaxenismWalletFactory
     */
    function getActiveVersions() external view override returns (string[] memory) {
        uint256 activeCount = 0;

        // Count active versions
        for (uint256 i = 0; i < _allVersions.length; i++) {
            if (_isImplementationActive(_allVersions[i])) {
                activeCount++;
            }
        }

        // Build active versions array
        string[] memory activeVersions = new string[](activeCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < _allVersions.length; i++) {
            if (_isImplementationActive(_allVersions[i])) {
                activeVersions[currentIndex] = _allVersions[i];
                currentIndex++;
            }
        }

        return activeVersions;
    }

    /**
     * @notice Check if a wallet address was deployed by this factory
     * @inheritdoc ISaxenismWalletFactory
     */
    function isWalletDeployed(address wallet) external view override returns (bool) {
        return _isWalletDeployed[wallet];
    }

    /**
     * @notice Get total number of wallets deployed by this factory
     * @inheritdoc ISaxenismWalletFactory
     */
    function getWalletCount() external view override returns (uint256) {
        return _deployedWallets.length;
    }

    /**
     * @notice Get wallet address by deployment index
     * @inheritdoc ISaxenismWalletFactory
     */
    function getWalletByIndex(uint256 index) external view override returns (address) {
        require(index < _deployedWallets.length, "SaxenismWalletFactory: index out of bounds");
        return _deployedWallets[index];
    }

    ////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////

    /**
     * @notice Internal function to check if implementation is active (for new deployments)
     * @param version Version string to check
     * @return True if version exists, is active, and not paused
     */
    function _isImplementationActive(string memory version) internal view returns (bool) {
        ImplementationInfo storage info = _implementations[version];
        return info.implementation != address(0) && info.isActive && !info.isPaused;
    }

    /**
     * @notice Internal function to check if implementation is usable (for upgrades)
     * @param version Version string to check
     * @return True if version is active and not deprecated
     */
    function _isImplementationUsable(string memory version) internal view returns (bool) {
        ImplementationInfo storage info = _implementations[version];
        return info.implementation != address(0) && info.isActive && !info.isPaused && !info.isDeprecated;
    }

    /**
     * @notice Validate wallet configuration parameters
     * @param owners Array of owner addresses
     * @param threshold Signature threshold
     */
    function _validateWalletConfig(address[] calldata owners, uint256 threshold) internal pure {
        require(owners.length > 0, "SaxenismWalletFactory: no owners provided");
        require(threshold > 0, "SaxenismWalletFactory: threshold cannot be zero");
        require(threshold <= owners.length, "SaxenismWalletFactory: threshold exceeds owner count");

        // Check for duplicate owners and zero addresses
        for (uint256 i = 0; i < owners.length; i++) {
            require(owners[i] != address(0), "SaxenismWalletFactory: invalid owner address");

            // Check for duplicates
            for (uint256 j = i + 1; j < owners.length; j++) {
                require(owners[i] != owners[j], "SaxenismWalletFactory: duplicate owner");
            }
        }
    }

    /**
     * @notice Remove a version from the versions array
     * @param version Version string to remove
     */
    function _removeFromVersionArray(string memory version) internal {
        for (uint256 i = 0; i < _allVersions.length; i++) {
            if (keccak256(bytes(_allVersions[i])) == keccak256(bytes(version))) {
                _allVersions[i] = _allVersions[_allVersions.length - 1];
                _allVersions.pop();
                break;
            }
        }
    }
}
