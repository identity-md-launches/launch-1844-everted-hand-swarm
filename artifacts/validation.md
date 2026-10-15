# Validation record

Worker validation completed on 2026-10-15. These are reproducible worker observations, not an independent audit or a claim that the external admission harness ran.

## Build and functional checks

| Check | Actual result |
| --- | --- |
| `npm run build` | Passed. Copied 32 runtime files from `site/` to `dist/`; relative assets validated. No bundler or compilation is required to use `site/`. |
| `PATH=/tmp/ehs-tools/node_modules/.bin:$PATH npm run typecheck` | Passed, TypeScript 5.9.3 `checkJs`, no emitted files. |
| `npm test` | Six Node tests passed, zero failed. URL/address handling, missing/zero values, chart URLs, translation coverage, noise continuity, and local assets. |
| `node scripts/validate-browser.mjs --a11y --evidence` | 18 Chromium check groups passed. Actual Chromium 141 through Playwright 1.56.1; external tool installation. |
| `node scripts/validate-browser.mjs --webkit` | 17 WebKit check groups passed. Actual WebKit 27.2 through Playwright 1.64.1; external browser/system libraries. |
| axe WCAG A/AA | Zero violations in Chromium, light and dark, 375px and 1440px. Remaining automatic-review items concern contrast of non-text symbol glyphs; inspected visually. |
| `forge build --sizes` | Passed with solc 0.8.26, Cancun, optimizer, via IR, metadata hash disabled. Both deployment bytecodes have empty link references. |
| Seeded `forge test` | 42 passed, zero failed, one skipped suite setup (optional mainnet fork without an RPC URL). |
| Mainnet-fork suite | Two passed, zero failed at Ethereum block 26,197,826 against the real PoolManager and IMD. No broadcast. |
| `node scripts/check-submission.mjs` | Full source/export hash comparison, prohibited-artifact checks and conservative byte budget; see `submission-inventory.json` for exact final totals. |

Foundry seed: `0xc47023846ff69d1d508a9d1527ec38306c24c871803ceb96f19522d1a5e085df`. Three fuzz functions ran 1,000 cases each, and two inherited reverse-order fuzz functions ran 256 cases each. The stateful sequence function checks solvency across twelve trades and interleaved claims per case.

The fork invocation used `EHS_MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com EHS_FORK_BLOCK=26197826` and `--match-contract EHSMainnetForkTest -vv`, with the same seed. The endpoint reported chain 1; the supplied IMD address had code and returned symbol `IMD`. Fork fixtures fund test accounts through Foundry; they are not production addresses or sample market data.

Raw compact results are retained in `checks/`. Screenshots of the actual export are in `screenshots/`. Browser tests serve the committed export under `/preview/`, exercising subpath-relative assets. They supply an empty development API, then explicit controlled live/error responses. The known IMD address is used only as an address-formatting fixture inside tests; no EHS address is shipped.

Packaging review also found inherited ignore rules hiding `artifacts/`. The final `.gitignore` has an explicit 512-byte budget (actual size 220 bytes), includes delivery reports and the static export, and excludes generated dependency/cache directories at every level. Every inventoried deliverable was checked with `git check-ignore` and is eligible for submission. No Git metadata or protected dependency-directory contents were changed by that check.

## Pinned design probe

The required command ran against the finished export:

```sh
IMD_PLAYWRIGHT=/tmp/ehs-tools/node_modules/playwright/index.mjs \
PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64 \
PLAYWRIGHT_BROWSERS_PATH=/tmp/ehs-browsers \
node .imd/reads/skills/design-critic/scripts/taste.mjs --out test/scratch/taste
```

Result: **12 of 16 passed**. Its built-in static server cannot supply the required origin-level `/simd-coin.json`, so `render` reports that single 404. The page recovers visibly; it does not invent market values. Bundling a dummy endpoint would shadow the publisher's live service.

The same probe also ran against `node scripts/preview.mjs dist 4182`, which supplies the documented empty API response, using `http://127.0.0.1:4182/preview/ --out test/scratch/taste-preview`. Result: **13 of 16 passed**, including render with no missing files or script errors. The three remaining flags are deliberate applications of the more specific creative brief:

| Probe flag | Disposition |
| --- | --- |
| `type-faces`: monospaced prose | Retained IBM Plex Mono, explicitly required for text. Only two families and three weights are used. |
| `glyphs`: two em dashes | Retained in the supplied final hero/story copy, which must remain word for word. |
| `repetition`: scrolling ticker | Retained the requested `$EHS` marquee and final tagline. It is decorative, hidden from assistive technology, pausable, and static with reduced motion. |

Layout, target sizing, measured solid-color contrast, casing, tracking, heading labels, six-size scale, slogan count, first-screen copy budget, UI depth, reduced motion and sharing metadata passed. At 390px the probe measured 43 prose words on the first screen; at 1440px, 75. All 29 controls were at least 24px or sufficiently separated; one inline footer link is under 44px. Seven text boxes over artwork/textures were outside the probe's contrast measurement. Those areas were inspected, but this is not a pixel-by-pixel contrast certification.

## Better Interface review: all six domains

Applied the pinned workflow and core principles while building, then reviewed the rendered export. References were read as task-provided design knowledge. The implementation and documentation retain its license notice.

| Domain | Source review | Rendered/interaction review | Outcome |
| --- | --- | --- | --- |
| Accessibility | Semantic landmarks, one H1, heading order, native actions, labeled controls, alt text, live statuses, reduced-motion and keyboard paths. | axe light/dark at 375/1440; tab navigation, mobile disclosure/Escape, buy-guide arrows/Home/End, keyboard sprouting, seal arrows/Home, pause/reset and contrast. | No axe violations. Visible focus and usable controls observed. Native screen-reader testing remains unperformed. |
| Layout | Shared shell, grid breakpoints, min-width constraints, wrapping addresses, reserved media geometry and sticky-anchor clearance. | All three languages at 320/375/390/768/1440/1920; 200% CSS text enlargement; both pages at 375/1440; first-screen screenshots. | No horizontal overflow. Name/product and Buy action visible at 390×844. Native zoom and physical devices remain untested. |
| Writing | Final creative copy preserved; plain product line; task-specific button labels; helpful prelaunch, outage and clipboard states; no invented figures or handles. | Read the rendered launch/error/live states and translated guide/social labels. | Transfer tax distinguished from actual swap fees. Three required brand-language exceptions recorded above. Translations have not had independent native-speaker review. |
| Typography | Local display/body fonts, six sizes, three weights, bounded measures, tabular market figures and system CJK fallbacks. | Probe confirms six sizes at 390/1440; long Chinese/Spanish copy and enlarged text reflow. | No clipping observed. CJK glyph appearance depends on installed system fonts. |
| Colors | Theme tokens, non-color status labels, focus contrast and measured solid-color pairs. | Light/dark screenshots and axe; manually reviewed textured art areas and icon controls. | Adjusted dark text accent for headroom. Full color-vision simulation and per-pixel image contrast not performed. |
| UI | Link/action semantics, real downloads, disabled copy before launch, chart consent, data retry, accessible tabs and bounded decorative swarm. | Live values including zero, supplied logo, Buy/Chart URLs, three X intents, Telegram sharing, copy, stale-data retention, six PNGs, pointer/keyboard controls and settings persistence. | All browser check groups passed. External destinations and embedded chart service were validated as URLs/requests with controlled responses, not third-party transactions. |

## Findings repaired

Line references identify the final source locations that implement the fixes, not an earlier failing revision.

| Finding | Final implementation | Verification |
| --- | --- | --- |
| Header and large supply value could overflow at 200% text size. | `site/styles.css:1432` wraps header/section rows and permits long values to break. | Chromium and WebKit enlarged-text check passed at 390px. |
| Brand red against the dark background was only 3.01:1, too close to the large-text threshold and unsuitable for smaller interactive text. | `site/styles.css:1447` adds theme-specific `--accent-text`; brand fill remains unchanged. | Solid token calculations, taste contrast and axe passed. |
| Interactive hero container had an unsuitable ARIA role for its label. | `site/index.html:61` uses a labeled group around native controls. | No `aria-prohibited-attr` violation in final axe scans. |
| Reduced-motion users could see an enabled resume control that could not start motion. | `site/swarm.js:148` applies the system preference and disables/relabels that control. | Reduced-motion interaction checks passed in both engines. |
| The first story hand and a hero stamp crowded/clipped their illustration bounds. | `scripts/art.py` repositions the scene; `site/styles.css` positions the stamp inside its stage. | Final images decoded and screenshots inspected at mobile/desktop. |
| An anatomy label collided with the hand at small sizes. | `site/index.html:114` moves the transfer-tax callout above the illustration with its own leader. | Final mobile/desktop views inspected. |
| The original brief's bare “0% tax” could misrepresent swap costs. | `site/index.html:115`, `site/translations.js`, and meme-2 PNG explicitly distinguish transfer tax from 2% hook + 1.25% pool fees. | Content review and translation-coverage tests. |
| Preview missing files could attempt to send headers twice. | `scripts/preview.mjs` reads before sending a successful status. | Both pages and missing-page behavior render without script/resource failures in the controlled preview. |

## Limits and handoff

Official X and Telegram URLs remain creator-settable because none were provided. Their slots disclose that state; share controls are functional. Production live data and a deployed EHS token were not yet available. Real market values, third-party chart rendering, transaction routes, deployment and publishing are outside this delivery. No account credentials are required by the static site.

The browser MCP executable was unavailable; actual rendering was performed with installed Playwright Chromium and WebKit instead. Clipboard success was tested with a browser API substitute, and downloads with real local files; OS clipboard permissions and a physical mobile wallet were not tested. No wallet flow belongs on this site.

The protected admission tests were read and their invariants mirrored where applicable; their external environment was not run. Slither and an independent audit were not run. See `security-review.md` for concrete accounting analysis and router integration requirements.
