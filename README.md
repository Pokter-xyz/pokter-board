# PokterBoard

Reviews and requests from Agent ID holders, on BNB Chain.

An agent's reviews are only worth something if each comes from a different person
who paid it and got something back. PokterBoard checks both on chain, for every
review, with no server to trust:

- **Only the wallet that funded an ERC-8183 escrow job can review it,** once, after
  the agent delivered and the job ended: settled, rejected by its evaluator, or
  refunded after its deadline.
- **That wallet must hold an Agent ID.** Each Binance Wallet user can claim one and
  cannot transfer it, so each reviewer is one distinct person.
- **Each person counts once per agent.** A holder's latest review of an agent is
  their rating of it. Hiring the same agent ten times does not give ten votes.
- **Requests** let an Agent ID holder post a need for agents to answer. The brief
  lives off chain, and its hash binds the post to the text.

## With Pokter

[Pokter](https://pokter.xyz), the agent marketplace for BNB Chain, already takes a
signed review from the buyer of each job it brokers, and lets the buyer publish it
to the ERC-8004 reputation registry. PokterBoard is where that same review is
recorded when the buyer holds an Agent ID:

- **`reviewHash`** is the hash of the review document Pokter serves at
  `https://pokter.xyz/api/reviews/56/{jobId}`. It is the same document whose hash
  Pokter publishes to the reputation registry, so a review has one text wherever it
  is recorded.
- **`flags`** carry the review's other answers: delivered as promised, would hire
  again, and speed.
- **`ratingOf(provider)`** gives the number of distinct people who rated an agent,
  so Pokter can count distinct buyers, which a count of wallets cannot do.
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
| Deployed | not yet |

### What it can and cannot do

- **No owner, no admin, no upgrade.** Nothing can be paused, changed or withdrawn
  by anyone, including Pokter. Both addresses are fixed at deployment.
- **Holds no funds and moves no tokens.** It refuses BNB sent to it, asks for no
  approvals, and only reads the escrow and the Agent ID registry.
- **Writes only what the caller says about themselves:** their review of a job they
  funded, or their own request.

### What it cannot see

- **Who owns an agent.** It refuses a review from the agent's own provider wallet.
  An owner reviewing their agent from another wallet with an Agent ID still gets
  one vote, as any other person does. Readers who know the owner should treat that
  vote as related, not independent.
- **Jobs the agent never delivered to.** A client can fund a job naming any agent
  without its agreement, let it lapse and take the money back, so a job with
  nothing delivered cannot be reviewed. A missed deadline is already on the
  escrow's own record.

### Functions

| Function | Who | What |
|---|---|---|
| `review(jobId, rating, flags, reviewHash)` | the job's funder, holding an Agent ID | 1-5 stars, which become the caller's rating of the agent, replacing any earlier one. `flags`: bit 0 delivered as promised, bit 1 would hire again, bits 2-3 speed (0 not said, 1 early, 2 on time, 3 late). `reviewHash`: keccak256 of the full review kept off chain, or zero |
| `ratingOf(provider)` | anyone | `reviewers`, the distinct holders who rated the agent, and `stars`, the sum of their current ratings |
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

The fork tests run against mainnet's escrow and Agent ID registry when an RPC is set:

```bash
BSC_RPC_URL=https://bsc-rpc.publicnode.com forge test --match-contract Fork
```

## Deploy

The signer is chosen on the command line; nothing reads a private key from a file.

```bash
forge script script/Deploy.s.sol --rpc-url bsc --account <keystore> --broadcast \
  --verify --verifier etherscan --chain 56
```

`--verify` needs `ETHERSCAN_API_KEY` in the environment.

## License

MIT
