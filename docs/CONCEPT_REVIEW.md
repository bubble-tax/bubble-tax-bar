# Concept review — 2026-10-09

Goal: cancel or downgrade AI subscriptions oversized for actual needs. Success is reduced unnecessary recurring spending, not increased token consumption.

## Corrected

- Shared widest-budget selection across persona and service roast. A current weekly budget or weekly history without eligible near-reset samples blocks a misleading short-window waste judgment.
- Early read now checks each represented plan for at least three eligible expired windows, rather than adding thin samples from different services.
- Active status now says Usage confirmed instead of Earning its keep; activity does not establish monetary value.
- Service strip marks evidence-backed personal reviews as Review and work-seat reviews as Review seat. Unknown/free/current-only readings do not receive those labels.
- Product documentation now reflects the English menu-bar experience, authenticated usage, local fallback and public price estimates. Cancellation history, cemetery sharing and verified savings remain future work.

## Remaining priorities

1. **Match the action to the outcome.** Current personal actions primarily open cancellation guidance/settings. Add a clear choice of cancellation and downgrade paths, with provider-specific destinations and feature-aware guidance. The current catalog does not establish what features a user needs, so automatic cheaper-tier recommendations would be premature.
2. **Close the loop.** Let users record completed cancellations/downgrades and a price basis, then show confirmed changes. Unused quota multiplied by a list price is not money saved. Current app neither performs cancellation nor verifies a completed change.
3. **Make review priority explicit.** Review labels now identify candidates; a review-first view could reduce page browsing. Preserve manual selection and avoid automatically jumping pages on refresh.

## Validation

27 Python tests and 51 Swift tests passed, including new regressions for missing weekly history and per-plan sample coverage. Release app built and restarted. Native popover visually checked with an isolated premium-waste demo; real state hash unchanged during the demo. Capture: ../../screenshots/subrip-concept-review.png.

## Follow-up implemented — 2026-10-09

Review first, user-completed change history, monthly list-price reduction estimates and latest-record undo are implemented. The service page uses Plan actions to access provider guidance and record completion. Both refresh controls now invoke the usage collector; the bubble control rotates its copy afterward. Annual/cumulative cash savings and feature-based downgrade recommendations remain outside this implementation.
