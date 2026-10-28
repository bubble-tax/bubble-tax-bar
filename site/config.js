// Add real destinations before publishing. Empty values keep buttons disabled.
window.BUBBLE_TAX_BAR_CONFIG = Object.freeze({
  downloadUrl: "https://github.com/bubble-tax/bubble-tax-bar/releases/download/v0.1.0-build.14/Bubble-Tax-0.1.0-macOS-arm64.zip", // GitHub Release asset URL (ZIP or DMG)
  githubUrl: "https://github.com/bubble-tax/bubble-tax-bar",
  coffeeUrl: "https://buymeacoffee.com/workromancer",
  assetVersion: "20261029",
  gaMeasurementIds: Object.freeze({
    "bubble-tax.github.io": "G-RDQQMG2P3P",
    "bubble-tax.workromancer.ai": "G-ZGTF5YBTDW",
  }),
  releaseLabel: "v0.1.0 Preview · Build 14", // e.g. "v0.1.0 · Apple silicon · unsigned beta"
});
