# Everted Hand Swarm · $EHS

A build-free, multilingual static website in `site/`, its complete published export in `dist/`, and an immutable Ethereum launch token and Uniswap v4 reward hook in `src/`. The website is designed for **https://evertedhandswarm.si-md.xyz**. This delivery does not deploy contracts or publish the site.

## Preview and export

Node.js 22+ is sufficient. No frontend package installation or compilation is needed to serve the source or produce the export:

```sh
node scripts/preview.mjs site
# Open http://localhost:4173/preview/

npm run build
npm run preview
```

`build` copies `site/` into `dist/` and validates asset paths. Both directories contain plain HTML, CSS, ES modules, local WOFF2 fonts, the supplied logo, SVG illustrations, and six downloadable PNGs. Asset URLs are relative; navigation uses real section anchors. `404.html` is also exported. Configure a static host's missing-page redirect to that file when deploying under a subpath.

The preview server supplies an **empty development response** at `/simd-coin.json`. It does not invent a token, price, market cap, or volume. A generic file server without this endpoint shows the recoverable data-unavailable state. No fallback JSON is bundled because it could shadow the publisher's live endpoint.

## Live data and creator settings

The site requests `/simd-coin.json` on the origin immediately, every 30 seconds while visible, when returning to the page, and on Refresh. The publisher supplies `token`, `coinUrl`, `chartUrl`, `market.priceUsd`, `market.marketCap`, `market.volume24h`, and optionally `logo`. Invalid/missing values are hidden. A deployed token address enables copying; until then the address reads `launching…`. Buy opens the supplied coin URL or takes the visitor to the buying guide. Chart uses the supplied chart URL or the market section. Failed refreshes label retained values as last known data.

An HTTPS `logo` overrides the bundled hero image; a failed replacement falls back to the original. A DexScreener URL enables a consent-based iframe with `embed=1` and the current theme. Other chart providers remain ordinary links. The chart is not contacted before the visitor loads it. There is no wallet connection, analytics, tracking script, data collection form, or transaction signing on this site.

Official X and Telegram account URLs were not supplied. Set them in `site/config.js` (`community.x`, `community.telegram`) and rebuild, or provide the optional `socials.x` and `socials.telegram` fields in the live response. Unset accounts are clearly identified as pending; no handles are invented. Three localized X share intents, a Telegram share link, and Copy site link work independently of these settings. Share actions compose a message; they do not post automatically.

EN, ES, and Simplified Chinese cover content, controls, lore, image descriptions, and the error page. The original English meme captions are included in the downloadable artwork; translated captions accompany every image on the page. Theme defaults to the system preference. Only theme and language preferences are saved in localStorage. The sprout counter is local to the current page visit.

## Development checks

The lockfile pins development tools only. Keep their installation and browser downloads outside the repository:

```sh
mkdir -p /tmp/ehs-tooling
cp package.json package-lock.json /tmp/ehs-tooling/
npm ci --prefix /tmp/ehs-tooling --cache /tmp/ehs-npm-cache
PATH=/tmp/ehs-tooling/node_modules/.bin:$PATH npm run typecheck
npm test

PLAYWRIGHT_BROWSERS_PATH=/tmp/ehs-browsers /tmp/ehs-tooling/node_modules/.bin/playwright install chromium webkit
IMD_PLAYWRIGHT=/tmp/ehs-tooling/node_modules/playwright/index.mjs PLAYWRIGHT_BROWSERS_PATH=/tmp/ehs-browsers npm run test:browser
IMD_PLAYWRIGHT=/tmp/ehs-tooling/node_modules/playwright/index.mjs PLAYWRIGHT_BROWSERS_PATH=/tmp/ehs-browsers npm run test:browser:webkit
```

Browser system libraries may need installing on a fresh host. The validation script manages its own temporary HTTP server, serves the export at `/preview/`, and closes the server and browser. Add `-- --a11y` and set `IMD_AXE_PLAYWRIGHT` to the installed `@axe-core/playwright/dist/index.js` to run the WCAG scans. `-- --evidence` saves compact screenshots under `artifacts/screenshots/`; ordinary screenshots and detailed results go in disposable `test/scratch/browser/`.

The JavaScript typecheck uses TypeScript's `checkJs`, without generating files. Unit tests cover remote URL validation, missing/zero market values, chart URL construction, translation completeness, gradient-noise continuity, and exported asset integrity. Browser checks exercise launch/live/error states, settings persistence, three languages, keyboard controls, dragging, downloads, chart consent, and 200% text enlargement.

To regenerate the illustration assets (not required for a normal build):

```sh
python3 scripts/art.py
IMD_PLAYWRIGHT=/tmp/ehs-tooling/node_modules/playwright/index.mjs PLAYWRIGHT_BROWSERS_PATH=/tmp/ehs-browsers node scripts/render-art.mjs
npm run build
```

The generator draws SVG hand compositions based on the supplied logo; the renderer creates the six PNG downloads using a headless browser. The website itself never uses canvas or a 3D library.

## Launch contracts

`EHS` mints exactly **1,000,000,000 × 10¹⁸ units** to its deployer. It has no mint function after construction, transfer tax, owner, proxy, upgrade mechanism, or allocation logic. The launch factory handles the 90% IMD-paired liquidity allocation, 10% Merkle swarm distribution, and remainder. No owner or distribution address is needed by these contracts.

`EHSHook(IPoolManager manager, address token)` takes `$poolManager` and `$token` in `launch.json`. The Ethereum mainnet PoolManager is `0x000000000004444c5dc75cB358380D2e3dE08A90`. The immutable paired currency is IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, with 18 decimals. The hook accepts only this token pair, static fee **12500 (1.25%)**, and tick spacing **60**. It accepts the factory's chosen opening price; the manifest's Q96 price is provenance, not an enforced opening price.

The hook is deployed directly through CREATE2. Its low 14 address bits must be **0x20cc (8396)**: `beforeInitialize`, `beforeSwap`, `afterSwap`, `beforeSwapReturnDelta`, and `afterSwapReturnDelta`. The constructor validates these flags. Tests mine an actual salt and deploy the real bytecode rather than copying hook code to a convenient address. `HookHarness.setupPool` shows the salt-mining calculation. The launch deployer must mine against its actual CREATE2 deployer and constructor arguments.

The immutable economics are:

| Rule | Implementation |
| --- | --- |
| Hook fee | 2% of the absolute **filled IMD BalanceDelta**, rounded down to a wei |
| Pool LP fee | Static 1.25%, separate from the hook fee; no dynamic override |
| Qualifying buy | Actual incoming IMD is at least 10 whole IMD |
| Reward | 1% of filled IMD, rounded down, capped by accrued fees not already owed |
| Payment | `claimRewards()` for the caller; `payRecorded(beneficiary)` by anyone, always to that beneficiary |
| Accounting | `pending(address)`, `owedTotal()`, and `accruedBalance()`; all fee backing is held as PoolManager ERC-6909 IMD claims |

When IMD is the unspecified side, `afterSwap` charges the actual fill through its return delta. When IMD is specified, `beforeSwap` reserves `ceil(inputBudget / 51)` for exact input or `ceil(netOutput / 49)` for exact output. Reservations are capped to cover any representable int128 fill. `afterSwap` keeps exactly `floor(filledIMD / 50)` and mints the excess as an **ERC-6909 IMD claim to the calling swapper/router**. This includes price-limited partial fills and rounding dust. The router must account for/redeem these claims for its payer; it can burn them to offset settlement during the same unlock. Do not silently leave user refunds in a router that cannot use claims.

No IMD transfer or reward payout happens inside swap callbacks. Fees are minted as claims, so a newly seeded token-only pool can accept its first IMD buy without already holding IMD. Reward payment later unlocks the manager, burns the hook's claims and takes IMD to the recorded beneficiary. A failed token transfer reverts that claim payment and restores the debt; it does not create a swap callback dependency. ETH-receiving behavior is irrelevant because this launch pays IMD, not ETH.

### Recipient integration

Routers must supply **`abi.encode(outputRecipient)`** as hook data and send the swap output to that same address. V4's callback `sender` is the router; PoolManager does not expose the eventual `take` recipient to a hook. A direct swapper can omit context, in which case the calling swapper is the beneficiary. Empty, zero, noncanonical, or malformed context never blocks a swap and falls back to `sender`. Do not use a third-party router that omits recipient context if you expect end-user rewards: those rewards would be recorded to that router. The site explicitly mentions compatible routing.

There is no router allowlist, owner, setter, or reliance on `tx.origin`. A caller can designate the beneficiary of its own trade's newly earned reward; it cannot change a previous beneficiary or redirect a recorded payment. Each new reward is at most half the fee of that same buy, so choosing a beneficiary cannot consume someone else's recorded backing. The application trusts the selected router to deliver both swap output and recipient context correctly, as it already must trust its settlement behavior.

Configuration decisions: plain general-purpose immutable hook using v4-core interfaces, no base-contract dependency, no pause, no shares, no access role, no transient cross-callback state, internal currency helpers, bounded manual casts, and ERC-6909 mint/burn settlement. Only the five declared callbacks/delta flags are enabled.

## Foundry verification

Every import resolves to a committed file under `lib/`. Foundry is pinned to solc **0.8.26**, Cancun, optimizer 200 runs, via IR, and `bytecode_hash = "none"`. Build/cache output lives in disposable `test/scratch/`; there are no submodules or network imports.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xc47023846ff69d1d508a9d1527ec38306c24c871803ceb96f19522d1a5e085df forge test

# Optional network fork; default offline test run skips this suite cleanly.
EHS_MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com EHS_FORK_BLOCK=26197826 FOUNDRY_FUZZ_SEED=0xc47023846ff69d1d508a9d1527ec38306c24c871803ceb96f19522d1a5e085df forge test --match-contract EHSMainnetForkTest -vv
```

Actual worker results on 2026-10-15: **42 Foundry tests passed, 0 failed; the optional fork suite skipped without a URL**. Three fuzz tests ran 1,000 cases each; two inherited reverse-order fuzz tests ran 256 cases each. A separate mainnet-fork run passed **both tests** at block **26,197,826**, against the real manager and IMD contract. Both currency orders, all four swap modes, all four price-limited partial-fill cases, reward claims, payment failure/reentry, permission bits, opcode restrictions, threshold behavior, and factory fee collection are covered locally.

`EHSHook` is 4,146 runtime bytes and 4,857 creation-code bytes (4,921 including its two constructor arguments), within EIP-170 and EIP-3860. `EHS` is 1,153 runtime bytes. No contracts were broadcast. The protected verifier harness was read; this is not a claim that the external protected suite or an independent security audit ran.

The production export, JavaScript typecheck, six Node tests, Chromium and WebKit interaction validation, and light/dark axe WCAG A/AA scans passed. The pinned taste probe's intentional brand exceptions and its offline API limitation are recorded in [artifacts/validation.md](artifacts/validation.md). Native screen-reader and physical-device testing were not performed. See [DESIGN.md](DESIGN.md), [artifacts/security-review.md](artifacts/security-review.md), and [artifacts/brief-coverage.md](artifacts/brief-coverage.md) for implementation details, review coverage, and remaining integration responsibilities.

The single `.gitignore` has an explicit **512-byte path budget**. It includes `dist/` and `artifacts/` despite inherited ignore rules and excludes dependency/cache directories at every nesting level, plus disposable `test/scratch/`. Development packages and browser runtimes were installed outside the repository; generated dependency directories are excluded and never submitted. The submission check inventories all deliverable files and rejects tracked caches, archives, submodules, and a payload above the 8 MiB budget.
