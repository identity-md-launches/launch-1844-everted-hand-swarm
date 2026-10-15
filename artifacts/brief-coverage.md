# Brief coverage

Read the full site brief before implementation from [the supplied endpoint](https://www.si-md.xyz/api/chat?op=site-brief&label=evertedhandswarm), JSON field `brief`. Retrieved response SHA-256: `32364850d21c2f1ab2f667ed2879931b2f98e672466ee0795b0487ef51af1f77`. The specific creative copy, palette, fonts and technical constraints take precedence over the broader maximalist summary.

| Requested feature | Delivered |
| --- | --- |
| Plain static source and export | `site/index.html`, CSS and native JS modules; identical complete `dist/` export. The build command only validates/copies files. |
| Coin-specific visual identity | Original hero JPG, hand-derived SVG poses, blackletter display, monospaced body, black/bone/anatomical-red palette, halftone/grain, circular angled stamps and `$EHS` marquee. |
| Hero and primary actions | Exact final headline and paragraph, plain Ethereum meme-coin line, Buy/Chart links, launch state, supplied logo. Buy appears on the first 390px screen. |
| Three-beat story | Three separate sections with the final supplied headings/paragraphs and unique flipped/spore, spiral and inverted-Ethereum SVG scenes. |
| Signature interaction | Bounded Perlin-noise SVG hand swarm, hover color inversion, sprout/ripple/lore on click, visit counter, draggable logo seal, keyboard alternatives, pause/reset. |
| Subtle motion | Small breathing/hover effects, restrained Buy confetti, bounded slow drift; no canvas or 3D. Reduced motion gives static outcomes and disables animation. |
| Live stats and chart | Required same-origin JSON request; refresh every 30 visible seconds; animated actual numeric values; missing values hidden; retained values labeled after an outage. DexScreener iframe after explicit load, with embed/theme parameters, plus direct fallback link. |
| Guide | One three-step interactive tabbed guide, exact supplied step headings, explanatory safety/route copy and contract-copy control. |
| Tokenomics | One anatomy section with 1B fixed supply, 90/10 allocation, no dev allocation, transfer tax, actual LP/hook fees and claimable buyer reward mechanics. |
| Meme wall | Six distinct hand compositions matching the six concepts, exact English captions, localized on-page translations, all six real PNG downloads. The transfer-tax meme also discloses swap fees. |
| Community and sharing | Configurable official X/Telegram URLs, honest pending state, three localized X intents, Telegram sharing, Copy site link and the final meta-hook sentence. |
| Themes and languages | System-default light/dark toggle; EN/ES/简体中文; both saved locally; translated copy, status/error text, controls and image descriptions. |
| Navigation and responsiveness | Sticky anchor navigation, mobile disclosure, 320–1920px tested, no overflow in any language, keyboard focus and skip link. |
| Metadata and error page | Title, description, canonical, OG/title/description/logo, Twitter large-image card, logo favicon, styled translated `404.html`. |
| Privacy and launch truth | No forms, wallet connection, trackers, promises of returns, fabricated addresses/prices or partnership claims. Only creator preference storage; chart service connects on demand. |
| Footer | Required Identity.md / si-md.xyz launchpad / not-financial-advice text; equivalent translations. |
| Documentation and checks | Root README and DESIGN, six-domain review, two real browser engines, production export/typecheck, Foundry unit/fuzz/fork tests, byte inventory. |

The required live-data section sits after the three story beats and before the buying guide. This preserves all eight creative sections in their specified relative order while accommodating the explicit live-stats requirement (nine sections total). The headline is seven words because it is final supplied copy; the generic six-word rule yields to it.

The brief's bare “Tax: 0%” is retained and explicitly qualified as **token transfer tax**. Actual swaps pay the mandatory separate 1.25% pool fee and 2% IMD hook fee. The mechanical specification takes precedence over any inference of fee-free swaps. The canvas-like meme wall is implemented with CSS/SVG, honoring the explicit no-canvas rendering option.

The full supplied logo remains the hero image, accompanied by isolated hand-derived SVGs; it is not replaced with a guessed brand asset. A live HTTPS `logo` field takes precedence with a local error fallback. Downloaded meme artwork retains English captions as original visual work, while localized captions and descriptions are provided alongside it.

Official community account URLs are the only unavailable creator values. They are optional owner-settable settings in `site/config.js`, as allowed by the task, rather than guessed accounts. The contract address, Buy URL and chart destination arrive at runtime from the publisher. No placeholder token address is used.

Contract delivery follows the task's explicit mandatory launch requirements: EHS, EHSHook, reproducible Foundry project, committed imports, CREATE2 permission validation, exact manifest shape and fee accounting. The reference's contrary suggestion not to write a manifest was treated as background; the requested `launch.json` is included. No hosting command, factory call, signing operation or contract broadcast was performed.
