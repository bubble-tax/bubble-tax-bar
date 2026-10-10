# Bubble Tax †

Pi coding-agent session activity is supported through Connections → Pi coding agent. Connect `~/.pi/agent/sessions` or choose a custom session directory. Recorded tokens appear by provider in Connections and the matching service's Details. They remain separate from provider-reported quota and cancellation evidence: a local model/provider label cannot prove whether an API key, subscription or extra-usage balance paid for a request. No Pi credentials or conversation contents are stored or transmitted.

Your AI subscriptions. Roasted.

An English-only macOS menu bar app that helps people cancel or downgrade AI subscriptions that are oversized for their actual usage. Click **†** in the menu bar. There is no launch dashboard and no Dock icon.

## What it does

The static English landing page lives in [site/](site/README.md), with native macOS demo captures, monochrome persona artwork, a six-screen feature tour, FAQ and configurable download/support links. Preview with `python3 -m http.server 8765 --directory site --bind 127.0.0.1`. GitHub Pages deployment is prepared in `.github/workflows/pages.yml`; destinations in `site/config.js` must be filled before publication.

- Compares ChatGPT/Codex, Claude, Cursor, GitHub Copilot and Antigravity in compact service pages.
- Puts **Left** first and shows short-window and weekly limits together without adding them up.
- Records near-reset balances to identify headroom repeatedly left unused in expired windows.
- Uses existing service authentication for usage queries, with local Claude/Codex logs as a fallback.
- Pairs public monthly list-price estimates with usage receipts, English roast bubbles and subscription review links.
- Treats free, personal and organization-managed plans separately. Missing, stale or incomplete evidence gets no cancellation verdict.

The goal is to spend less on unnecessary subscriptions, not to consume extra tokens to justify a bill. An open window's remaining quota is not expired waste. Frequent use is evidence of activity, not proof that a paid tier is worth its price. Server plan labels and public list prices are not actual invoices; local logs may omit web, mobile and other-device usage. No plan, price or renewal-date input is required. The “send me the money” line is a joke, with no payment flow.

## Run on macOS

Requires macOS 13+, Swift 5.9+ and Python 3.9+. No external packages.

```bash
bash scripts/run.command
```

Builds and tests the app, then opens `dist/Bubble Tax.app`. Click **†** in your menu bar; gear opens Connections. You can also reopen the app to reveal the popover.

Default folder locations:

- Claude Code: `~/.claude/projects`
- Codex: `~/.codex/sessions`

The build uses a local ad-hoc signature, not Developer ID distribution signing or notarization.

## Local data

`~/Library/Application Support/BubbleTaxBar/state.json`, permissions 0600. Existing subscription records remain compatible with the storage model; the menu focuses on remaining quota, observed unused history and renewal value. The original cost/renewal assessment engine remains in BubbleTaxBarCore.

## Verification

The build script runs Python collector and Swift core tests. Coverage includes quota windows, missing/stale receipts, pricing, personas, roast evidence and old-state decoding. Check the menu bar popover and Connections on a Mac after building.

Original conversation and local work history: [LOCAL_HANDOFF.md](docs/LOCAL_HANDOFF.md).

## Quota expiry

Live provider queries and supported local rate-limit snapshots supply used percentages, durations and reset timestamps. The menu shows current **Left** and the average last observed unused balance of eligible windows that expired in the past 30 days. Only account-identified observations within 15 minutes of reset qualify for expired-window estimates; usage after that observation is unknown. Missing periods are excluded. Short-window, weekly and monthly limits stay separate.

Repeated unused headroom supports a cancellation or downgrade review, surfaced as **Review** on the service strip. Work plans use **Review seat**. Both the persona and service roast use the widest reported budget; missing weekly history cannot inherit short-window history. **Early read** means incomplete coverage or fewer than three eligible windows for any represented plan. A quiet short window does not override an actively used weekly budget: 34% weekly remaining means 66% used, not a token-wasting verdict. Local transcript token counts have no subscription quota denominator.

**Details** provides activity and receipts. **Cancel options…** opens the provider's official cancellation instructions; billing changes are completed by the user with the provider. A connected CLI does not establish that a paid subscription exists. Public price sources and caveats are in [PRICE_CATALOG.md](docs/PRICE_CATALOG.md).

## Live subscriptions and work plans

Supported collector IDs: ChatGPT/Codex, Claude, Cursor, GitHub Copilot and Antigravity. Google service usage is shown through Antigravity; the separate Gemini collector is no longer enabled. The bundled MIT-licensed CodexBarCLI v0.73.0 performs provider-specific read-only usage queries with existing service authentication; this is not a claim that every provider has a public, supported API. Provider toggles are in Connections. Sign in to each service before refreshing. Missing authentication/permissions remain unavailable; no quota is fabricated.

Server-supplied plan labels classify personal, free and organization-managed contexts. Enterprise, Business, Team and education labels use “Your boss is gonna love this.” and “Review seat…” instead of personal cancellation instructions. A free plan has no cancellation action. Unknown plan labels do not establish who pays. Workplace quotas may be pooled and personal activity is not organization-wide utilization. No company messages or billing changes are sent.

Raw account email and organization names are not saved: account/workspace identity is hashed to partition quota history. When a verified account or reported plan changes, its previous baseline is discarded. Anonymous transcript history isn't assigned to a verified account; live expiry estimates start with the recorded server snapshots. Model/budget buckets with the same duration stay separate. Unsupported cadence or reset data remains unavailable instead of fabricating expiry. Existing local Claude/Codex token history stays available under Details.

The current vendored helper is macOS arm64. See vendor/codexbar/PROVENANCE.md and LICENSE. It is bundled inside Bubble Tax; nothing is installed globally.

## Completed changes and savings

**Review first** is enabled by default and can be toggled above the service strip. Evidence-backed review candidates come first; the selected service stays selected on refresh. Completed records are removed from the review queue. Missing, free and unfinished-window readings are not promoted into cancellation verdicts.

**Plan actions → Compare downgrade…** compares cheaper published tiers. A Week / Month / Year picker converts the monthly price difference into illustrative real-world budget ideas, from coffee and meals to concerts and travel. These ideas also appear in completed-change previews and Savings history. Exact tier prices are required; the comparison is conditional on the cheaper tier covering your work. Enterprise plans show a sarcastic stock joke and remain excluded from personal savings.

Open **Plan actions → Record completed change…** after completing cancellation or downgrade with the provider. Select the actual new tier for a downgrade, confirm completion and save. Work plans can record a released seat without personal savings. The banknote button opens **Savings**, with completed actions, dates, from/to tiers and an undo for the latest record in each account chain. Undo removes a local record; it does not change the provider subscription.

Amounts show estimated monthly rate reductions at the bundled public USD list prices. They are not invoices, refunds, accumulated cash saved or unused-quota percentages converted into money. Ambiguous/missing prices are excluded from the estimate. Only the latest record in each account chain contributes to the total, preventing downgrade-then-cancel double counting. Account hashes partition records. Previously observed paid tiers are retained so a provider reporting Free or a cheaper tier does not erase the recording basis.

The footer **Refresh** and the speech-bubble refresh icon both query current usage. The speech-bubble button also rotates the copy after the collector returns; both show/disable during collection. Failures surface as unavailable rather than inventing a fresh quota. Demo fixtures do not run collectors or write real state.

## Compact visuals

The main menu pairs current Left with a small expired-window history chart for each quota. The orange persona ring represents estimated unused quota near reset, not remaining quota or cash waste. Service cells show thin remaining-balance bars. Roast headlines stay visible; the info button reveals context and receipts. Long pricing, identity and work-plan explanations are available as tooltips in Details. Savings uses Before/After bars with a shared USD scale and keeps the monthly list-price estimate label visible. No observation or classification rules change with this presentation.
