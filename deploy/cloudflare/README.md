# Custom hostname

`bubble-tax-landing` serves `bubble-tax.workromancer.ai` from the existing public `https://bubble-tax.github.io` origin. Both addresses remain directly accessible, so `site/config.js` can select separate GA4 streams by hostname. No GitHub Pages CNAME is set.

Cloudflare account: `3dd0aee58b6494f23da71181145156c8`.
Zone `workromancer.ai`: `5d6c127ca931996dbdb580905164b2f1`.

The Worker accepts GET/HEAD only, uses a fixed upstream, forwards no incoming cookies or authorization, and does not log request content. Cloudflare manages the custom hostname DNS and TLS certificate. Website updates are still published through the GitHub Pages repository; this Worker only needs redeployment when its proxy code changes.
