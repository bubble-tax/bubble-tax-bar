# Bundled plan prices

Collected 2026-10-08. The app does not scrape billing pages at runtime or request plan/price input. `PlanPricing.swift` stores public US monthly list prices. These are reference estimates, not account charges. Taxes, annual discounts, promotions, regional prices and usage overages are excluded. Quota percentages are not literal refundable dollars.

| Service | Public monthly price (USD) | Official source |
|---|---|---|
| ChatGPT | Go 8; Plus 20; Pro 100 / 200 / 500 | [Go / Plus](https://openai.com/index/introducing-chatgpt-go/), [Pro tiers](https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers) |
| Claude | Pro 20; Max 5x 100; Max 20x 200 | [Plan guide](https://support.claude.com/en/articles/11049762-choose-a-claude-plan) |
| Cursor | Pro 20; Pro+ 60; Ultra 200 | [Pricing docs](https://cursor.com/help/account-and-billing/pricing) |
| GitHub Copilot | Pro 10; Pro+ 39; Max 100 | [Plans](https://github.com/features/copilot/plans) |
| Antigravity / Google AI | Pro 19.99; Ultra 5x 100; Ultra 20x 200 | [Pro](https://one.google.com/about/google-ai-plans/?gl=US&hl=en), [Ultra update](https://blog.google/products-and-platforms/products/google-one/google-ai-subscriptions/) |

Google prices represent the entire bundled Google AI subscription, not a standalone Antigravity license. Free/student and organization plans do not enter personal totals. Enterprise contract prices are not guessed. Unknown plan names remain unknown. Bare Claude Max, ChatGPT Pro or Google Ultra are ranges; no user tier selection is required. A complete exact price match and complete quota history permit price-weighted persona scoring. Otherwise quota scoring stays unweighted, with incomplete coverage indicated. Price catalog updates require a source change and app build.
