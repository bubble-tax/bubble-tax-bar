# Bubble Tax landing page

Static English landing page, published from [bubble-tax/bubble-tax.github.io](https://github.com/bubble-tax/bubble-tax.github.io). The app repository keeps the canonical source in `site/`; it does not run a Pages deployment workflow.

The product tour leads with paired five-hour/weekly quota comparisons, then task allocation, reservations, forecasts, usage patterns and plan review. Allocation captures keep feature tabs above a separate row of account, task or log-source filters. Model labels refer to usage recorded in code logs. The hero offers menu-bar and MacBook-notch previews. Theme changes swap native light/dark captures as well as page colors.

## Screenshots

Use the native app with isolated `--demo-data`, `--hide-demo-badge`, and `--appearance-light` / `--appearance-dark`. Fixtures must contain fictional accounts and logs. Capture the relevant view, crop the popover arrow and outer transparent padding, and keep public “sample data” captions. Never publish screenshots from real account state.

Reservations are planning targets, forecasts are estimates, and model usage comes from saved code logs and does not establish account-wide quota attribution. Do not describe suggestions as automatic task execution or quotas as transferable.

## Configuration

`config.js` supplies the release download, repository, support destination and host-specific GA4 web streams:

| Host | Measurement ID |
| --- | --- |
| `bubble-tax.github.io` | `G-RDQQMG2P3P` |
| `bubble-tax.workromancer.ai` | `G-ZGTF5YBTDW` |

`analytics.js` loads only the current host’s stream. Local preview, unknown hosts and browsers with Global Privacy Control enabled do not load Google Analytics. Advertising signals are disabled. Events are page views, `download_click`, `homebrew_copy_click` (the click, not guaranteed clipboard success), and `feature_view`. App logs, account data, prompts and quota records are not included. Automatic enhanced measurement can also be configured in the GA4 property.

The custom hostname is served by a Cloudflare Worker from the same Pages origin, keeping both public addresses accessible. See [the custom-host configuration](https://github.com/bubble-tax/bubble-tax-bar/tree/main/deploy/cloudflare) for its source and routing.

## Publishing

Copy the static source and assets to the website repository, commit and push its main branch. Update script query hashes when changing JavaScript or CSS. Verify the live tour, theme pairs, menu/notch previews, download and Homebrew command after the Pages build succeeds.

The app and its collectors ship together; visitors do not need Python or a local server to use the app. The current download is Developer ID signed and Apple notarized.

## Share metadata

Canonical and Open Graph URLs use `https://bubble-tax.github.io/`. The share image is `assets/bubble-tax-og.png` (1200×630). Regenerate the existing monochrome character and native typography with `swift scripts/render-og.swift` from the app repository root.
