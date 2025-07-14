// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {ISaxenismWalletFactory} from "../interfaces/ISaxenismWalletFactory.sol";
import {ISaxenismWallet} from "../interfaces/ISaxenismWallet.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract SaxenismWalletFactory is ISaxenismWalletFactory, Ownable2Step {
    //////////////////////
    // Factory Storage
    //////////////////////

    // Registry of all implementation versions:
    mapping(string => ImplementationInfo) private _implementations;

    string[] private _allVersions;

    string private _latestVersion;

    address[] private _deployedWallets;

    mapping(address => bool) private _isWalletDeployed;

    //////////////////////
    // Constant(s)
    //////////////////////

    /// @notice Salt prefix for CREATE2 deployment consistency
    bytes32 private constant SALT_PREFIX = keccak256("SaxenismWalletFactory.v1");

    //////////////////////
    // Constructor
    //////////////////////

    constructor(address initialPrivilegedAdmin) Ownable(initialPrivilegedAdmin) {
        require(initialPrivilegedAdmin != address(0), "SaxenismWalletFactor");
    }

    //////////////////////////////////
    // Core Logic (Wallet Creation)
    //////////////////////////////////

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

    function pauseImplementation(string calldata version, string calldata reason) external override onlyOwner {
        require(_implementations[version].implementation != address(0), "SaxenismWalletFactory: version not found");
        require(!_implementations[version].isPaused, "SaxenismWalletFactory: already paused");

        _implementations[version].isPaused = true;
        _implementations[version].pausedAt = block.timestamp;

        emit ImplementationPaused(version, _implementations[version].implementation, msg.sender, reason);
    }

    function unpauseImplementation(string calldata version) external override onlyOwner {
        require(_implementations[version].implementation != address(0), "SaxenismWalletFactory: version not found");
        require(_implementations[version].isPaused, "SaxenismWalletFactory: not paused");

        _implementations[version].isPaused = false;
        _implementations[version].pausedAt = 0;

        emit ImplementationUnpaused(version, _implementations[version].implementation, msg.sender);
    }

    // If you remove the latest version, then go ahead and call `setLatestVersion` too. Since it will otherwise default to an empty string
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

    function deprecateImplementation(string calldata version, string calldata reason) external override onlyOwner {
        require(_implementations[version].implementation != address(0), "SaxenismWalletFactory: version not found");
        require(!_implementations[version].isDeprecated, "SaxenismWalletFactory: already deprecated");

        _implementations[version].isDeprecated = true;
        _implementations[version].deprecatedAt = block.timestamp;

        emit ImplementationDeprecated(version, _implementations[version].implementation, msg.sender, reason);
    }

    function setLatestVersion(string calldata newLatestVersion) external override onlyOwner {
        require(
            _implementations[newLatestVersion].implementation != address(0), "SaxenismWalletFactory: version not found"
        );
        require(_implementations[newLatestVersion].isActive, "SaxenismWalletFactory: version not active");

        string memory oldLatest = _latestVersion;
        _latestVersion = newLatestVersion;

        emit LatestVersionUpdated(oldLatest, newLatestVersion, msg.sender);
    }

    function transferPrivilegedAdmin(address newAdmin) external override onlyOwner {
        transferOwnership(newAdmin);
    }

    function acceptPrivilegedAdmin() external override {
        acceptOwnership();
    }

    ////////////////////////////////////////////////////
    // View Functions
    ////////////////////////////////////////////////////

    function getPrivilegedAdmin() external view override returns (address) {
        return owner();
    }

    function getPendingPrivilegedAdmin() external view override returns (address) {
        return pendingOwner();
    }

    function getImplementationInfo(string calldata version)
        external
        view
        override
        returns (ImplementationInfo memory)
    {
        return _implementations[version];
    }

    function getImplementation(string calldata version) external view override returns (address) {
        return _implementations[version].implementation;
    }

    function isImplementationActive(string calldata version) external view override returns (bool) {
        return _isImplementationActive(version);
    }

    function isImplementationUsable(string calldata version) external view override returns (bool) {
        return _isImplementationUsable(version);
    }

    function getLatestVersion() external view override returns (string memory) {
        return _latestVersion;
    }

    function getAllVersions() external view override returns (string[] memory) {
        return _allVersions;
    }

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

    function isWalletDeployed(address wallet) external view override returns (bool) {
        return _isWalletDeployed[wallet];
    }

    function getWalletCount() external view override returns (uint256) {
        return _deployedWallets.length;
    }

    function getWalletByIndex(uint256 index) external view override returns (address) {
        require(index < _deployedWallets.length, "SaxenismWalletFactory: index out of bounds");
        return _deployedWallets[index];
    }

    //////////////////////////////////////////////
    // Internal Functions
    //////////////////////////////////////////////

    function _isImplementationActive(string memory version) internal view returns (bool) {
        ImplementationInfo storage info = _implementations[version];
        return info.implementation != address(0) && info.isActive && !info.isPaused;
    }

    // Check if implementation is usable (for upgrades). True if version is active and not deprecated
    function _isImplementationUsable(string memory version) internal view returns (bool) {
        ImplementationInfo storage info = _implementations[version];
        return info.implementation != address(0) && info.isActive && !info.isPaused && !info.isDeprecated;
    }

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
