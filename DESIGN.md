# Everted Hand Swarm design system

## Overview

The site presents an Ethereum meme-token launch as a strange anatomical broadside: blackletter headlines, branching muscle-red hands, bone-colored paper, a star-ring seal, and an interactive swarm. The supplied logo remains the hero image. Original SVG redraws carry its branching fingers and tendon lines into the three story scenes, buying guide, anatomy diagram, social artwork, and six distinct meme compositions.

The home page has nine sections in reading order: landing, three story beats, market pulse/chart, buying guide, tokenomics, meme wall, and community. The required creative copy remains intact, with explicit factual clarification beside the “0% tax” wording. Large artwork and quiet body spacing keep the maximalist theme readable. There are no decorative dashboards, fake balances, or invented account links.

The authoritative source is `site/`. `dist/` is an exact static copy. Shared styles live in `site/styles.css`; behavior is divided between `app.js`, `swarm.js`, `data.js`, and `translations.js`. There is no component framework or runtime package dependency.

## Colors

All values are sRGB hex tokens in `site/styles.css`:

| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| `--bg` | `#e7e1df` | `#0c0c0c` | Page and sticky header |
| `--surface` | `#f5f0ec` | `#171414` | Market section and control hover |
| `--ink` | `#211b1a` | `#e7e1df` | Main text and control outlines |
| `--muted` | `#625854` | `#b9aaa5` | Supporting text and data labels |
| `--line` | `#b4a6a0` | `#4e3b38` | Structural dividers |
| `--accent` | `#a23c36` | `#a23c36` | Specified brand red: primary actions, ticker, anatomy section |
| `--accent-text` | `#a23c36` | `#cc857b` | Red heading text and text-link hover, with extra dark-mode contrast |
| `--accent-hover` | `#862e29` | `#b54a43` | Primary button hover |
| `--on-accent` | `#ffffff` | `#ffffff` | Primary button label |
| `--focus` | `#211b1a` | `#ffffff` | 3px keyboard focus outline |
| `--art-bg` / `--art-ink` | `#0c0c0c` / `#e7e1df` | Same | Fixed-color logo/meme artwork |

The red anatomy section overrides supporting text to `#f0d7d4`, borders to `#c87d76`, and focus to white. A restrained 2.5%-opacity SVG-noise overlay and a halftone dot field provide texture. They do not carry information. Status always includes text; the colored dot is decorative.

Measured solid-token contrast: light body 13.13:1; light supporting text 5.33:1; dark body 15.12:1; dark supporting text 8.72:1; white on brand red 6.49:1; pale anatomy copy on red 4.75:1. The original brand red was only 3.01:1 against the dark background, so text now uses the lighter `--accent-text` token. Browser axe scans cover both themes; textured/artwork areas and symbol-only controls were also visually reviewed. These measurements do not claim a pixel-by-pixel image contrast audit.

## Typography

Local fonts, originally from Google Fonts:

- **UnifrakturCook 700** (`assets/unifraktur.woff2`): main headings, wordmark, section headings. Fallback: Georgia, Noto Serif CJK SC, serif.
- **IBM Plex Mono 400 / 600** (`assets/plex-regular.woff2`, `assets/plex-semibold.woff2`): prose, controls, labels, addresses, and numbers. Fallback: Noto Sans CJK SC, monospace. The monospaced body is an explicit creative-brief choice.
- Simplified Chinese uses available system CJK glyphs. Chinese headings use 1.35 line-height and normal tracking. This delivery does not bundle a multi-megabyte CJK font.

One six-step scale is used:

| Role | Desktop | At 640px and below |
| --- | --- | --- |
| `--text-sm` | 14px | 14px |
| `--text-body` | 16px | 16px |
| `--text-label` | 20px | 20px |
| `--text-card` | 32px | 28px |
| `--text-title` | 64px | 40px |
| `--text-hero` | 104px | 52px |

At 1150px the title/hero steps become 48px/80px. At 920px the hero uses the title step until the mobile rule takes over. Weights are 400, 600 and 700. Body line-height is 1.65; standard headings 1.08; story headings 1.15; component headings 1.4. Hero tracking is −0.035em, section headings −0.025em, and body tracking is normal. Prose has bounded measures; headings balance; dynamic numbers use tabular numerals. Full addresses wrap and remain selectable rather than being truncated.

The required seven-word English headline, creative em dashes, and ticker are preserved even where the generic critic's house rules prefer alternatives.

## Layout

The spacing system uses an 8px base. Root spacing tokens are 8, 16, 24, 32, 48, 80 and 112px; section-specific 56, 64 and 96px values stay on that base. Desktop content aligns to a 1320px maximum content width. Gutters are at least 32px on desktop and 20px at 640px and below.

- Above 1150px: large two-column hero, three story columns, two-column guide and anatomy, three-column meme wall.
- Below 920px: mobile navigation disclosure, story sections become illustration/text rows, meme wall becomes two columns.
- Below 640px: single-column hero, story, guide, anatomy and meme wall; market values become label/value rows. The anatomical diagram stops sticking. The primary Buy/Chart actions remain before the hero artwork.
- Above 1600px: the hero expands its gap and minimum height, while content edges remain constrained.

The header is sticky with anchor scroll clearance. It wraps at large text sizes instead of pushing controls off-screen. Section heading rows also wrap; the supply number may break across lines at 200% text size. Containers grow with translations. The diagram and media reserve their geometry through dimensions/aspect ratios. Guide panels use minimum height to reduce stepping shifts without clipping longer copy.

Observed in Chromium and WebKit at 320, 375, 390, 768, 1440 and 1920px in all three languages, with no page overflow. The product and Buy action are visible on the initial 390×844 screen. 200% CSS text enlargement also reflows without horizontal overflow. This is distinct from an unperformed native-browser zoom test.

## Elevation & Depth

The design is flat: borders organize controls and sections; there are no box shadows or card-inside-card stacks. Artwork uses light outlines, orbital ellipses, halftone dots, and angled stamps. The grain layer is noninteractive. The sticky header sits at z-index 30, the grain at 20, and short-lived confetti at 50. Hero layers are isolated to their own stacking context.

## Shapes

Primary/secondary buttons use `--pill: 999px`, with 1.5px outlines and a 52px minimum height. Icon controls are at least 44×44px. The hand seal is circular; the hero stage has rounded arch-like upper corners and small lower corners. The two circular stamps are slightly rotated. Meme tiles have thin outlines and alternate small rotations on desktop; the rotations are removed on mobile. The SVG scenes are decorative compositions rather than nested UI cards.

## Components

| Pattern | Source | Behavior |
| --- | --- | --- |
| `.button`, `.primary`, `.text-button`, `.icon-button` | `styles.css` | Real links for destinations, buttons for actions; hover, active, keyboard focus, and disabled states. Press scale is 0.96 only when motion is allowed. |
| Sticky header and `#navigation` | `index.html`, `app.js` | Brand left, settings right; mobile disclosure exposes `aria-expanded`, closes on selection, outside click or Escape; Escape restores menu-button focus. |
| `#playground`, `#logo-sticker` | `swarm.js` | SVG hands drift along bounded 2D gradient-noise paths; hover inverts a hand, click sprouts one with a lore bite/ripple. Sprout is also a native button. Seal supports pointer dragging, arrow-key movement and Home to recenter. 28-hand cap prevents unbounded DOM growth. Reset clears the visit count and positions. |
| Motion control | `swarm.js`, `styles.css` | Pauses the ticker, breathing seal and SVG motion. System reduced motion disables animation and the resume control; interactions retain static results. Hidden/out-of-view playgrounds stop their JS animation loop. |
| `#stats`, `#chart-panel` | `app.js`, `data.js` | Missing values are hidden. Values animate over 500ms only when motion is enabled. Failed refreshes show a retry and label stale values. DexScreener is embedded only after explicit Load chart; other hosts remain links. |
| Three-step buying guide | `index.html`, `app.js` | Accessible tabs with roving focus, Left/Right/Home/End keys, labeled panels, and a next-step cycle. Contract copying is disabled while launching. Failed clipboard access leaves selectable text and recovery instructions. |
| `.anatomy-facts` | `index.html` | One supply/distribution/fee block, with separate reward explanation. Transfer tax is distinguished from pool/hook fees. |
| `.meme-grid` | `index.html`, `assets/` | Six distinct SVG compositions, localized descriptions/captions, real PNG download links; slight hover straightening on desktop. Downloaded originals retain the final English captions. |
| Community/share links | `config.js`, `app.js` | Official account destinations appear only when configured. Three X intents, Telegram sharing and Copy site link work before launch. |
| Error page | `404.html`, `error.js` | Same fonts, colors, appearance/language preferences, supplied visual vocabulary, and a real return link. |

All repeated UI copy is checked for translation coverage. `lang` changes to `en`, `es`, or `zh-CN`. Dynamic statuses use stable live regions. No custom modal or wallet UI is present.

## Do's and Don'ts

- Start new content with `.section-shell`, the existing heading scale, and the same shared alignment edges.
- Keep the specified red for fills and artwork; use `--accent-text` for small interactive text or large red headings on dark backgrounds.
- Preserve the distinction between a **0% token transfer tax**, **1.25% LP fee**, and **2% IMD hook fee**.
- Add both Spanish and Chinese strings and image descriptions when adding interface copy.
- Keep real data absent until supplied. Never substitute sample prices, pretend addresses, or guessed community handles.
- Use the supplied logo or its anatomical hand vocabulary, not unrelated stock art or mascots.
- Keep control shapes and focus states visible in both themes. Never clip addresses or suppress reduced-motion behavior.
- For another static page, reuse the shared stylesheet, relative asset paths, theme bootstrap, meta tags and page return links; export the page as its own folder with an `index.html` when it represents a route.

Design/review method: pinned Better Interface (Jakub Krehel, MIT), with the documentation method adapted from Impeccable (Paul Bakaus, Apache-2.0). License notices are retained in `artifacts/licenses/better-interface.txt`.
