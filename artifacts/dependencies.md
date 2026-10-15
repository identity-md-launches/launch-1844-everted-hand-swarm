# Dependency and asset provenance

Runtime website dependencies are local assets only. No remote font, JavaScript CDN, analytics or wallet package is required. `/simd-coin.json` is the publisher's runtime data service; the optional chart iframe is the sole embedded third-party service and is loaded on request.

| Material | Version/source | Included scope and license |
| --- | --- | --- |
| Uniswap v4-core | [46c6834698c48bc4a463a86d8420f4eb1d7f3b75](https://github.com/Uniswap/v4-core/tree/46c6834698c48bc4a463a86d8420f4eb1d7f3b75) | `lib/v4-core/src` without unused upstream test helpers; upstream LICENSE and per-file SPDX retained. PoolManager is used in tests, interface/internal-library code by the hook. |
| Foundry forge-std | [v1.9.7 / 77041d2ce690e692d6e03cc812b57d1ddaa4d505](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | Test sources, MIT/Apache notices in `lib/forge-std`. |
| Solmate | [89365b880c4f3c786bdd453d4b8e8fe410344a69](https://github.com/transmissions11/solmate/tree/89365b880c4f3c786bdd453d4b8e8fe410344a69) | Only `Owned.sol`, needed by the real PoolManager test dependency, plus upstream license. EHS and EHSHook do not inherit ownership. |
| UnifrakturCook | `@fontsource/unifrakturcook` 5.2.6, Google Fonts | Local Latin 700 WOFF2; OFL notice beside assets. |
| IBM Plex Mono | `@fontsource/ibm-plex-mono` 5.2.7, Google Fonts | Local Latin 400/600 WOFF2; OFL notice beside assets. |
| Original EHS logo | [Requester-supplied JPG](https://fxumiqjngmabtgvruvka.supabase.co/storage/v1/object/public/forum-attachments/posts/mv9gfo9j-hzbbwl.jpg) | Original 1024px image in `site/assets/logo.jpg`; used as authorized task artwork, no ownership claim. |
| Derived hand illustrations and meme compositions | `scripts/art.py` | Original SVG compositions derived from the supplied logo's anatomical vocabulary; PNGs rendered by `scripts/render-art.mjs`. |
| Better Interface guidance | Pinned task input; Jakub Krehel, with Impeccable documentation method | License retained in `licenses/better-interface.txt`. |
| Uniswap v4 security guidance | Pinned task input | License retained in `licenses/uniswap-v4-security.txt`. |
| Ethereum testing guidance | Pinned task input | License retained in `licenses/eth-testing.txt`. |

`package-lock.json` pins development-only TypeScript 5.9.3, Playwright 1.64.1 and axe Playwright 4.10.2 and their integrity hashes. No dependency installation, package-manager cache, registry mirror, archive or browser executable is included. The worker also used an external Playwright 1.56.1 installation for Chromium 141 compatibility; the WebKit run used the lockfile's Playwright version. No dependency is a Git submodule. All Solidity imports are ordinary committed source paths and all library calls needed by deployment are linked internally.
