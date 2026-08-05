# NFT Minting Platform, Smart Contract

A gas-optimized ERC-721A minting contract: merkle allowlist, on-chain royalties, a reveal mechanism, and reentrancy protection, deployed and verified live on Sepolia.

Part of a larger system, see [`nft-infra`](https://github.com/sivajisj/nft-infra) for the full architecture (indexer, subgraph, frontend).

**Deployed contract:** [`0x1D24FE1860F4E670aFd65C1B93118A4B4F5c0f54`](https://sepolia.etherscan.io/address/0x1d24fe1860f4e670afd65c1b93118a4b4f5c0f54) · Sepolia · verified source

---

## What's actually in here

- **ERC-721A** batch minting (chiru-labs), one storage write per batch instead of per token
- **Merkle allowlist** minting, single 32-byte root on-chain regardless of allowlist size
- **ERC-2981 royalties**, 5% default, marketplace-enforced on secondary sales
- **Reveal pattern**, metadata computed live from a single `revealed` flag, zero per-token updates needed
- **Reentrancy guards** on every payable function, plus a `withdraw()` that actually exists (an earlier Slither pass caught the version that didn't)
- **Custom errors** throughout, not string-based `require`, cheaper to deploy and revert
- **Owner-only admin functions**, provably locked down: there's a regression test that specifically proves an unauthorized wallet gets rejected

## Test coverage, for real

```
6 unit tests    → mint, payment validation, access control, royalties, reveal
1 fuzz test     → payment/supply boundary conditions (256 runs)
1 invariant test → 128,000 randomized mint calls, 256 runs × depth 500, 0 violations
```

Run them yourself:

```bash
forge test -vv
forge test --match-contract NFTMintingPlatformInvariantTest -vv
```

The invariant test uses a `Handler` contract that bounds inputs to realistic ranges and always attaches correct ETH, so every one of those 128,000 calls is a genuine, valid mint attempt, not a call that instantly reverts and proves nothing. `totalSupply()` never exceeded `MAX_SUPPLY` across any of them.

## Security posture, honestly stated

Slither found 35 raw findings on first pass. 34 were noise (library internals, pragma version notes) or cosmetic (naming conventions). One was real: the contract accepted ETH via `mint()` and `allowListMint()` but had no way to withdraw it, a genuine "you built a money collector with no way to collect the money" bug. Fixed, then covered by a dedicated `test_WithdrawSuccess` test.

**What's not here:** a third-party audit (Trail of Bits, OpenZeppelin, Cyfrin). That costs real money a solo project doesn't have. The honest substitute: Slither, high-count invariant fuzzing, and this paragraph, saying plainly what's missing is a stronger signal than pretending it isn't.

## Setup

```bash
git clone https://github.com/sivajisj/nft-mint-platform.git
cd nft-mint-platform
forge install
forge build
forge test
```

### Environment variables

Create `.env`:

```
PRIVATE_KEY=your_deployer_wallet_private_key
RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your-alchemy-key
ETHERSCAN_API_KEY=your_etherscan_api_key
```

Never use a wallet with real funds for testnet work. Generate a dedicated one:

```bash
cast wallet new
```

### Deploying

```bash
source .env
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

### Verifying on Etherscan

```bash
forge verify-contract <address> src/NFTMintingPlatform.sol:NFTMintingPlatform \
  --chain sepolia --etherscan-api-key $ETHERSCAN_API_KEY
```

## Architecture decisions

**ERC-721A over standard ERC-721.** The gas saving is real but conditional: it only pays off on multi-token mints in a single transaction, since the trick is skipping storage writes for all but the first token in a batch. A collection where everyone mints exactly one token at a time would see no benefit. This one supports up to a configurable batch size per allowlist mint, so the saving is real in practice.

**Checks-Effects-Interactions *and* a reentrancy guard, not just one.** CEI protects ordering within a single function. It does nothing for cross-function reentrancy (re-entering a *different* function while one is mid-call) or read-only reentrancy (a view function returning stale state mid-reentrancy, which can mislead an integrating contract even with no funds directly stolen). The guard is a shared lock across every function touching sensitive state, closing both gaps CEI alone leaves open.

**The reveal pattern stores nothing per token.** `tokenURI()` is computed live from a single `revealed` boolean. Flipping that one flag instantly changes what every past and future token returns, no migration, no per-token update, no matter how many tokens exist. Cheap by design, not by accident.

**Custom errors, not `require` strings.** Every character in a revert string is deployed bytecode and costs gas on every revert. `error InsufficientFunds();` is a 4-byte selector regardless of how descriptive the name is.

## Project structure

```
src/
  NFTMintingPlatform.sol   → the contract
test/
  NFTMintPlatform.t.sol             → unit + fuzz tests
  NFTMintingPlatformInvariantTest.t.sol → invariant test + Handler
script/
  Deploy.s.sol                          → deployment script
```

## About

Part of a full-stack portfolio project by [Sivaji Gadidala](https://sivajibuilds.netlify.app). See [`nft-infra`](https://github.com/sivajisj/nft-infra) for how this connects to the indexer, subgraph, and frontend.

[Email](mailto:sivajigsivajig703@gmail.com) · [LinkedIn](https://linkedin.com/in/sivaji-gadidala-b712ba221) · [Portfolio](https://sivajibuilds.netlify.app)
