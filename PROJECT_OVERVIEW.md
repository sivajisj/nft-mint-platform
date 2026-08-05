# Building the NFT Minting Platform: What, How, and Why

A narrative walkthrough of all four repos, why each piece exists, how it was actually built (including the debugging that shaped it), and the reasoning behind every major decision. Written to prepare for questions like "walk me through this project."

---

## The one-paragraph version

A gas-optimized ERC-721A contract deployed and verified live on Sepolia, feeding an async Rust indexer that watches the chain with reorg-safe confirmation depth and serves a REST API with wallet-based (SIWE) auth, a TheGraph subgraph as a second, trustless way to query the same on-chain data, and a Next.js frontend that connects a wallet, reads live contract state, executes real mint transactions, and shows a user what they actually own. Four repos, four toolchains, wired together, Dockerized, with CI running on every push.

---

## 1. The contract (`nft-mint-platform`)

### What
An ERC-721A NFT contract: public mint, merkle-allowlist mint, ERC-2981 royalties, an unrevealed-until-flipped metadata pattern, owner-only admin controls, reentrancy guards, custom errors, and a `withdraw()` function.

### How it was actually built
Started from a bare Foundry scaffold, `forge init`, OpenZeppelin and ERC721A installed as real git-submodule dependencies. Built incrementally: mint function first (with a deliberate off-by-one bug, `>=` instead of `>` against `MAX_SUPPLY`, caught by writing a fuzz test that immediately found the edge case where the last legitimate token couldn't be minted). Then merkle allowlist, wired in without access control at first, on purpose, to prove the vulnerability existed with a passing test that shouldn't have passed, then locked down with `Ownable` and the same test flipped to prove the fix. Then royalties, reveal, reentrancy guards. Ran a real Slither pass: 35 raw findings, 34 noise (library internals, pragma warnings), one real (`locked-ether`, the contract accepted payment with no way to withdraw it). Fixed, tested. Closed out with a 128,000-call invariant test using a `Handler` contract that bounds inputs to realistic ranges so the fuzzer actually exercises real mint activity instead of reverting on every call. Deployed to Sepolia after working through two separate faucet/gas-price dead ends (Polygon Amoy's gas price kept climbing mid-attempt, so the deploy moved to Sepolia instead), then verified on Etherscan.

### Why these specific decisions
- **ERC-721A, not standard ERC-721**: batch mints write ownership once per batch instead of once per token, real gas savings, but only when users actually mint more than one token per transaction. Worth being able to say precisely, not oversell it.
- **CEI plus a reentrancy guard, not just one**: CEI only orders operations within a single function. It does nothing against cross-function reentrancy (re-entering a *different* function mid-call) or read-only reentrancy (a view function returning stale state that a different contract might trust). The guard closes both gaps.
- **Custom errors over `require` strings**: every character in a revert string is deployed bytecode and costs gas on revert. A custom error is a 4-byte selector no matter how descriptive its name is.
- **The reveal pattern stores nothing per token**: `tokenURI()` is computed live from one boolean flag. Flipping it once changes what every token, past and future, returns. No migration, no per-token write, regardless of collection size.
- **No third-party audit**: costs real money a solo project doesn't have. The honest substitute is Slither plus heavy invariant fuzzing, stated plainly rather than implied otherwise.

---

## 2. The indexer (`nft-indexer`)

### What
An async Rust service (Axum + SQLx + Postgres + alloy) that watches the deployed contract, decodes and stores its events, waits for real confirmation depth before trusting them, and serves both a REST API and wallet-based authentication, all running concurrently on one Tokio runtime.

### How it was actually built
Started with the simplest possible thing: connect to Sepolia, print the latest block number. Then decode a real `Transfer` event using alloy's `sol!` macro, which required actually minting a token via `cast send` to have something real to detect, proving the whole chain worked: mint on-chain, indexer picks it up, decodes it correctly. Hit Alchemy's free-tier 10-block range limit on `eth_getLogs` almost immediately, fixed by chunking the scan into 10-block windows with retry-and-backoff on rate limits (and deliberately *not* retrying permanent errors like a malformed request range, since retrying those wastes calls for no reason). Turned the one-shot script into a real indexer by wrapping it in a loop that tracks `last_scanned_block` and re-polls every 15 seconds, refactored into proper modules (`config`, `db`, `chain`, `events`, `auth`) once the single-file version got unwieldy. Added Postgres with a `UNIQUE(tx_hash, log_index)` constraint (not just `tx_hash`, since a single transaction can emit multiple events, a 3-token batch mint emits 3 separate `Transfer` logs). Added confirmation-depth promotion (`confirmed = true` only once a block clears 12 confirmations), running as part of the same continuous loop, so a passing scan naturally promotes older unconfirmed events over time without a separate process. Built SIWE auth from scratch: nonce issuance, message verification, single-use nonce invalidation, expiry, structured error types instead of bare HTTP status codes. Debugged a genuinely hard Docker issue: the container kept silently shipping an empty 437KB placeholder binary because `cargo build --release` was failing inside Docker (first because `sqlx`'s compile-time query macros need database access that doesn't exist in a build environment, fixed with `cargo sqlx prepare` and `SQLX_OFFLINE=true`; then a glibc mismatch between the Debian-13-based Rust builder and a Debian-12 runtime image, fixed by matching them), and Docker Compose was quietly reusing the last *successful* image on every failed rebuild rather than surfacing the failure loudly. Same root cause tripped CI later (an out-of-date `.sqlx/` cache missing a newer query), fixed by regenerating and committing the cache.

### Why these specific decisions
- **Rust, not Node or Go**: SQLx's compile-time query verification catches a wrong column type or malformed query at build time, not as a silently wrong response in production. Tokio's async model runs the indexing loop and the API server concurrently on one thread pool, `tokio::spawn`, no separate process or message queue needed.
- **Chunked scanning with retry/backoff, not one big query**: a structural constraint (RPC provider rate limits) that any real indexer has to handle, not a toy simplification.
- **12-block confirmation depth**: a risk/UX tradeoff, not a fixed protocol rule. Deep enough that spontaneous reorgs are vanishingly unlikely, shallow enough that the wait is tolerable. A high-value DeFi protocol would reasonably push this to 64-128+.
- **`UNIQUE(tx_hash, log_index)`**: makes duplicate-prevention a database-enforced guarantee, not something application code has to remember to check correctly every time.
- **SIWE over password auth**: the wallet already proves identity cryptographically. A password system on top would be redundant attack surface for no real benefit.

---

## 3. The subgraph (`nft-minting-subgraph`)

### What
A TheGraph subgraph, auto-scaffolded from the verified contract's ABI, indexing the same events into a public, GraphQL-queryable dataset. Currently builds and codegens cleanly locally; not yet deployed to Subgraph Studio, stated honestly rather than implied otherwise.

### How it was actually built
`graph init --from-contract`, which required the contract to be Etherscan-verified first to auto-fetch the ABI (a real, useful side effect: verifying the contract was originally just a subgraph prerequisite, but it turned into a genuine credibility improvement for the contract repo on its own). Learned GraphQL and AssemblyScript from scratch in a dedicated, separate deep-dive across five structured sessions before touching the actual mapping logic, rather than guessing at a new query language and a new, restricted TypeScript-like language simultaneously while also debugging a live indexer.

### Why it exists alongside a custom Rust backend
Not redundant. The Rust indexer is *my* backend, needed for auth and app-specific logic no generic indexer would provide. The subgraph is a second, independent, trustless way for *anyone* to query the same on-chain history without needing to trust or even know about my server. Real NFT projects commonly ship both for exactly this reason.

---

## 4. The frontend (`nft-frontend`)

### What
The actual application: wallet connection, live contract reads, a real mint transaction with an honest multi-state UI, an owned-tokens gallery backed by the Rust API, and a full SIWE sign-in flow, wrapped in a deliberately non-generic "engineering blueprint" design system.

### How it was actually built
Scaffolded with `create-next-app`, wagmi and RainbowKit added for wallet connection. Hit a real, hard-to-diagnose bug: RainbowKit's `ConnectButton` rendered completely empty in Chrome (but fine in Firefox), eventually traced to Coinbase's Smart Wallet connector (pulled in by RainbowKit's *default* wallet list) injecting an iframe with a legacy `border="0"` attribute that broke provider initialization, an `invalid border=0` error thrown deep inside `RainbowKitProvider`. Fixed at the root by building an explicit wallet list (MetaMask, WalletConnect, Rainbow, generic injected) instead of patching around the symptom. Wired `useReadContract` for live `totalSupply()`, then the real mint flow with two distinct hooks, `useWriteContract` for the signature/broadcast, `useWaitForTransactionReceipt` for actual on-chain confirmation, since a transaction hash existing only means it was *broadcast*, not that it *succeeded*. Built the owned-tokens gallery against the Rust API (the only real option, since the contract's ERC-721A implementation has no on-chain "list tokens by owner" call without the optional Enumerable extension). Closed with a full SIWE flow: build the exact EIP-4361 message client-side (informed directly by the earlier hand-typed-message debugging session, where a stray leading blank line and a malformed timestamp both broke backend parsing), request a wallet signature, POST to the backend, show an honest "LEDGER SIGNED" state only once genuinely verified.

### Why these specific decisions
- **An explicit wallet list, not RainbowKit's default**: removed a real, load-bearing bug at its source rather than working around the symptom.
- **Two separate hooks for the mint transaction**: showing "success" the instant a hash exists, before the chain actually mines it, is a common, real Web3 UI mistake this deliberately avoids.
- **Querying the Rust API for owned tokens, not scanning on-chain**: the correct, efficient choice given the contract's actual capabilities, not a workaround.
- **Building the SIWE message programmatically, not by hand**: eliminates an entire class of formatting bugs already discovered the hard way once.
- **A custom, subject-grounded design system**: a minting platform styled like a die-press spec drawing (navy/brass, Space Grotesk, tick-mark seal), a deliberate choice against the generic cream-serif or dark-neon patterns that read as templated.

---

## The system as a whole

```
Sepolia contract (verified)
        │ emits Transfer events
        ├──────────────► nft-indexer (Rust)  ──HTTP──► nft-frontend (Next.js)
        │                  - 12-block confirm
        │                  - Postgres
        │                  - SIWE auth
        │                  - Dockerized, CI green
        │
        └──────────────► nft-minting-subgraph (TheGraph)
                           - independent, trustless query path
```

Two independent read paths off the same on-chain truth, one backend I control for app logic, one public and trustless for anyone. That split, and being able to explain exactly why, is itself one of the stronger architectural signals in this project.
