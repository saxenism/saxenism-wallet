# Testing Documentation

## Testing Priniciples

Paul Razvan Berg's work has been instrumental in shaping my testing philosophy, especially the BTT. Here is a broad overview of how I think about testing:

### High-Level Structure Solution

#### Four Essential Test Categories
1. **Unit Tests** - Single contract functions in isolation
2. **Integration Tests** - Multiple contracts working together (including ERC20 interactions)
3. **Invariant Tests** - Properties that should ALWAYS hold true (most powerful testing type)
4. **Fork Tests** - Testing against real mainnet contracts via Alchemy/Infura

#### Concrete vs Fuzz Distinction
- **Concrete**: Deterministic tests with hardcoded values
- **Fuzz**: Property-based tests with randomized inputs

### The Branching Tree Technique (BTT)

It is a **minimal specification language** using ASCII characters to map out all possible execution paths BEFORE writing Solidity tests.

#### How It Works
1. **Write English specs first** - Define contract state, function parameters, and execution paths in plain English
2. **Use tree hierarchy** - Map out all possible states and conditions using ASCII tree structure
3. **Mirror in Solidity** - Use empty modifiers that match each tree node for clear test structure

#### Example Structure
```
├── when contract is paused
│   └── it should revert with ContractPaused
├── when caller is not owner
│   └── it should revert with Unauthorized  
└── when conditions are valid
    ├── when amount exceeds balance
    │   └── it should revert with InsufficientBalance
    └── when amount is valid
        └── it should transfer successfully
```

### Practical Implementation Tips

#### 1. Use Contract Inheritance
Create base test contracts with shared logic, then inherit from them to avoid code duplication.

#### 2. Treat Contract Names as Describe Blocks
Use descriptive contract names that clearly indicate what you're testing (like `TestTokenTransfer.sol`).

#### 3. Empty Modifiers for Specifications
```solidity
modifier whenNotPaused() { _; }
modifier whenValidAmount() { _; }
modifier whenSufficientBalance() { _; }

function test_Transfer_WhenValidConditions() 
    public 
    whenNotPaused 
    whenValidAmount 
    whenSufficientBalance 
{
    // test implementation
}
```

#### 4. **Invariant Tests Should be the Priority**
They're the most powerful testing framework available - expressions that should hold true no matter what, testing your protocol through hundreds of random call sequences.


## Granular Details

0. Ideally, we should do our development the [TDD way](https://en.wikipedia.org/wiki/Test-driven_development), but that may not always be possible.

1. Hands down, we NEED to have unit tests that cover 100% of the codebase. No line in the codebase should exist that has not been covered by some unit test.
    + This is literally a sanity test and should NOT be skipped
    + This might sound difficult but this is the most straight-forward part of the testing process
    + Use LLMs for the heavy-lifting/grunt work

2. Next, we need to carry out slightly more sophisticated "Integration Tests". In my personal opinion, Integration tests are also sanity checks but mimic the real world scenario a little better.
    + Please, do not spam these tests w/ `vm.mockCall` just to make tests run
    + Spend time and energy coming up with good and realistic dummy values. It IS worth the time.

3. Write tests covering all possible scenarios (states) for important piece of code.
    + Important == Code logic that has THE most impact on the protocol either via loss of funds or loss of reputation
    + For example: 
        + The workflow for when a critical bug is discovered in the implementation contract SHOULD be very thoroughly tested
        + Are all the functions paused? How much time does it take to pause? Should some function have remain unpaused? Are the wallets able to remove their money during that time? Can the upgrade of the implementation contract happen without hiccups during that time and on and on.
        + Another example can be what if a trusted delegate address is malicious. What is the maximum extent of damage it can do? Can something be done to prevent that?

4. Lastly, we should question the base assumptions that our protocol is built on and write invariant tests to try and break them. These invariants if broken would be catastrophic for the protocol. 
    + For example:
        + onlySelfExecutesPrivilegedOps Invariant: All sensitive operations (changeOwners, upgradeImplementation, setTrustedDelegate, withdrawAllFunds, cancelNonce, etc.) must only be callable from within the wallet via executeTransaction.
        + nonceStrictlyIncreases Invariant: Nonce must strictly increase on every executed transaction and must never be reused.
        + thresholdValid Invariant: The signature threshold must always be greater than zero and less than or equal to the number of owners.
        + implementationMustBeValidInFactory: The currently active implementation must be marked usable by the factory.

## Operation Security Testing

1. We also need to simulate certain conditions to check our monitoring rules as in my experience they are often untested.
2. We also need to simulate all kinds of governance attacks on the entities using our wallets and ensure that no matter what, the funds can always be extracted.
3. Basic things such as Fuzzing (in-built Foundry) should be implemented
4. Static analysis via tools like Slither should be integrated in the CI pipeline and resolved before PRs can be merged.
5. For really critical piece of our codebase, mutation testing wouldn't hurt.


