# Interview Prep: Concepts, Attack Vectors, and Q&A

Drawn directly from what was actually built, debugged, and reasoned through across this project. Each question has a model answer written the way you'd actually say it out loud, not a textbook definition.

---

## Part 1: Smart Contract Security

### Q: Walk me through a reentrancy attack against a naive withdraw function.
**A:** If a function sends ETH via an external call *before* updating the caller's recorded balance, a malicious contract receiving that ETH can use its `receive()` function to call back into `withdraw()` again, before the first call finishes and the balance updates. Since the balance still shows the old, un-decremented value, the check passes again, and the attacker drains funds in a loop within a single transaction. The fix is Checks-Effects-Interactions: update state *before* making the external call, so a re-entering call sees the already-reduced balance and fails the check.

### Q: Why isn't CEI alone enough? What does a reentrancy guard add?
**A:** CEI only orders operations *within one function*. It doesn't protect against re-entering a *different* function that reads the same shared state mid-call (cross-function reentrancy), and it doesn't protect view functions that might return stale, inconsistent data during a reentrant window (read-only reentrancy) even though no state was ever illegitimately changed in that view function itself, which matters if another contract trusts that view's return value mid-attack. A reentrancy guard is a shared lock (`nonReentrant`) applied across every function touching the sensitive state, so *any* nested call into the protected surface reverts immediately, regardless of which function the attacker tries to sneak into.

### Q: How does the reentrancy guard actually work under the hood?
**A:** It's a simple state flag, not a counter. `status` starts at `NOT_ENTERED`. The modifier sets it to `ENTERED` before the function body runs, and back to `NOT_ENTERED` after. If a nested call tries to enter any function sharing that guard while `status == ENTERED`, the `require` at the top reverts immediately. It's the same shape as a mutex, one flag, whoever holds it blocks everyone else, except here "blocking" means an instant revert instead of a wait.

### Q: You said ERC-721A saves gas. Does it always?
**A:** No, and overclaiming that would be a red flag. The saving comes specifically from batch minting, ERC-721A writes ownership once per batch instead of once per token, so `ownerOf()` walks backward to the nearest recorded owner for un-written slots. If every mint is exactly one token at a time, there's no batch to compress, and the gas cost is essentially identical to standard ERC-721. The tradeoff is that transfers can be slightly more expensive, especially deep into a large unwritten batch, since the lookup walks further back. For a collection where minting happens in batches and transfers happen individually, the trade is worth it.

### Q: How would you enforce that a transaction status can only move CREATED → PENDING → BROADCASTED → CONFIRMED, never backwards or skipping states?
**A:** In both layers, for different reasons. In application code, model it as an explicit state machine, an allow-list of valid `(from, to)` pairs, reject anything not listed, this gives fast, clear error messages before ever touching the database. But the real guarantee has to live in the database itself: a `CHECK` constraint can tie related fields together (e.g., a transaction hash must be present once status passes PENDING), and a `BEFORE UPDATE` trigger comparing `OLD.status` to `NEW.status` can reject any transition not on the allow-list, no matter what wrote the update, my app, a migration script, someone's manual `psql` session. Application code alone can be bypassed by anything that talks to the database directly; a trigger cannot.

### Q: Why does a Merkle allowlist scale better than storing every address on-chain?
**A:** Storing N addresses in a mapping costs N storage writes at setup and N slots forever. A Merkle tree lets you store exactly one 32-byte root, regardless of list size, thousands or millions of addresses, same on-chain cost. To mint, a user submits their address plus a small proof (roughly log₂N hashes, so ~13 hashes for 5,000 addresses), and the contract recomputes the path from that leaf up to the root, verifying it matches the stored one. If they're not genuinely in the original tree, the recomputed root won't match.

### Q: What's the actual risk tradeoff with upgradeable contracts (proxy patterns)?
**A:** Upgradeability doesn't remove risk, it moves it. An immutable contract's risk is "can the code have a bug," fixed at deployment, permanent, but predictable and trustworthy to users. A proxy pattern's risk becomes "can I trust whoever holds the upgrade key," since that party can, in principle, change any logic, including maliciously. That's why serious upgradeable systems pair it with a multisig and a timelock, so no single actor can silently push a change, and users get a window to react before it takes effect.

---

## Part 2: Rust Concurrency

### Q: Why is holding a `std::sync::Mutex` guard across an `.await` dangerous?
**A:** `std::sync::Mutex` is a *blocking* lock. When a task holding it hits `.await`, Tokio may suspend that task and reuse the OS thread for other work, that's the whole point of async. But if another task on a different thread then tries to acquire the same lock, it has to genuinely block its entire OS thread, waiting for a lock that won't release until some unrelated async operation finishes. Under load this can stall the executor or even deadlock. The fix is either scoping the guard so it's dropped before the `.await`, or switching to `tokio::sync::Mutex`, which yields properly instead of blocking a thread, though the real best practice is keeping critical sections short regardless.

### Q: Since a resumed async task can land on a different OS thread than it started on, what does that imply about the data it holds?
**A:** Anything held across an `.await` point must be `Send`, safe to transfer between threads. A type like `Rc<T>` isn't `Send` (its reference count isn't atomic, so incrementing it from two threads is a race), so the compiler flatly refuses to compile an async function that holds an `Rc` across an await, because the generated future itself has to be `Send` for Tokio's default multi-threaded runtime. The fix is usually swapping to `Arc` (thread-safe reference counting), or pinning the task to one thread with `LocalSet` if you genuinely need non-`Send` data.

### Q: When would you reach for `Arc<Mutex<T>>` versus a channel?
**A:** `Arc<Mutex<T>>` is for when multiple tasks genuinely need to read and mutate the *same* shared data together. A channel is for when tasks just need to hand a result off to one place with no shared state at all, the sender gives up ownership entirely. Using a Mutex where a channel fits means unrelated tasks contend for a lock they don't actually need to share; using a channel where you actually need shared mutable state doesn't work at all. Most real systems use both, for different pieces of the same problem.

### Q: What are the four conditions for deadlock, and how does starvation differ?
**A:** Deadlock requires all four: mutual exclusion, hold-and-wait, no preemption, and circular wait. Break any one and deadlock can't happen, the standard fix is a global lock-ordering convention that prevents circular wait specifically. Starvation is different: no circular wait exists, a thread just never gets scheduled or never wins the lock, often because of relative priority or timing, not a structural cycle. A naive fix like swapping to `RwLock` can actually make starvation worse under heavy read load, since readers can perpetually starve a writer. Real fixes are fairness-aware locks or reducing contention structurally.

### Q: How do you prevent two workers from double-processing the same job?
**A:** The bug is a classic check-then-act race: worker A checks "is this free," worker B checks the same thing before A marks it taken, both proceed. The fix is making the claim atomic at the database level: `SELECT ... FOR UPDATE SKIP LOCKED`. It locks the row the instant it's selected, and any other worker querying for pending work simply skips a locked row and grabs a different one, no two workers can ever believe they own the same job.

---

## Part 3: Indexer / Backend Systems

### Q: Why wait for confirmations before treating a blockchain event as final?
**A:** A block only 1-2 deep can still be reverted by a chain reorganization, especially under network latency or validator timing variance. Waiting N blocks makes that vanishingly unlikely without waiting so long the UX suffers. It's a risk/speed tradeoff, not a fixed protocol law, a low-value action like an NFT mint might reasonably use 12 blocks (~24s), while a high-value DeFi liquidation would justify pushing that much higher, since the cost of showing a false "success" scales with what's at stake.

### Q: What happens if your service crashes between writing "pending" and actually broadcasting a transaction?
**A:** Store the nonce at the same moment you write the pending state, before broadcasting, so it's a reliable breadcrumb. On restart, query the chain for that address's transaction count in "pending" mode (not "latest") to determine whether that nonce was ever actually consumed. If it wasn't, it's safe to resubmit using the *same* nonce, no duplicate risk. If it was consumed, the original broadcast succeeded even though the crash happened before you recorded it, so it's a matter of reconciling state, not resending.

### Q: Why does deduplicating events on `tx_hash` alone not work?
**A:** A single transaction can emit multiple events, a batch mint of 3 tokens emits 3 separate `Transfer` events sharing one `tx_hash` but with different `log_index` values. A `UNIQUE(tx_hash, log_index)` constraint is what actually guarantees each individual event is recorded exactly once, letting the insert logic safely use `ON CONFLICT DO NOTHING` to handle re-scanning the same range after a restart without creating duplicates or erroring out.

### Q: Why SIWE instead of a password system, and what does the nonce actually protect against?
**A:** The wallet already proves identity cryptographically, signing a challenge with a private key is a stronger proof than a password, and building a second credential system on top adds attack surface for no real benefit. The nonce's job is preventing replay: it must be unpredictable (a `rand::thread_rng()`-generated value, not a counter, since a predictable nonce could theoretically let an attacker replay a previously captured signature) and single-use (invalidated immediately on successful verification, so the exact same signed message can never verify twice).

### Q: How do you know when to retry a failed request versus fail immediately?
**A:** Depends on whether the failure is transient or structural. A rate limit (429) or a network blip is transient, retrying with exponential backoff makes sense. A malformed request, like asking for a block range the provider's tier doesn't support, is a *permanent* failure, the exact same request will fail every time no matter how many times you retry it. Retrying a permanent error just wastes calls and time; the correct move is to fail fast and fix the request itself (in this case, chunking the range smaller).

---

## Part 4: General Systems / Design Judgment

### Q: Why build both a custom backend and a subgraph instead of just one?
**A:** They're not redundant, they serve different trust models. My Rust backend is *my* service, needed for anything app-specific: auth, custom queries, business logic no generic indexer provides. A subgraph is public and trustless, anyone can query the same on-chain history without needing to trust or even know about my server exists. Real projects often ship both for exactly this reason, one is "my app's backend," the other is "a public good anyone can build on."

### Q: What would you add if given a real security budget?
**A:** A third-party audit (Trail of Bits, OpenZeppelin, Cyfrin tier), which catches classes of bugs that automated tools like Slither and even heavy fuzzing can miss, human review of business logic and economic incentives specifically. Also: a fair-queue rate limiter and monitoring/alerting (Prometheus/Grafana, structured tracing) on the indexer, since right now failures are visible in logs but nothing pages anyone. Being able to name the gap precisely, rather than claim the project is bulletproof, is itself the stronger answer.

### Q: Walk me through a real bug you hit and how you diagnosed it.
**A:** The Docker image for the indexer kept silently running an empty, do-nothing binary after supposedly successful rebuilds. The actual root cause was two-layered: first, `sqlx`'s compile-time query macros need live database access to verify queries, which doesn't exist inside a Docker build, so the real build was failing every time; second, once that was fixed, a glibc version mismatch between the Rust builder image and a separate, older runtime image caused the compiled binary to fail to even start. The reason it looked like silent, mysterious runtime behavior rather than an obvious build failure is that Docker Compose quietly reuses the last *successful* image whenever a rebuild fails, so the container kept running an old placeholder binary from a much earlier, unrelated caching experiment. The real lesson: a stale or suspiciously undersized image is usually a sign the build itself is failing, not a runtime bug, worth checking that first rather than debugging the running container's behavior directly.
