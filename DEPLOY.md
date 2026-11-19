# Deploy AgentBadges to BSC mainnet

> **Run this later, after the wallet session is re-authorised.** Nothing here
> has been deployed yet. Do not paste a private key into chat or any file.

## 0. Prerequisites

- Foundry installed (`forge`, `cast`) — already at `~/.foundry/bin`.
- A funded deployer wallet on **BNB Smart Chain** (BSC mainnet, chain 56).
  The deployer only needs gas — roughly **0.002 BNB** is plenty at normal
  gas prices (measured deploy: 1,789,824 gas; at 1 gwei ≈ 0.0018 BNB,
  at 0.1 gwei ≈ 0.00018 BNB).
- A **BscScan API key** (free at bscscan.com/myapikey) for verification.
- The deploy private key available as an environment variable only:

```bash
export PRIVATE_KEY="0x..."        # deployer key — never commit, never share
export BSCSCAN_API_KEY="..."      # bscscan.com API key
```

## 1. Build + test (sanity check)

```bash
cd ~/workspace/agent-id-hackathon/agentbadges
export PATH="$HOME/.foundry/bin:$PATH"
forge build
forge test   # expect: 31 passed, 0 failed
```

## 2. Deploy + verify in one command

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://bsc-dataseed.binance.org/ \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $BSCSCAN_API_KEY \
  --chain bsc
```

What it does:

- Deploys `AgentBadges` with the Agent ID gate set to the mainnet contract
  `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`.
- Verifies the source on BscScan (single file, no imports — verification is
  straightforward).

Overrides (optional, env vars read by the script):

```bash
AGENT_ID="0x..."   # default: the mainnet Agent ID contract above
```

Save the output: contract address, transaction hash, block number.

## 3. If verification fails separately

```bash
forge verify-contract <CONTRACT_ADDRESS> src/AgentBadges.sol:AgentBadges \
  --chain bsc \
  --etherscan-api-key $BSCSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" \
      0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F)
```

No BscScan API key? Verify on Sourcify instead (no key needed):

```bash
forge verify-contract <CONTRACT_ADDRESS> src/AgentBadges.sol:AgentBadges \
  --chain bsc --verifier sourcify \
  --constructor-args $(cast abi-encode "constructor(address)" \
      0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F)
```

## 4. Wire up the frontend

1. In `frontend/app.js`, set:
   - `CONTRACT_ADDRESS` to the deployed address
   - `DEPLOY_BLOCK` to the block number of the deployment transaction
2. Commit + push to GitHub, enable **GitHub Pages** on the repo
   (Settings → Pages → Deploy from branch, folder `/docs` —
   `docs/` is a copy of `frontend/`; the page must serve `index.html` and `badges/*.svg`).
3. Open the Pages URL, connect a wallet that holds an Agent ID, and smoke
   test: GM → check streak → tip 0.0001 BNB to another holder → claim
   badge 1. Confirm each transaction on BscScan.

## 5. Submit to the hackathon

- Submission closes **9 Dec 2026 08:00 UTC (15:00 WIB)**.
- Submit project name, website (GitHub Pages URL), contract address(es),
  and the Agent ID usage description via the Binance announcement form.
- The contract is already live and open-source on BscScan at that point,
  which satisfies the eligibility rules. The Innovation Award additionally
  needs **≥ 30 Agent ID addresses** interacting with the contract during the
  submission period — drive that after launch (GM + tip are the cheapest
  interactions: ~45k and ~50k gas).

## Measured gas (local, for budgeting)

| Action | Gas |
|---|---|
| Deploy | 1,789,824 |
| `gm` (daily) | ~45,000 (first GM ~96,000) |
| `tip` | ~32,000–69,000 |
| `claimBadge` | ~100,000–211,000 (first badge most expensive) |
| `tokenURI` | ~98,000 (view — free off-chain) |

At BSC gas prices of 0.1–1 gwei, a GM costs roughly 0.000005–0.00005 BNB
and a tip roughly 0.000003–0.00007 BNB plus the tipped amount.

## Local dry run (already done 19 Nov 2026)

The deploy script was tested end-to-end against a local anvil chain:
deploy → mock Agent IDs → `gm()` → `tip()` → `claimBadge(1)` +
`claimBadge(4)` → streak 1, 2 badges, contract ETH balance 0. All good.
(One gotcha found during that test: anvil's account #0 private key ends in
`…f4f2ff80` — a one-digit typo in the key gives an unfunded address and an
"insufficient funds" error. Always copy the key from anvil's startup log.)
