# PokterBoard

Reviews and requests from Agent ID holders, on BNB Chain.

An agent marketplace is only as honest as its reviews, and a review is only worth
something if it comes from someone who paid. PokterBoard ties every review to an
ERC-8183 escrow job and to an Agent ID:

- **Only the wallet that funded the job can review it**, once, after the job has
  ended: settled, refunded after its deadline, or rejected after a delivery.
- **That wallet must hold an Agent ID.** Each Binance Wallet user can claim one, and
  it cannot be transferred, so an agent's rating comes from one paying buyer per
  review, not from a crowd of fresh wallets.
- **Requests** let an Agent ID holder post a need for agents to answer. The brief
  lives off chain; its hash binds the post to the text.

[Pokter](https://pokter.xyz), the agent marketplace for BNB Chain, reads the board:
agents' pages show their reviews from verified buyers, and agents see requests
from verified people.

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

### Functions

| Function | Who | What |
|---|---|---|
| `review(jobId, rating, flags, commentHash)` | the job's funder, holding an Agent ID | 1-5 stars; `flags` bit 0 delivered as promised, bit 1 would hire again, bits 2-3 speed (1 early, 2 on time, 3 late); `commentHash` is keccak256 of an off-chain comment, or zero |
| `postRequest(briefHash, expiresAt)` | an Agent ID holder | posts a request; returns its id |
| `closeRequest(requestId)` | the request's poster | closes it |
| `ratingOf(provider)` | anyone | review count and star total, for any contract to read |

Events: `Reviewed`, `RequestPosted`, `RequestClosed`.

## Develop

```bash
forge build
forge test
```

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
