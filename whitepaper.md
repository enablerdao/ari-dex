# ARI: Arithmetic of Intents
## Technical Whitepaper v1.0

---

### Abstract

ARI is an intent-based decentralized exchange protocol where users express *what* they want to trade, and a competitive solver network determines *how* to execute it optimally. By separating intent declaration from execution, ARI eliminates MEV extraction, reduces slippage, and enables cross-chain atomic swaps — all while maintaining full self-custody.

This paper describes ARI's architecture, mechanism design, cryptographic primitives, and a radically community-aligned tokenomics model that allocates **0% to founders at TGE** and instead earns team allocation through verifiable protocol milestones.

---

## 1. Problem Statement

Current DEX architectures suffer from three structural flaws:

1. **MEV Extraction**: ~$1.4B annually extracted from users via sandwich attacks, frontrunning, and JIT liquidity manipulation.
2. **Fragmented Liquidity**: Users must manually route across pools, chains, and aggregators. Sub-optimal execution is the norm.
3. **Misaligned Incentives**: Protocol tokens reward early insiders, not long-term users. 15-20% founder allocations with short vesting create persistent sell pressure.

## 2. Architecture

### 2.1 Intent Layer

Users submit structured intents specifying:
- Token pair and direction
- Amount and minimum acceptable output
- Deadline and chain constraints
- EIP-712 signature for on-chain verification

Intents are **not** orders. They represent desired outcomes, leaving execution optimization to solvers.

### 2.2 Encrypted Mempool

Submitted intents are encrypted using **AES-256-GCM** with keys distributed via **Shamir's Secret Sharing** (threshold *t* of *n* key holders). This prevents:
- Frontrunning by miners/validators
- Sandwich attacks by searchers
- Information leakage to market makers

Intents are only decrypted at batch execution time.

### 2.3 Solver Network

Solvers compete in a **Dutch auction** to fill intents:

1. Each solver computes optimal routing using Dijkstra multi-hop pathfinding (up to 3 hops)
2. Solutions are scored on: price improvement, gas efficiency, fill rate, and historical reliability
3. The highest-scoring solution wins and executes on-chain via the Settlement contract

Solvers must stake **100,000 $ARI** in the SolverRegistry. Malicious behavior (failed fills, price manipulation) results in slashing.

### 2.4 Matching Engine

ARI uses a hybrid matching engine:

| Order Size | Mechanism | Rationale |
|-----------|-----------|-----------|
| < $10K | CLMM (Concentrated Liquidity) | Minimal price impact |
| $10K - $100K | Split routing (70/30) | Reduce market impact |
| > $100K | Batch auction (250ms epochs) | Uniform clearing price, MEV-resistant |

**CLMM Math**: Q64.96 fixed-point sqrt price representation, compatible with Uniswap V3 tick spacing. Positions are represented as ERC-721 NFTs via the Vault contract.

### 2.5 Settlement

The Settlement contract (`0x536EeDA7...`) verifies:
1. EIP-712 typed data signature matches intent sender
2. Signature is not replayed (nonce tracking)
3. Output amount >= minimum buy amount
4. Deadline has not passed

Settlement uses **SafeERC20** for all token transfers and **reentrancy guards** on state-modifying functions.

### 2.6 Cross-Chain Intents

ARI implements **ERC-7683** for cross-chain settlement:
1. Origin tokens are escrowed in the CrossChainIntent contract
2. Solver fills the destination chain order
3. Escrow releases to solver upon proof of fill
4. If unfilled by deadline, user can cancel and reclaim escrowed tokens

## 3. Cryptographic Primitives

| Primitive | Implementation | Purpose |
|-----------|---------------|---------|
| Intent encryption | AES-256-GCM | Encrypted mempool |
| Key distribution | Shamir SSS (GF(256)) | Threshold decryption |
| Intent signing | EIP-712 + secp256k1 | On-chain verification |
| Signature malleability | s-value lower half check | Replay protection |

**Note**: BLS threshold signatures for committee-based decryption are designed but currently use an HMAC-SHA256 placeholder. Production BLS implementation is planned for Phase 3.

## 4. Smart Contract Architecture

13 contracts deployed on Ethereum Mainnet:

| Contract | Purpose | Key Security Features |
|----------|---------|----------------------|
| Settlement | Intent settlement | EIP-712 verification, nonce tracking, pause/unpause |
| Vault | CLMM + LP NFTs | Reentrancy guard, tick range validation |
| VaultFactory | Minimal proxy factory | EIP-1167 clones, deterministic addresses |
| AriToken | ERC-20 governance | 1B fixed supply, owner-only mint |
| VeARI | Vote escrow | 1-4yr lock, soulbound, linear decay |
| SolverRegistry | Solver staking | 100K minimum, slashing, cooldown |
| ConditionalIntent | Limit/Stop/DCA | Oracle-based price (no user-supplied) |
| PerpetualMarket | 20x leverage perps | Liquidation engine, funding rate |
| CrossChainIntent | ERC-7683 | Escrow, cancel after deadline |
| IntentComposer | Atomic multi-action | Batch execution, all-or-nothing |
| PrivatePool | Whitelisted AMM | Access control, constant product |
| AriPaymaster | ERC-4337 gas | Sponsored transactions |
| SimplePriceOracle | Price feed | Owner-updatable, Chainlink-ready |

All contracts use OpenZeppelin's **SafeERC20** and are verified on Sourcify (exact match).

## 5. Tokenomics: Milestone-Earned Model

### 5.1 Design Philosophy

Traditional tokenomics allocate 15-20% to founders with time-based vesting. This creates:
- Guaranteed dilution regardless of protocol success
- Sell pressure at cliff dates
- Misalignment: team is rewarded for *time*, not *outcomes*

ARI introduces a **Milestone-Earned Allocation (MEA)** model: the team earns tokens *only* when verifiable on-chain milestones are achieved.

### 5.2 Allocation

| Category | % | Amount | Unlock Mechanism |
|----------|---|--------|-----------------|
| **Community & Ecosystem** | 55% | 550M | Progressive release tied to TVL, volume, and user milestones |
| **Protocol Treasury (DAO)** | 20% | 200M | Governance vote required for any spend |
| **Team & Contributors** | 8% | 80M | **Milestone-earned only** (see 5.3) |
| **Early Contributors & Grants** | 7% | 70M | 6-month cliff, 24-month linear vesting |
| **Public Launch** | 10% | 100M | Fair launch, no VC preferential pricing |

**Key differences from typical DeFi tokenomics:**
- **Team: 8% (not 15-20%)** — and earned, not granted
- **No VC allocation** — replaced by public launch at fair price
- **Community majority: 55%** — largest single allocation
- **Public: 10%** — double the typical 5%, no price discount

### 5.3 Milestone-Earned Team Allocation

The team's 8% (80M $ARI) is locked in a smart contract and releases in tranches when on-chain conditions are met:

| Milestone | $ARI Released | Verification |
|-----------|--------------|-------------|
| TVL reaches $10M | 10M (1%) | On-chain TVL oracle |
| 10,000 unique traders | 10M (1%) | Settlement contract event count |
| TVL reaches $100M | 15M (1.5%) | On-chain TVL oracle |
| 5 active solvers with >90% fill rate | 10M (1%) | SolverRegistry state |
| Cross-chain volume > $50M | 10M (1%) | CrossChainIntent settlement events |
| TVL reaches $500M | 15M (1.5%) | On-chain TVL oracle |
| Governance proposal executed by community | 10M (1%) | VeARI governance events |

If milestones are not achieved within 5 years, unearned tokens are **burned** — not returned to the team.

### 5.4 Community Ecosystem Fund (55%)

Released progressively:

| Phase | Allocation | Trigger |
|-------|-----------|---------|
| Genesis Airdrop | 5% (50M) | TGE — to early testnet users, bug reporters, contributors |
| Solver Rewards | 15% (150M) | Per-epoch rewards proportional to fill quality |
| LP Incentives | 15% (150M) | Concentrated liquidity mining with veARI boost |
| Trading Rebates | 10% (100M) | Fee rebates for intent submitters |
| Ecosystem Grants | 10% (100M) | DAO-governed grants for integrations, tools, research |

### 5.5 Value Accrual

ARI uses a **three-pillar** value model that avoids securities classification:

1. **Work Token**: Solvers must stake $ARI to participate — creating buy pressure proportional to protocol demand
2. **Buyback & Make**: Protocol fees (0.05% per swap) fund automatic market buybacks, with purchased $ARI deposited into the ecosystem fund (not burned, creating perpetual incentives)
3. **veARI Governance**: Long-term lockers receive boosted LP rewards (up to 2.5x), governance power, and API access — pure utility, not dividends

### 5.6 Fee Structure

| Fee Type | Rate | Distribution |
|----------|------|-------------|
| Swap fee | 0.05% | 50% buyback, 30% treasury, 20% solver reward |
| Perpetual funding | Variable | To counter-parties |
| Liquidation penalty | 2.5% | 50% liquidator, 50% insurance fund |

### 5.7 Anti-Extraction Safeguards

- **No VC lockup games**: No private rounds with discounted prices
- **Milestone clawback**: Unearned team tokens are burned at year 5
- **Treasury governance**: DAO must approve all treasury spends (7-day timelock)
- **Emission caps**: Ecosystem fund releases are capped at 2% of remaining balance per month

## 6. Security

### 6.1 Smart Contract Security

- All contracts use OpenZeppelin's audited libraries
- EIP-712 signature verification prevents unsigned intent execution
- Reentrancy guards on all state-modifying functions
- SafeERC20 prevents silent transfer failures
- Oracle-based pricing (no user-supplied price parameters)
- Signature malleability protection (s-value in lower half)

### 6.2 Infrastructure Security

- CORS restricted to known origins
- Concurrent request limiting (100 max)
- WebSocket connection limits (1,000 max)
- Input validation on all API endpoints
- HTTPS enforcement in production
- No secret key exposure in logs or responses

### 6.3 Cryptographic Security

- AES-256-GCM for intent encryption (128-bit security level)
- Shamir's Secret Sharing over GF(256) for key distribution
- BLS threshold signatures planned for production (currently HMAC placeholder)

## 7. Comparison with Existing Protocols

| Feature | ARI | CoW Protocol | UniswapX | 1inch Fusion |
|---------|-----|-------------|----------|-------------|
| MEV Protection | Encrypted mempool | Batch auction | Dutch auction | Resolver competition |
| Cross-chain | ERC-7683 native | No | Planned | Limited |
| Team allocation | 8% milestone-earned | ~20% time-vested | N/A (UNI) | ~15% |
| Solver staking | Required (100K $ARI) | Optional | No | No |
| Perpetual futures | Yes (20x) | No | No | No |
| Conditional intents | Limit/Stop/DCA | No | No | Limit only |
| Account abstraction | ERC-4337 native | No | No | No |

## 8. Roadmap

| Phase | Status | Key Deliverables |
|-------|--------|-----------------|
| Phase 1: MVP | **Complete** | 13 mainnet contracts, API server, Swap UI |
| Phase 2: Core Protocol | **Complete** | Solver network, encrypted mempool, batch auction, CLMM |
| Phase 3: Production | In Progress | External audit, multi-chain, Chainlink oracle, BLS |
| Phase 4: Governance | Planned | veARI governance launch, treasury activation, DAO |

## 9. Deployed Contracts (Ethereum Mainnet)

| Contract | Address |
|----------|---------|
| Settlement | `0x536EeDA7d07cF7Af171fBeD8FAe7987a5c63B822` |
| VaultFactory | `0x1d06BEDA9797CB52363302bBf2d768a36b53cd5c` |
| ARI Token | `0x3B15dD6d6E5a58b755C70b72fC6e2757F1062d8C` |
| VeARI | `0x90dA559495bAb9408F8175eB6F489eab48E20d10` |
| SolverRegistry | `0x72eCef8A9321f5BdaF26Db3AB983c15DE61F9C4E` |
| SimplePriceOracle | `0x0eC4094174F3B8fccc23B829B27A42BA28eCF4c4` |
| ConditionalIntent | `0x747ffBF3c30Ac13cf54cb242e70Dcb532c4cBD05` |
| PerpetualMarket | `0x5DE57652E281B94b3f40Eb821DaF3e4924bc1A2d` |
| CrossChainIntent | `0x64d9F15D3d6349A7B3Cc1b8D6B57bF32d8c12c5A` |
| IntentComposer | `0x081887186409851f58e5229D343657ac84F4F283` |
| PrivatePool | `0x429bCCb01e5754132D56fAA75CC08e60A53a0618` |
| AriPaymaster | `0x0c965066f106a94baBCb18db8fC37A5DF4180CAe` |

## 10. Conclusion

ARI represents a new paradigm in decentralized exchange design:

1. **Intent-first**: Users express desired outcomes, not execution instructions
2. **MEV-resistant**: Encrypted mempool + batch auction eliminates extraction
3. **Solver-competitive**: Dutch auction ensures best execution
4. **Community-aligned**: 55% community allocation, 8% milestone-earned team, no VC
5. **Full-stack**: From cryptographic primitives to production-deployed smart contracts

The protocol is live on Ethereum Mainnet with 13 verified contracts, a functional API server, and a modern swap interface — built entirely by AI-accelerated engineering.

---

**Links:**
- Spec: [dex-spec.fly.dev](https://dex-spec.fly.dev)
- App: [ari-dex-api.fly.dev](https://ari-dex-api.fly.dev)
- GitHub: [github.com/enablerdao/ari-dex](https://github.com/enablerdao/ari-dex)
- Contracts: Verified on [Sourcify](https://sourcify.dev)
