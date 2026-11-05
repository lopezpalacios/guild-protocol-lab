# Contracts

Foundry project. Five contracts, 37 tests.

```bash
forge build
forge test -vv
forge test --match-contract LoadSimTest -vv   # the 200-person dry run
```

See the [root README](../README.md) for the quickstart, and [`../LAB-PACK.md`](../LAB-PACK.md)
for why these five and not the other four.

| File | Encounter | One-line |
|---|---|---|
| `src/LabToken.sol` | E2, E5 | ERC-20 with an immutable minter and a cap |
| `src/MerkleDistributor.sol` | E2 | Claim-based airdrop; `claim` pays `account`, never `msg.sender` |
| `src/AdventurerBadge.sol` | E3, E9 | ERC-721, on-chain SVG, operator fallback |
| `src/Ballot.sol` | E1, E8 | EIP-712 ballots, batched, equal + token-weighted |
| `src/LabPair.sol` | E5 | Constant product, 30bps fee, hard trade cap |

`via_ir = true` is on because the deploy script's string assembly trips the legacy pipeline's
stack limit. Compile time is ~90s cold; cached rebuilds are fast.
