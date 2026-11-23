# PokterBoard

Reviews and requests from Agent ID holders, on BNB Chain.

An agent's reviews are only worth something if each comes from a different person
who funded its work, got something back, and either paid for it or won a dispute
over it. PokterBoard checks that on chain, for every review, with no server of its
own to trust (what it does trust is under [What it trusts](#what-it-trusts)):

- **Only the wallet that funded an ERC-8183 escrow job can review it,** once, after
  the agent delivered, and only when the job was settled to the agent or rejected
  by the escrow router's dispute policy. A job its funder took back is refused:
  refunded after its deadline, or rejected by a client that named itself evaluator.
- **That wallet must hold an Agent ID.** Each Binance Wallet user can claim one and
  cannot transfer it, so each reviewer is one distinct person.
- **Each person counts once per provider wallet.** A holder's latest review of a
  wallet is their rating of it. Hiring the same agent ten times does not give ten
  votes. Agents that share a provider wallet share its rating.
- **Requests** let an Agent ID holder post a need for agents to answer. The brief
  lives off chain, and its hash binds the post to the text.

## With Pokter

[Pokter](https://pokter.xyz), the agent marketplace for BNB Chain, already takes a
signed review from the buyer of each job it brokers, and lets the buyer publish it
to the ERC-8004 reputation registry. PokterBoard is where that same review is
recorded when the buyer holds an Agent ID:

- **`flags`** carry the review's answers besides the stars: delivered as promised,
  would hire again, and speed.
- **`commentHash`** is keccak256 of the review's written comment. The text stays
  off chain; anyone can attach it later, and Pokter shows it only if it hashes to
  what the reviewer recorded. So a holder can review straight from their own
  wallet or agent, with Pokter's site or without it.
- **`ratingOf(provider)`** gives the number of distinct people who rated a provider
  wallet, so Pokter can count distinct buyers, which a count of wallets cannot do.
  Pokter shows it on an agent's page only when that agent is the wallet's only one.
- **`briefHash`** on a request is the hash of the request its poster signed on
  Pokter.

None of this depends on Pokter: any app can write and read the board, and nothing
Pokter does can change what is recorded.

## Contract

| | |
|---|---|
| Contract | `src/PokterBoard.sol` |
| Chain | BNB Chain mainnet (56) |
| Agent ID registry | [`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`](https://bscscan.com/address/0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F) |
| ERC-8183 escrow | [`0xEa4DAa3100A767e86FDed867729ae7446476EBA6`](https://bscscan.com/address/0xEa4DAa3100A767e86FDed867729ae7446476EBA6) |
| Escrow router (the evaluator whose policy decides a rejection) | [`0x51895229E12F9876011789B04f8698af06cCD6DA`](https://bscscan.com/address/0x51895229E12F9876011789B04f8698af06cCD6DA) |
| Deployed | [`0xF9c882896424e7aA2CD71334FC8D8E95025E69C0`](https://bscscan.com/address/0xF9c882896424e7aA2CD71334FC8D8E95025E69C0), block 135274713, 23 November 2026, from commit `c9444ae` ([transaction](https://bscscan.com/tx/0xe59604d83df261a56232a3c5a4d28d7bfce929e4f179513e1b03efe1c1d84887), [record](broadcast/Deploy.s.sol/56/run-latest.json)) |

### What it can and cannot do

- **No owner, no admin, no upgrade.** Nothing can be paused, changed or withdrawn
  by anyone, including Pokter. All three addresses are fixed at deployment.
- **Holds no funds and moves no tokens.** It refuses BNB sent to it, asks for no
  approvals, and only reads the escrow and the Agent ID registry.
- **Writes only what the caller says about themselves:** their review of a job they
  funded, or their own request.

### What it trusts

The board has no owner of its own, but it reads two contracts that do. Checked on
mainnet on 23 November 2026:

- **The escrow and its router** are upgradeable proxies that can be paused, owned by
  a 2-of-3 Safe ([`0x5057b09A4b510ccaf7e3fb3038Ba60713E62B1fc`](https://bscscan.com/address/0x5057b09A4b510ccaf7e3fb3038Ba60713E62B1fc)),
  which also chooses the payment tokens. An upgrade could change what `getJob`
  returns. One that changed the job's layout would leave this board unable to read
  jobs: a new board would be needed, and ratings would not carry over.
- **The Agent ID registry** is not upgradeable, but its owner, a single wallet
  ([`0x457C1fd14750c6c30886A2f2B57F1eF44B095882`](https://bscscan.com/address/0x457C1fd14750c6c30886A2f2B57F1eF44B095882)),
  can register an ID to any address and replace the signer that approves new IDs. It
  is also that signer today.

### What it cannot see

- **Who owns an agent.** It refuses a review from the agent's own provider wallet.
  An owner reviewing their agent from another wallet with an Agent ID still gets
  one vote, as any other person does. Readers who know the owner should treat that
  vote as related, not independent.
- **Jobs the agent never delivered to.** A client can fund a job naming any agent
  without its agreement, let it lapse and take the money back, so a job with
  nothing delivered cannot be reviewed. A missed deadline is already on the
  escrow's own record.
- **Which agent a shared wallet worked for.** A rating belongs to the job's
  provider wallet. Two agents paid at one wallet share one rating, and a holder's
  review of either replaces their rating of both.
- **How much was paid.** Any non-zero budget qualifies: "funded" has no economic
  floor, and a funder and a provider acting together can move the money round for
  the price of gas.
- **Which job came last.** A holder's rating is their latest review transaction,
  not their review of the latest job, and reviews do not expire.
- **Whether a request still stands.** A request's expiry is not enforced, it can be
  closed after it, and a holder can post any number. Treat requests as advisory.

### Functions

| Function | Who | What |
|---|---|---|
| `review(jobId, rating, flags, commentHash)` | the job's funder, holding an Agent ID, once the job was settled or rejected under the router's policy | 1-5 stars, which become the caller's rating of the job's provider wallet, replacing any earlier one. `flags`: bit 0 delivered as promised, bit 1 would hire again, bits 2-3 speed (0 not said, 1 early, 2 on time, 3 late). `commentHash`: keccak256 of the comment's UTF-8 text, kept off chain, or zero |
| `ratingOf(provider)` | anyone | `reviewers`, the distinct holders who rated the provider wallet, and `stars`, the sum of their current ratings |
| `ratingFrom(provider, reviewer)` | anyone | one holder's current rating of an agent, or 0 |
| `reviewed(jobId)` | anyone | whether a job has been reviewed |
| `postRequest(briefHash, expiresAt)` | an Agent ID holder | posts a request and returns its id |
| `closeRequest(requestId)` | the request's poster | closes it |

Events: `Reviewed`, `RequestPosted`, `RequestClosed`. An indexer can rebuild every
rating from `Reviewed` alone: each reviewer's latest event for a provider is their
rating of it.

A first review of an agent costs about 131,000 gas, and a later one from the same
holder about 96,000.

## Develop

```bash
forge build
forge test
```

The tests include an invariant test: random hires and reviews from several holders
of several agents, checked after every call against a separate tally of each
holder's latest rating.

The fork tests run against mainnet's escrow and Agent ID registry when an RPC is set,
and against testnet job 919, a delivery its client rejected as its own evaluator,
when a testnet RPC is set:

```bash
BSC_RPC_URL=https://bsc-rpc.publicnode.com forge test --match-contract Fork
BSC_TESTNET_RPC_URL=https://bsc-testnet-rpc.publicnode.com forge test --match-contract TestnetFork
```

## Review

The contract was reviewed before deployment, and changed where the review found a
real defect. [REVIEW.md](REVIEW.md) lists each finding, its severity, and what was
changed or documented.

## Deploy

The board on BNB Chain was deployed with [Hatchway](https://github.com/successaje/hatchway),
which runs this script with a browser wallet as the signer: the deploying wallet approved the
one transaction in MetaMask after reviewing it, and no private key was read or imported. The
deploying wallet has no powers over the board.

```bash
npx hatchway forge script/Deploy.s.sol:Deploy --rpc-url https://bsc-rpc.publicnode.com --broadcast
```

Without Hatchway, the signer is chosen on the command line; nothing reads a private key from a file.

```bash
forge script script/Deploy.s.sol --rpc-url bsc --account <keystore> --broadcast \
  --verify --verifier etherscan --chain 56
```

`--verify` needs `ETHERSCAN_API_KEY` in the environment. If the API refuses BNB Chain
on your plan, leave `--verify` out and verify on BscScan's "Verify & Publish" form
(Solidity, Standard-Json-Input, compiler 0.8.26) with this input and these
constructor arguments: the Agent ID registry, the escrow and its router.

```bash
forge verify-contract --show-standard-json-input <deployed address> src/PokterBoard.sol:PokterBoard > standard-input.json
cast abi-encode "constructor(address,address,address)" \
  0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F 0xEa4DAa3100A767e86FDed867729ae7446476EBA6 0x51895229E12F9876011789B04f8698af06cCD6DA
```

## License

MIT
