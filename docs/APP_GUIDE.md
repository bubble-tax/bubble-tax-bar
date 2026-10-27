# Bubble Tax usage & data guide

[Back to the product overview](../README.md)

## Connect and refresh

Open Settings from the menu-bar popover. Sign in to supported services first, then enable the providers you want to track. Bubble Tax uses the bundled CodexBarCLI v0.73.0 for read-only provider-specific queries with existing authentication. This does not imply that every provider offers a public, supported usage API. Missing authentication or permissions remain unavailable.

Local activity defaults:

| Source | Default directory |
| --- | --- |
| Claude Code | `~/.claude/projects` |
| Codex | `~/.codex/sessions` |
| Pi coding agent | `~/.pi/agent/sessions` |

Choose another folder in Connections if necessary. Connected sources show their selected path; reconnecting offers the default or a custom directory. Pi token counts are grouped by provider in Connections and matching service Details. They cannot establish which subscription, API key or extra-usage balance paid for a request. Pi credentials and conversation contents are not saved by Bubble Tax.

Both the main Refresh button and the speech-bubble refresh query usage. The latter also changes the roast after collection finishes. Failures show unavailable readings rather than fabricated quota. Demo fixtures do not run collectors or write real state.

## Menu bar and navigation

The menu bar rotates enabled, detected paid-plan quotas every eight seconds. Each title names the service, quota period and percentage left. Rotation pauses while the popover is open; Reduce Motion skips the flip animation.

In the popover, click a service card to switch subscriptions. The Quota left selector appears only when more than one enabled, detected plan is available. A single plan opens directly into its details.

The top toolbar opens Quota history, Savings and Settings. Subpages put Back on the left. Launch-at-login setup is offered on first launch and can be changed in Settings. Right-click the menu-bar item to quit.

Settings → General contains Cancellation candidates first. It prioritizes evidence-backed review candidates and preserves the selected service during refresh. Free, missing and unfinished readings are not promoted into cancellation verdicts.

## MacBook notch

On a display with a camera notch, Bubble Tax shows the paid service on the left and the quota period and percentage left on the right. Click to open that service's details below the notch. Click again, use the collapse button, press Escape, or click another app to close it. Paid plans rotate every eight seconds while collapsed.

Settings → General → Use MacBook notch switches back to the menu bar. Displays without a notch keep the regular menu-bar interface. Screen connections and resolution changes update the placement automatically.

## Allocate work and protect headroom

Open Allocation from the main screen or the branch icon in the toolbar.

- **Use next** suggests Claude or Codex from fresh overall weekly and 5-hour meters. Choose a work type and separate Personal / Work budgets. Configure eligible services for each task in Settings → Task routing. Suggestions describe headroom, not equivalent token capacity or model quality. View quota opens the suggested service in the overview.
- **Reserve** records named weekly-quota targets with deadlines before the current reset. Targets are tied to the reported account, plan and reset. The app won't create targets exceeding unallocated quota. Mark done or remove a target to release it. This is local planning; provider quota is never locked or transferred.
- **Forecast** combines measured paired-window changes with an editable daily time plan (initially 2h/day). It shows expected headroom at reset or planned usage before hitting a protected target. Observed hours include idle time; early estimates and missing data are labeled. Model changes, other devices and short-window limits can alter the outcome. No background work is started to consume quota.
- **Patterns** summarizes seven days of local metadata: repeated new inputs of at least 32K tokens, cache-read share and local model mix. Local logs may cover several accounts. These numbers don't establish task quality, retries, waste, billing savings or account-wide quota attribution.
- **Plans** compares capacity needs with current use and near-reset history. Pending reservations and recent 95%-used short windows take priority over downgrade reviews. At least three eligible resets spanning roughly two quota periods are needed to suggest comparing a smaller tier; consistently unused headroom doesn't guarantee a cheaper tier has the required features. Work seats stay separate from personal costs.

Preferences and reservation targets stay in the existing local state file. Expired, completed, previous-account and previous-reset targets don't reserve the current quota. The old weekly quota-exhaustion target has been replaced by Weekly runway.

## Current left versus expired unused

Current Left describes the active quota window. It is not expired waste. Weekly, session and monthly budgets are kept separate, including model-specific buckets of the same duration. Local transcript token totals have no subscription quota denominator and may omit web, mobile or other-device usage.

The persona and its ring use fresh **weekly** readings. Services without weekly readings are excluded from that calculation, and coverage is shown. Without eligible weekly data, the persona stays pending. Public plan prices can weight eligible readings, but they are not invoices.

Service review evidence uses the widest supported budget. A quiet session does not override an actively used weekly plan: 34% weekly left means 66% used. Incomplete coverage and insufficient history receive an early reading rather than a confident cancellation verdict.

## Unused history

Near-reset observations become local history after their windows expire. Only account-identified observations within 15 minutes of reset qualify; subsequent usage before reset is unknown. Missed periods and unsupported reset data are excluded. The app cannot recover unobserved past quota.

Unused history offers All recorded and Last 30 days, separate charts per account and limit, and reset receipts. Each bar shows the unused fraction against a faint full-quota track at the actual reset time. A dashed line marks the selected period’s average; hover for a reset’s date and remaining percentage. Charts show up to the latest 30 resets, while the average and receipts cover the selected period. The main quota details show recent expired-window estimates. Short-window and weekly percentages are never added together.

Account and workspace identities are hashed to partition records. Raw account emails and organization names are not saved. Verified identity or plan changes reset the relevant assessment baseline; anonymous local history is not assigned to a verified account.

## Review a plan and record a change

Plan actions → Compare downgrade compares cheaper tiers with known published prices. Week / Month / Year converts the monthly difference into illustrative spending ideas. A cheaper tier must still cover your work; a comparison does not guarantee that it will.

Cancel options opens official provider instructions. Complete cancellation or downgrade with that provider first, then choose Record completed change in Bubble Tax. For a downgrade, select the actual new tier. Work plans can record a released seat without personal savings.

Savings shows completed actions, dates and from/to tiers. Undo removes the latest local record in an account chain; it does not reverse the provider's billing change. Only the latest record in each chain contributes to the total, preventing downgrade-then-cancel double counting.

Amounts are estimated monthly rate reductions at bundled public USD list prices. They are not actual invoices, refunds, accumulated cash saved or unused quota converted into money. Ambiguous prices are excluded. Previously observed paid tiers are retained so a subsequent Free or cheaper-tier reading does not erase the recording basis.

## Personal and work plans

Reported plan labels distinguish free, personal and organization-managed contexts. Enterprise, Business, Team and education plans use Review seat rather than personal cancellation instructions. Free plans have no cancellation action; unknown labels do not establish who pays.

Work quotas may be pooled. Personal activity does not measure organization-wide utilization, and workplace plans are excluded from personal savings. No messages are sent to your employer and no billing changes are performed.

## Renewal schedules

Optional monthly or yearly renewal schedules can be set locally with an anchor date. They do not change provider quota resets or billing and do not replace actual invoice dates. No plan, price or renewal-date input is required to connect usage.

## Storage and builds

Local state is stored at `~/Library/Application Support/BubbleTaxBar/state.json`, with file permissions 0600. Existing service authentication is used for live queries; the app does not require users to paste passwords into its settings.

The installed app requires macOS 14+ and Apple silicon. Provider quota refresh calls the bundled native helper directly. Local Claude/Codex/Pi activity and the optional Claude statusline bridge use a bundled collector with its own Python runtime. Users do not need Python, Command Line Tools or a local server. Move the app to Applications before connecting the bridge; reconnect it in Settings if the app moves. Owned legacy connections migrate at launch. User-edited statuslines are left alone until you explicitly enable quota fallback again.

To build from source, run `bash scripts/run.command`. Development requires Swift 5.9+ and python.org Python 3.12 for bundling the collector; PyInstaller is installed only into a project-local build environment. Native provider requests are bounded by time and response size; unverified or failed data stays unavailable.

The build uses an ad-hoc signature. Developer ID signing and Apple notarization are separate distribution steps. See the [release notes](releases/v0.1.0.md), [price catalog](PRICE_CATALOG.md) and bundled helper [provenance](../vendor/codexbar/PROVENANCE.md).

## Claude window comparisons

Quota history → Claude windows records paired server readings of the 5-hour and weekly meters at each refresh (every five minutes while running). For each observed segment, it shows the 5-hour percentage-point change alongside the weekly percentage-point change, an expandable timeline, and a scatter plot comparing segments. The normalized rate is weekly percentage points per 100 session percentage points; it is an observation, not a guaranteed conversion rule.

Accounts, plans and weekly meters stay separate. A session/weekly reset, a meter decrease or a plan change starts a new segment. Gaps over 15 minutes and changes under 10 session percentage points are excluded from rate comparisons. Readings cover only the observed interval; they cannot reconstruct old windows, determine the model responsible, or isolate Claude Code from other Claude account activity. Rounded meters and reporting delays can affect ratios. Paired records are saved locally for 180 days, and the view shows the latest 30 segments for the selected account/plan/meter. Existing saved data remains compatible.

## Model context and Codex windows

Quota history now includes Claude and Codex window comparisons. Connect local code logs in Settings to see each observed interval’s model mix and input/output/cache tokens. The model picker includes intervals containing that model, including mixed-model intervals. Local token shares provide context; they do not allocate account-wide quota to models. Missing model metadata remains unknown.

## This week’s usage pattern

The main screen estimates the daily time and 5-hour quota equivalents needed to use the remaining weekly balance at your recent observed pace. It distinguishes insufficient records, an exhausted weekly limit, a pace too slow for the deadline, and insufficient 5-hour capacity at observed conversion rates. Estimates follow the current account, plan and weekly cycle; changing models or work patterns can change the outcome.


### Claude quota collection and local session history

Claude refresh tries OAuth, the authenticated Claude CLI, then automatic lookup. The user-installed CLI in `~/.local/bin` takes precedence over older Homebrew copies. If a response has usage but no identity, the app keeps trying the CLI before falling back to anonymous readings. Existing account records are never relabeled from the current login alone.

The connected Claude statusline bridge also retains sanitized pairs of 5-hour and weekly percentages, including while Bubble Tax is closed. Each session is isolated by a hashed session ID; raw session IDs, prompts, paths and credentials are not retained in this journal. It keeps at most 10,000 pairs over 180 days, sampled at five-minute intervals. Only periods actually observed by the updated bridge can be imported; installing it cannot recover missing historical measurements.

Local session readings appear separately as account-unverified and are excluded from subscription recommendations and account forecasts. Quota history shows the most recent paired reading and live collection source. A missing current identity no longer labels the saved account as a previous account.


### Build 13 statusline change

Quota fallback now owns its Claude Code display while connected, showing only the remaining five-hour and weekly quota. It never runs the previously configured statusline or any shell command. Disconnect restores the saved display command. Enabling explicitly replaces the current display after backing it up; automatic migration only updates a connection still owned by Bubble Tax.

Legacy Python bridge files are backed up and retired as no-op entry points. The legacy `original` delegation key is cleared, so old frozen collectors also stop chaining. Existing quota history is retained. If another tool later takes over the statusline, choose which tool should own the display; nested statusline chaining is no longer supported.
