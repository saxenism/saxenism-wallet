# Saxenism Wallet: Enterprise-Grade Multisig Protocol

> *"Not just another multisig. This is a security-first governance primitive for serious teams."*

Saxenism Wallet is a highly secure, CREATE2-deployed, proxy-upgradeable multisig system that gives each wallet **complete autonomy** over its governance, upgradability, and security posture. This wallet treats security and governance as first-class citizens.

Every wallet is a self-governing smart contract with k-of-n EIP-712 signed execution. **This is not a toy wallet.**

---

## Design Highlights

### Self-Administration

```solidity
// Factory deploys proxy with itself as admin
new TransparentUpgradeableProxy(implementation, address(this), initData);

// During initialize(), wallet becomes its own admin
address(this).call(abi.encodeWithSignature("changeAdmin(address)", address(this)));
```

**Result**: Every wallet controls its own upgrade timeline. No forced updates, no protocol-level coercion.

**Technical Note**: 
1. Uses EIP-1967 standard storage slots to prevent storage collisions between proxy state and implementation state.
2. Admin call filtering in the TPP contracts used prevents function collision.

### Security Building Blocks

| Security Layer | Implementation | Attack Prevention |
|---|---|---|
| **Signature Verification** | EIP-712 + ecrecover | Replay attacks, signature malleability |
| **External Calls** | ExcessivelySafeCall | Returnbomb attacks, gas griefing |
| **External Delegatecalls** | Whitelisted Addresses Only | Untrusted delegate calls prevented |
| **Cross-Chain** | Explicit chainId + verifyingContract | Cross-chain replay attacks |
| **Version Control** | Factory deprecation system | Dangerous downgrade prevented |

### Layered-Solutions for Governance

**Democratic Conflict Resolution**: When multiple valid transactions compete for the same nonce:

```solidity
// Two factions sign competing proposals for nonce 7
// Cross-faction coalition signs cancelNonce(7) 
// Both proposals invalidated → Clean renegotiation at nonce 8
```

**Benefits**: Privacy-preserving rejection, democratic process, no off-chain coordination complexity.

**Fully autonomous upgrades**: Wallets upgrade via k-of-n agreement and only when they want to and only to the versions they want to. No broad protocol-level broad directives that HAVE to be followed (apart from critical hacks being discovered in the implementation contract)

### CREATE2 Deterministic Deployment

- **Same wallet address** across all chains
- **Cross-chain governance consistency** 
- **Predictable address calculation** for planning

---

## Architecture

```
SaxenismWalletFactory.sol
├─ Deploys TransparentUpgradeableProxy instances
├─ Manages implementation lifecycle (pause/deprecate/remove)  
├─ CREATE2 deployment for cross-chain consistency
└─ Emergency response capabilities

SaxenismWalletLogic.sol
├─ Implementation contract (business logic)
├─ Self-administration through two-phase init
├─ Unified security model via executeTransaction
├─ Governance primitives (cancelNonce, emergency exit)
└─ Advanced security features (trusted delegates, etc.)

TransparentUpgradeableProxy (per wallet)
├─ User's actual wallet address and storage
├─ Delegatecalls to SaxenismWalletLogic
├─ Self-administered (wallet = proxy admin)
└─ Battle-tested OpenZeppelin proxy security
```

### The Security Model

**Single Entry Point**: All security-critical operations flow through `executeTransaction`:

```
┌─ Regular Transactions ─┐
├─ Change Ownership ─────┤
├─ Emergency Withdrawals ┤ ──► executeTransaction() ──► k-of-n Validation
├─ Upgrade Implementation┤
├─ Trusted Delegate Mgmt ┤
└─ Governance Actions ───┘
```

---

## Signature Verification

Battle-tested ECDSA with comprehensive validation:

```solidity
// EIP-712 structured signing prevents malleability
struct Transaction {
    address target;
    uint256 value; 
    bytes data;
    Operation operation;
    uint256 nonce;
    uint256 chainId;           // Explicit cross-chain protection
    address verifyingContract; // Contract-specific binding
}

// Signature validation with duplicate prevention
require(signatures.length >= threshold);
require(signatures.length <= owners.length);
require(recovered > lastOwner);  // Enforces ascending order → prevents duplicates
require(_isOwner[recovered]);    // Must be current owner
```

**Why ECDSA**: Most battle-tested signature scheme in production. Current implementation is gas-intensive (each signature requires individual ecrecover), so future roadmap includes **signature aggregation schemes**:

- **BLS (Boneh-Lynn-Shacham)**: Single aggregated signature for all k signers
- **Schnorr signatures**: Linear signature aggregation with lower gas costs
- **Trade-off**: Current ECDSA prioritizes battle-tested security over gas efficiency

**Wallet Compatibility Caveat**: ECDSA will likely remain the default signature scheme due to widespread wallet compatibility (e.g., MetaMask cannot generate BLS signatures). Alternative schemes would require specialized tooling and may limit user adoption.

**Long Term Solutions**: As quantum computing matures, we must look at quantum safe, lattice-cryptography based signature schemes that are already in use in blockchains. For example, Algorand uses FALCON.

---

## Emergency & Sovereignty Features

| Feature | Purpose | Security Model |
|---|---|---|
| `withdrawAllFunds()` | Exit mechanism for governance disagreements | Requires k-of-n + whitelisted recipient |
| `cancelNonce()` | Democratic conflict resolution | Requires k-of-n signatures |
| `upgradeImplementation()` | Autonomous upgrade decisions | Requires k-of-n + factory validation |
| `setTrustedDelegate()` | Delegatecall safety management | Requires k-of-n signatures |

### User Sovereignty Mechanisms

**Emergency Exit Rights**: Preserves user autonomy when disagreeing with:
- Protocol governance decisions
- Security policy changes  
- Ecosystem direction

**Autonomous Upgrade Decisions**: Each wallet decides whether/when to upgrade independently.

---

## OpSec Framework: Monitoring

### Proactive Threat Detection

**High-Value Target Monitoring**:

```
Track Top 20 Wallets by USD Value →
Monitor for Rapid/Large Balance Decreases →
Early Warning System for Protocol Exploits →
Emergency Response Activation
```

**Rationale**: Attackers target high-value wallets first. Early detection provides critical head-start in response time for an upcoming hack.

### Monitoring Architecture Redundancy

```
Primary Monitor (OZ Defender/Custom)
├─ Platform-optimized alerts
├─ Real-time response integration
└─ High-fidelity monitoring

Backup Monitor (Different Tech Stack)
├─ Shared core rule set  
├─ Independent alerting channels
└─ Platform limitation resilience (e.g., OZ Defender can't detect L2 function calls)
```

### Monitor Trusted Delegatecall Addresses

For high-value wallets and wallets that want to, we can setup monitoring for their trusted "delegatecall" addresses to ensure that it does not have any dangerous combination of `delegatecall` and `selfdestruct` as that can leave the wallet unusable.

### Multi-Layer Incident Response

| Response Level | Trigger | Action | Authority |
|---|---|---|---|
| **Level 1** | Vulnerability discovered | Pause implementation | Privileged admin |
| **Level 2** | Breaking changes identified | Deprecate version | Privileged admin |
| **Level 3** | Severe compromise confirmed | Remove from registry | Privileged admin |
| **Level 4** | User disagreement | withdrawAllFunds | Individual wallet (k-of-n) |

### Privileged Admin Centralization Risk

**Risk**: Single privileged admin could abuse implementation lifecycle controls.

**Mitigation**: The privileged admin address is itself a **multisig wallet governed by protocol-level governance**. This ensures:
- No single individual controls protocol-level decisions
- Implementation changes require consensus from protocol governance
- Emergency response capability without sacrificing decentralization
- Clear separation between protocol governance and individual wallet autonomy

---

## Technical DRI Framework

**Every protocol upgrade requires:**

1. **DRI Assignment**: Senior engineer owns upgrade end-to-end
2. **Monitoring Gap Analysis**: Review existing monitoring rules
3. **Invariant Evolution**: Update protocol invariants for new functionality
4. **Dual Monitor Updates**: Update both primary and backup systems
5. **Formal Verification**: Halmos integration for mathematical proofs

**Invariant Rejig as Foundation**: After every protocol upgrade, the updated invariants serve as the **fundamental basis** for:
- **Core test case generation**: All critical tests derive from invariant definitions
- **Core monitoring rules**: Alert systems validate invariant compliance in real-time
- **Formal verification targets**: Mathematical proofs ensure invariants hold under all conditions

**Example Protocol Invariants**:

```solidity
invariant balanceConsistency: sum(userBalances) <= address(this).balance;
invariant thresholdValid: threshold > 0 && threshold <= owners.length;
invariant nonceProgression: forall tx: nonce[tx] > nonce[previousTx];
```

---

## Security & Quality Standards

### Development Requirements

**Every logic upgrade must:**
- ✅ Follow **Test-Driven Development** (TDD) methodology
- ✅ Include **mutation/fuzz tests** (especially for critical protocol parts)
- ✅ Maintain **100% coverage** 
- ✅ Pass **formal verification** via Halmos invariant testing
- ✅ Preserve **storage layout compatibility** (gap reserved)

### Storage Layout Compatibility

```solidity
contract SaxenismWalletLogic {
    // State variables...
    string private _version;
    
    /**
     * @dev Storage gap for safe upgrades
     * Reduces by number of new variables added in future versions
     */
    uint256[50] private __gap;
}
```

**Storage Compatibility Validation Tools**:
- **`slither-check-upgradeability`**: Automated storage layout collision detection
- **`openzeppelin-foundry-upgrades/Upgrades.sol`**: Foundry integration for upgrade safety validation
- **Manual review**: Storage slot analysis for complex upgrade scenarios

---

## License & Acknowledgments

**UNLICENSED** - This code is provided for **demonstration and educational purposes only**. All rights reserved. Not licensed for production use, modification, or distribution.

**Built on proven foundations:**
- **OpenZeppelin**: Battle-tested upgradeable contract frameworks
- **Nomad Labs**: ExcessivelySafeCall for returnbomb protection  
- **Ethereum Foundation**: EIP-712 and EIP-1967 standards

---

**Author**: [Rahul Saxena](https://x.com/saxenism)
