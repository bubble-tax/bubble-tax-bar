(() => {
  const screens = {
  "model-windows": {
    "title": "Five hours. One weekly budget.",
    "body": "See how much weekly quota each five-hour window actually consumed. Compare recorded meter changes with model usage from logs before planning the next task.",
    "note": "Claude and Codex · observed percentage-point changes, not a fixed token-to-quota formula.",
    "label": "Window comparison"
  },
  "claude-windows": {
    "title": "What did that window cost?",
    "body": "Compare Claude’s five-hour usage with the weekly quota it drew down. Model usage from logs adds context to the differences between windows.",
    "note": "Gaps remain visible. Model mix is context, not a claim about exact quota weights.",
    "label": "Claude windows"
  },
  "use-next": {
    "title": "Give the next task a home.",
    "body": "See which suitable service has headroom after your planned work is accounted for. Choose coding, writing or research, then open the service’s quota view.",
    "note": "Claude and Codex · availability and your preferences. You choose where to run the task.",
    "label": "Use next"
  },
  "reserve": {
    "title": "Save room for Friday.",
    "body": "Set aside a share of weekly quota for a named task and deadline. See what is used, reserved and still unallocated at a glance.",
    "note": "Local planning targets. Quota is not locked or moved between providers.",
    "label": "Reserve"
  },
  "forecast": {
    "title": "Will the week’s work fit?",
    "body": "Set your expected daily hours and compare projected headroom at reset with the quota you have set aside. Adjust the plan before the meter runs out.",
    "note": "Estimates from observed window history, including idle time. Too little data stays unknown.",
    "label": "Forecast"
  },
  "patterns": {
    "title": "Know what fills the meter.",
    "body": "See which models you used, cache reuse and large-input requests together. Use the pattern as a starting point for changing how you work.",
    "note": "Metadata from locally stored logs; not a measurement of answer quality or guaranteed savings.",
    "label": "Patterns"
  },
  "plans": {
    "title": "Keep the capacity you need.",
    "body": "Review plan choices against recorded resets, peak use and upcoming work. Keep useful headroom; reconsider tiers that repeatedly go unused.",
    "note": "Evidence needs time. Personal costs and shared work capacity are reviewed separately.",
    "label": "Plans"
  },
  "savings": {
    "title": "Make the smaller bill stick.",
    "body": "Record completed downgrades and cancellations. Keep the before-and-after monthly difference in one place.",
    "note": "Published list-price reductions, not cash already recovered.",
    "label": "Savings"
  },
  "connections": {
    "title": "Start with what’s signed in.",
    "body": "Connect available provider sessions and choose your local log folders. Tracking, task preferences and display options live in Settings.",
    "note": "Optional Claude Code quota statusline replaces the current display while connected; disconnect restores it.",
    "label": "Settings"
  }
};
  const root = document.documentElement;
  const themeToggle = document.getElementById("theme-toggle");
  let manualTheme = false;
  try { manualTheme = ["light", "dark"].includes(localStorage.getItem("bubble-tax-theme")); } catch {}
  const systemTheme = matchMedia("(prefers-color-scheme: dark)");
  const assetUrl = name => `assets/${name}.png?v=${window.BUBBLE_TAX_BAR_CONFIG.assetVersion}`;
  const themedSource = image => image.dataset[root.dataset.theme];
  const applyTheme = theme => {
    root.dataset.theme = theme;
    themeToggle.textContent = theme === "dark" ? "Light" : "Dark";
    themeToggle.setAttribute("aria-label", `Switch to ${theme === "dark" ? "light" : "dark"} mode`);
    document.querySelector('meta[name="theme-color"]').content = theme === "dark" ? "#181818" : "#f7f6f2";
    document.querySelectorAll("img[data-light][data-dark]").forEach(image => {
      image.src = themedSource(image);
      const button = image.closest("[data-image]");
      if (button) button.dataset.image = image.getAttribute("src");
    });
    const modalImage = document.getElementById("full-image");
    if (modalImage.dataset.light) modalImage.src = themedSource(modalImage);
  };
  themeToggle.addEventListener("click", () => {
    const next = root.dataset.theme === "dark" ? "light" : "dark";
    manualTheme = true;
    try { localStorage.setItem("bubble-tax-theme", next); } catch {}
    applyTheme(next);
  });
  systemTheme.addEventListener("change", event => { if (!manualTheme) applyTheme(event.matches ? "dark" : "light"); });
  applyTheme(root.dataset.theme);
  const tourImage = document.getElementById("tour-image");
  const tourButton = document.getElementById("tour-image-button");
  document.querySelectorAll("[data-screen]").forEach(button => {
    button.addEventListener("click", () => {
      const key = button.dataset.screen;
      const screen = screens[key];
      document.querySelectorAll("[data-screen]").forEach(item => {
        const selected = item === button;
        item.classList.toggle("active", selected);
        item.setAttribute("aria-pressed", String(selected));
      });
      tourImage.dataset.light = assetUrl(key);
      tourImage.dataset.dark = assetUrl(key + "-dark");
      tourImage.src = themedSource(tourImage);
      tourImage.alt = `${screen.label} — actual Bubble Tax macOS app with sample data.`;
      tourButton.dataset.image = tourImage.getAttribute("src");
      tourButton.dataset.caption = tourImage.alt;
      document.getElementById("shot-label").textContent = screen.label;
      document.getElementById("tour-title").textContent = screen.title;
      document.getElementById("tour-body").textContent = screen.body;
      document.getElementById("tour-note").textContent = screen.note;
    });
  });
  let previewMode = "notch";
  const desktop = document.querySelector(".mac-desktop");
  const notchToggle = document.getElementById("notch-quota-toggle");
  const notchQuotaLabel = document.getElementById("notch-quota-label");
  const quotaToggle = document.getElementById("mac-quota-toggle");
  const setExpanded = expanded => {
    [quotaToggle, notchToggle].forEach(button => button.setAttribute("aria-expanded", String(expanded)));
    quotaToggle.setAttribute("aria-label", `${expanded ? "Close" : "Open"} Bubble Tax preview`);
    notchToggle.setAttribute("aria-label", `${expanded ? "Close" : "Open"} notch preview`);
    document.getElementById("mac-popover").hidden = !expanded;
  };
  [quotaToggle, notchToggle].forEach(button => button.addEventListener("click", () => {
    setExpanded(button.getAttribute("aria-expanded") !== "true");
  }));
  // Mirror the native 8-second cadence and 130ms fold / 170ms unfold.
  const quotaLabel = document.getElementById("mac-quota-label");
  const heroImage = document.querySelector(".mac-popover img");
  const quotaExamples = [
    {name: "Claude", period: "Weekly", left: 44, image: "overview"},
    {name: "Codex", period: "Weekly", left: 72, image: "overview-openai"},
  ];
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  let quotaIndex = 0;
  const renderQuota = () => {
    const examples = previewMode === "notch" ? quotaExamples.slice(0, 2) : quotaExamples;
    const example = examples[quotaIndex % examples.length];
    const asset = previewMode === "notch" ? `notch-${example.name === "Claude" ? "claude" : "openai"}` : example.image;
    document.getElementById("notch-service").textContent = example.name;
    notchQuotaLabel.textContent = `${example.period} ${example.left}% left`;
    quotaLabel.textContent = `† ${example.name} · ${example.period} quota ${example.left}% left`;
    heroImage.dataset.light = assetUrl(asset);
    heroImage.dataset.dark = assetUrl(asset + "-dark");
    heroImage.src = themedSource(heroImage);
    heroImage.alt = `Bubble Tax ${previewMode === "notch" ? "notch preview" : "on macOS"} showing ${example.name} quota left with sample data.`;
    heroImage.closest("[data-image]").dataset.image = heroImage.getAttribute("src");
    heroImage.closest("[data-image]").dataset.caption = `${example.name} ${previewMode === "notch" ? "notch preview" : "overview"} — native macOS app capture, sample data.`;
  };
  document.querySelectorAll("button[data-preview]").forEach(button => {
    button.addEventListener("click", () => {
      previewMode = button.dataset.preview;
      desktop.dataset.preview = previewMode;
      desktop.setAttribute("aria-label", previewMode === "notch" ? "Mac desktop illustration with a simulated notch and actual Bubble Tax app capture" : "Mac desktop illustration with the actual Bubble Tax app open");
      quotaIndex = 0;
      document.querySelectorAll("button[data-preview]").forEach(item => item.setAttribute("aria-pressed", String(item === button)));
      document.getElementById("preview-caption").textContent = previewMode === "notch" ? "Notch preview · native app capture · sample data." : "Actual app capture · sample data.";
      setExpanded(true);
      renderQuota();
    });
  });
  // Warm both appearances so changing services or themes doesn't flash a blank image.
  quotaExamples.forEach(example => {
    ["", "-dark"].forEach(suffix => { const image = new Image(); image.src = assetUrl(example.image + suffix); });
  });
  ["claude", "openai"].forEach(provider => ["", "-dark"].forEach(suffix => {
    const image = new Image(); image.src = assetUrl(`notch-${provider}${suffix}`);
  }));
  renderQuota();
  setInterval(async () => {
    if (document.hidden || document.querySelector("dialog[open]")) return;
    quotaIndex = (quotaIndex + 1) % (previewMode === "notch" ? 2 : quotaExamples.length);
    if (reducedMotion.matches) { renderQuota(); return; }
    const flipTarget = previewMode === "notch" ? notchQuotaLabel : quotaLabel;
    const fold = flipTarget.animate([{transform: "rotateX(0deg)"}, {transform: "rotateX(-90deg)"}], {duration: 130, easing: "ease-in", fill: "forwards"});
    await fold.finished;
    renderQuota();
    fold.cancel();
    await flipTarget.animate([{transform: "rotateX(90deg)"}, {transform: "rotateX(0deg)"}], {duration: 170, easing: "ease-out"}).finished;
  }, 8000);
  const dialog = document.getElementById("image-dialog");
  document.querySelectorAll("[data-image]").forEach(button => {
    button.addEventListener("click", () => {
      const caption = button.dataset.caption;
      const fullImage = document.getElementById("full-image");
      const thumbnail = button.querySelector("img");
      fullImage.dataset.light = thumbnail.dataset.light;
      fullImage.dataset.dark = thumbnail.dataset.dark;
      fullImage.src = button.dataset.image;
      document.getElementById("full-image").alt = caption;
      document.getElementById("image-caption").textContent = caption;
      dialog.showModal();
      document.body.classList.add("modal-open");
    });
  });
  document.getElementById("close-dialog").addEventListener("click", () => dialog.close());
  dialog.addEventListener("close", () => document.body.classList.remove("modal-open"));
  dialog.addEventListener("click", event => { if (event.target === dialog) {
    const rect = dialog.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
  }});
  const config = window.BUBBLE_TAX_BAR_CONFIG || {};
  const activate = (id, value) => {
    if (!value) return false;
    let url;
    try { url = new URL(value); } catch { return false; }
    if (url.protocol !== "https:") return false;
    const link = document.getElementById(id);
    link.href = url.href;
    link.removeAttribute("aria-disabled");
    link.removeAttribute("tabindex");
    link.removeAttribute("role");
    link.rel = "noopener noreferrer";
    return true;
  };
  if (activate("download-link", config.downloadUrl)) document.getElementById("release-status").textContent = config.releaseLabel || "Public beta";
  const copyBrew = document.getElementById("copy-brew");
  copyBrew.addEventListener("click", async () => {
    const command = document.getElementById("brew-command");
    const status = document.getElementById("brew-copy-status");
    try {
      await navigator.clipboard.writeText(command.textContent.trim());
      copyBrew.textContent = "Copied";
      status.textContent = "Homebrew installation command copied.";
    } catch {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(command);
      selection.removeAllRanges(); selection.addRange(range);
      status.textContent = "Command selected. Press Command C to copy.";
    }
  });
  const coffeeDialog = document.getElementById("coffee-dialog");
  const coffeeTrigger = document.getElementById("coffee-link");
  if (activate("coffee-destination", config.coffeeUrl)) {
    coffeeTrigger.disabled = false;
    document.getElementById("coffee-status").hidden = true;
  }
  coffeeTrigger.addEventListener("click", () => {
    coffeeDialog.showModal();
    document.body.classList.add("modal-open");
  });
  ["close-coffee", "skip-coffee"].forEach(id => document.getElementById(id).addEventListener("click", () => coffeeDialog.close()));
  coffeeDialog.addEventListener("close", () => document.body.classList.remove("modal-open"));
  coffeeDialog.addEventListener("click", event => {
    if (event.target !== coffeeDialog) return;
    const rect = coffeeDialog.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) coffeeDialog.close();
  });
  activate("github-link", config.githubUrl);
})();
