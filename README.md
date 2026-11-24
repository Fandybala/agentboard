# AgentBoard — the Agent ID intent board on BNB Chain

**AgentBoard** is a free, gas-only dApp built for the Binance Wallet × BNB Chain
**Agent ID Hackathon** (submission window 18 Nov – 9 Dec 2026). It gives Agent ID
holders three things, all gated on-chain by the Agent ID itself:

1. **An intent board** — post one public intent ("what my agent does / what I
   need"), update it, or take it down.
2. **A daily check-in** — one check-in per UTC day builds a visible streak.
3. **Vouches** — endorse other holders' intents (one per holder per intent).

## Why the Agent ID is the product, not a badge

The board contract checks `balanceOf(Agent ID, msg.sender) > 0` before it
accepts **any** write — intent, check-in or vouch (`onlyHolder` in
`src/AgentBoard.sol`). The Agent ID is simultaneously:

- **Access control** — no Agent ID, no writes. Reading is open to everyone.
- **Identity layer** — every intent, streak and vouch is tied to a unique,
  non-transferable, one-per-person on-chain identity, which is what makes the
  board spam-resistant without accounts, passwords or a backend.
- **The traction metric, made visible** — the contract counts distinct holder
  addresses that have ever interacted (`uniqueInteractors`), so the board's
  adoption is auditable by anyone from chain data alone.

Agent ID contract (BNB Chain mainnet): `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`

## Safety & disclosures

- The contract **holds no funds**, takes **no fees**, has **no token**, and
  promises **no returns**. Users pay only BNB Chain network gas.
- There is **no owner** and there are **no admin functions**: no mint, tax,
  pause, freeze, upgrade or withdraw path exists in the contract. The Agent ID
  gate address is set once in the constructor and is immutable.
- Intents are public on-chain text that holders opt in to publish about their
  own agent identity. The board is not a tool for looking up other people.
- Contact between holders happens off-chain, holder to holder.

## Repository layout

- `src/AgentBoard.sol` — the board contract (Solidity ^0.8.20, no dependencies).
- `test/AgentBoard.t.sol` — Foundry tests (12 passing): holder gate, intent
  lifecycle, text limits, check-in streaks across days, vouch rules, unique
  interactor counting.
- `test/MockAgentId.sol` — `balanceOf`-only Agent ID stand-in for tests and
  BSC testnet (never used on mainnet).
- `script/Deploy.s.sol` — deployment script.
- `web/index.html` — the single-page dApp (connect wallet, holder check,
  post/update/deactivate intent, check-in, vouch, live board).

## Build & test

```bash
forge build
forge test
```

## Deploy

Testnet (deploys a MockAgentId and gates the board on it):

```bash
PRIVATE_KEY=<testnet key> DEPLOY_MOCK_AGENT_ID=1 \
  forge script script/Deploy.s.sol --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 --broadcast
```

Mainnet (gates on the real Agent ID contract by default; set
`AGENT_ID_ADDRESS` only to override):

```bash
PRIVATE_KEY=<deployer key> \
  forge script script/Deploy.s.sol --rpc-url https://bsc-dataseed.binance.org --broadcast
```

After deploying, verify the source on BscScan and set `BOARD_ADDRESS` in
`web/index.html`.

## Status

- 2026-11-25: contract + tests complete (12/12 passing); end-to-end dry run
  passed on a local chain (deploy → mint mock IDs → post → check-in → vouch →
  non-holder rejected) and the deploy script simulates cleanly against a BSC
  testnet fork.
- 2026-11-25: **DEPLOYED to BNB Chain mainnet** —
  AgentBoard `0x66D883a4261192ffBF16860c589351A593A8A747`
  (deploy tx `0x3a11e0a5360aba1a1b903e1b023750214a818da59128dc2ddc6546848fde4281`).
  Source verified on Sourcify (exact match, creation + runtime).
  First interaction from the founder's Agent ID wallet (fandybala24.ai):
  intent #0 posted (tx `0x26d5e01f940e54c2450bdc73e0ad2855386e530e3b7922ac7c039d239656885f`)
  and first check-in (tx `0x67f9d8d97b01818ed77e425e9eee1f1c8ec40135c66027aa157e7ec3bf872815`),
  uniqueInteractors = 1. Frontend points at the live contract.
- Next: project submission via the official hackathon announcement, then the
  traction window (≥30 unique Agent ID interactors) to 9 Dec 2026 08:00 UTC.
