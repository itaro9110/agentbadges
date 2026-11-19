# AgentBadges

**Soulbound on-chain achievement badges for Binance Agent ID holders** — a public, verifiable reputation layer for AI agents.

Built for the **Binance Agent ID Hackathon** (Binance Wallet × BNB Chain, $60,000 USDC). Submission period: 18 Nov – 9 Dec 2026 (08:00 UTC). Targets both the **Project Awards** (on-chain metrics: interacting Agent ID addresses, tx volume/count) and the **Innovation Award** (judged: Agent ID integration depth, practicality, completion, innovation).

## The idea

Agent ID (`name.ai`) is the on-chain name of an Agentic Wallet — one per user, non-transferable. AgentBadges turns that identity into **reputation you can prove on-chain**:

- Say **GM** once a day → build a streak.
- **Tip** another Agent ID holder → support the ecosystem.
- Earn **soulbound badges** (ERC-721, non-transferable) that anyone can verify on BscScan. No points database, no backend, no admin mint.

## Badges

| # | Badge | How to earn |
|---|-------|-------------|
| 1 | First GM | Say GM once |
| 2 | Three-Day Streak | GM on 3 consecutive days |
| 3 | Seven-Day Streak | GM on 7 consecutive days |
| 4 | First Tip | Tip another Agent ID holder ≥ 0.0001 BNB |
| 5 | Collector | Hold any 3 badges |

## How Agent ID is used

- **Gating (on-chain):** `gm()`, `tip()` and `claimBadge()` all require `balanceOf(msg.sender) > 0` on the Agent ID contract (`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`, BSC mainnet). Non-holders cannot interact at all.
- **Tips:** the recipient of `tip()` must also hold an Agent ID. The full amount is forwarded immediately — the contract keeps nothing.
- **Names (frontend):** the Agent ID contract does **not** implement ERC721Enumerable (`tokenOfOwnerByIndex` / `totalSupply` revert), so names are resolved from the Agent ID mint `Transfer` events (find the tokenId sent to an address, then read its `tokenURI` metadata). Graceful fallback to the truncated address if the lookup fails.
- **Leaderboard (frontend):** computed client-side from the contract's `GM` / `BadgeClaimed` events via public RPC `getLogs` — no indexer, no server.

## Contract

Single file, no imports, no proxy, no upgradeability: `src/AgentBadges.sol` (Solidity 0.8.24).

- Minimal self-contained ERC-721 with **on-chain metadata** (`tokenURI` returns a `data:application/json;base64` JSON; artwork is static SVGs in `frontend/badges/`).
- **Soulbound:** `transferFrom`, `safeTransferFrom`, `approve`, `setApprovalForAll` all revert.
- **No owner privileges over user funds:** tips forward immediately, no admin mint, no withdraw function. The only constructor inputs are the Agent ID address and the metadata base URI.
- Events for everything (`GM`, `Tip`, `BadgeClaimed`) so the leaderboard and any indexer can read activity from logs.

### Measured (local, Foundry 1.9.0)

- **Tests: 31 passed, 0 failed** (`forge test`) — mock Agent ID ERC-721; covers gating, once-per-day GM, streak counting incl. reset after a missed day (`vm.warp`), exact tip forwarding, tip rules, one-claim-per-badge, Collector requirement, soulbound reverts, views and metadata.
- **Contract size:** runtime 7,552 bytes (limit 24,576), initcode 8,315 bytes.
- **Deploy gas:** 1,789,824 gas (real tx on local anvil).
- **Function gas (test env):** `gm` ~45k (first GM ~96k), `tip` ~32–69k, `claimBadge` ~100–211k (first badge most expensive), `tokenURI` view ~98k (free off-chain read).
- **End-to-end smoke test on anvil:** deploy script → mint mock Agent IDs → `gm()` → `tip()` → `claimBadge(1)` + `claimBadge(4)` → streak 1, balance 2 badges, contract ETH balance 0. All good.

## Repo layout

```
src/AgentBadges.sol        Contract (single file)
test/AgentBadges.t.sol     Foundry tests + MockAgentId
script/Deploy.s.sol        Deploy script (BSC mainnet by default)
frontend/
  index.html               Static UI
  app.js                   Wallet connect, GM / tip / claim, leaderboard
  badges/1.svg … 5.svg     Badge artwork
DEPLOY.md                  Exact deploy + verify commands (run later)
```

`lib/forge-std` is vendored (copied, not a submodule) so the repo builds offline.

## Run the frontend locally

```bash
cd frontend
python3 -m http.server 8080
# open http://localhost:8080
```

No build step. It loads ethers v6 from a CDN. Before the contract is deployed, the page shows a banner and the action buttons stay disabled — set `CONTRACT_ADDRESS` and `DEPLOY_BLOCK` at the top of `frontend/app.js` after deploying (see `DEPLOY.md`).

## Test

```bash
forge test            # 31 tests
forge test --gas-report
forge build --sizes
```

## Deploy

See [DEPLOY.md](DEPLOY.md). **Not deployed yet** — the deploy step runs separately after the wallet session is re-authorised. It needs ~0.002 BNB for gas plus a BscScan API key for verification.

## Status

- [x] Contract written + 31/31 tests passing
- [x] Deploy script tested end-to-end on local anvil
- [x] Frontend built + syntax/HTML/SVG validated
- [ ] Deploy to BSC mainnet (needs wallet re-auth)
- [ ] Verify on BscScan
- [ ] Host frontend on GitHub Pages + submit to the hackathon
- [ ] Community Promotion lane: X post with #BinanceWalletHackathon + #AgenticWallet (separate, $100 each for 20 winners)
