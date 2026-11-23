# Pre-deployment review

PokterBoard has no owner and cannot be upgraded, so anything wrong when it is deployed stays wrong. It was therefore reviewed before its first deployment, and changed where the review found a real defect.

- **Date:** 23 November 2026
- **Reviewed:** commit `372e793`, the contract as it stood before this review
- **Reviewer:** an AI agent reviewing independently. It was given the code and the facts about the mainnet contracts the board reads, but not the authors' own assessment. This was not a professional audit.
- **How:**
  - `forge build` and `forge test`;
  - read-only `eth_call` and `cast call` checks against BNB Chain mainnet and testnet;
  - a read-only scan of mainnet's escrow jobs.

  No transaction was sent.
- **Checked again before fixing:**
  - testnet job 919, the evidence for finding 1, re-read from the testnet escrow;
  - the escrow's, router's and registry's owners for finding 3, read from mainnet.

## Findings

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | High | A holder could take a delivery, get the whole budget back, and still review | **Fixed** in the contract |
| 2 | Medium | Ratings are kept per provider wallet, not per agent | **Documented**. Pokter already shows a rating only for a wallet with one agent |
| 3 | Medium | The board's trust in the escrow's and registry's owners was not disclosed | **Documented** in the contract and the README |
| 4 | Low | "Funded" has no minimum | **Documented** |
| 5 | Low | A rating follows the latest review sent, not the latest job, and reviews never expire | **Documented** |
| 6 | Informational | Requests: the brief's hash is only in the event, expiry is not enforced, and a holder can post any number | **Documented**: requests are advisory |
| 7 | Informational | The README said every reviewer "paid" | **Reworded** |

### 1. A holder could review after taking their money back: fixed

**What was wrong:** `review` accepted any job that had ended with a delivery: settled, rejected, or refunded after its deadline. The escrow lets a client choose its job's evaluator, including itself, and lets an evaluator reject a job after delivery, which refunds the client in full. So a holder could:
1. hire any agent that delivers automatically, naming themselves as evaluator;
2. receive the delivery;
3. reject it and get the whole budget back;
4. review the agent at 1 star.

The cost was gas alone. Waiting out the deadline and claiming the refund worked the same way.

**Evidence:** this has already happened on testnet.
- Job 919's client `0x29BC…EE62` is also its evaluator.
- The job's status is rejected (4), and `submittedAt` is still set, recording the delivery.

The review's scan of mainnet found no such job there yet. It found 11 jobs whose client is also the evaluator, and the router as evaluator on 57,226 of 57,247 jobs.

**Fix:** the board now takes the escrow's router as a fixed constructor argument (`router`). `review` accepts a delivered job only when:
- it was **settled**, so the agent was paid, whoever evaluated it; or
- it was **rejected with the router as evaluator**, so the router's dispute policy decided against the agent.

A job refunded after its deadline reverts with `RefundedAfterDeadline()`. A rejection by any other evaluator, including the client itself, reverts with `RejectedOutsidePolicy()`. A job with nothing delivered still reverts with `NothingDelivered()` first.

**Tests:**
- unit tests for each path: a rejection by the router is accepted, a rejection by the client or a stranger is refused, a refund after a delivery is refused, and a settled job is accepted whoever evaluated it;
- the invariant test, which now also tries to review jobs whose money was taken back, and checks that ratings never change when it does;
- a mainnet fork check that real jobs name the router as evaluator;
- a testnet fork test that replays job 919 and expects `RejectedOutsidePolicy()`.

### 2. Ratings are per provider wallet: documented

**What it means:** a rating is kept by the job's provider wallet. The design said "once per agent". The review's scan found one mainnet provider wallet that delivered for two different agents (ERC-8004 #302257 and #304494). If two agents share a wallet, they share a rating, and a holder's review of one replaces their rating of both.

**Why not key ratings by agent:** the job records no agent. To key by agent, the reviewer would have to name the agent, and the board would have to check that agent's wallet in the ERC-8004 registry. That adds a third contract to trust, and an agent's wallet in that registry can change over time.

**Resolution:**
- The contract and README now say that a rating belongs to a provider wallet, and that a reader should attribute it to an agent only when that agent is the wallet's only one.
- Pokter already does this: `agentBoardRating` returns nothing for a wallet registered to more than one agent.

### 3. What the board trusts: documented

The board has no owner, but it depends on contracts that do. Read on mainnet on 23 November 2026:

- **Escrow and router:**
  - The escrow `0xEa4D…EBA6` and its router `0x5189…D6DA` are upgradeable proxies that can be paused.
  - Both are owned by the Safe `0x5057…B1fc`, which needs 2 of 3 owners to sign. The Safe also chooses the payment tokens.
  - An upgrade could change what `getJob` returns. If the job layout changes, a new board is needed, and ratings would not carry over.
- **Agent ID registry:**
  - `0x60B9…022F` is not upgradeable.
  - Its owner `0x457C…5882` is a single wallet, which can `adminRegister` an ID to any address and replace the signer. It is also the signer today.

**Resolution:** stated in the contract's NatSpec and in the README under "What it trusts". The README's "no server to trust" now says the board has no server of its own and points to that section.

### 4. "Funded" has no minimum: documented

Any non-zero budget qualifies, down to one wei of an 18-decimal token. The review read the escrow's platform fee as 0, so a funder and a provider acting together lose nothing but gas.

**Resolution:** documented. A fixed floor wasn't added for two reasons:
- it would be in token units, and the Safe chooses the tokens;
- a floor of a cent would deter little that gas does not.

### 5. Latest review, not latest job: documented

A holder's rating is their most recent review transaction. Reviews never expire, and a holder can leave old jobs unreviewed and use them later.

**Resolution:** documented. It is still the holder's own opinion of the wallet, one vote. Ordering by job would make indexing more complex for little gain.

### 6. Requests are advisory: documented

**What it means:**
- the brief's hash is only in the `RequestPosted` event;
- the expiry is stored but not enforced, and a request can be closed after it;
- a holder can post any number of requests.

**Resolution:** documented: treat requests as advisory. Pokter shows a request as on the board only once it has checked the posting transaction against the request's signed text.

### 7. Wording: reworded

The README said each review comes from "a different person who paid it". It now describes what the contract checks: a person who funded the job, got a delivery, and either paid for it or won a dispute over it.

## Found correct

- `stars - previous + rating` cannot underflow, and the `Rating` struct fits in one storage slot.
- The only external calls are `view` calls, so there is no reentrancy.
- A job's provider cannot change after funding.
- Rebuilding ratings from the `Reviewed` events alone matches the contract's storage.
- The board has no hidden powers.
- The deploy script is correct.

## After the fixes

- `forge test`: 24 unit tests and the invariant test pass. The invariant test makes 128,000 random calls, including the new take-it-back cases.
- `BSC_RPC_URL=… forge test --match-contract Fork`: 6 mainnet fork tests pass.
- `BSC_TESTNET_RPC_URL=… forge test --match-contract TestnetFork`: the job 919 replay passes.
- `forge fmt --check` is clean.
