(() => {
  const screens = {
    "weekly-pattern": {title: "Your subscription needs a second job.", body: "See the daily pace needed to finish your remaining weekly quota. If keeping up sounds like work, the smaller plan might be enough.", note: "Claude and Codex · an estimate from observed use, including idle time. Too little data stays unknown.", label: "Weekly pattern"},
    "model-windows": {title: "Five hours. One weekly budget.", body: "Follow how each Claude or Codex window draws down the weekly meter. See the local model mix alongside the recorded changes.", note: "Token counts add context; they don't reveal a provider's exact quota formula.", label: "Codex windows"},
    "claude-windows": {title: "Same window. Different models.", body: "Compare Claude windows with their local model mix. Check whether similar short-window usage made a different dent in the weekly limit.", note: "Observed meter changes, with input, output and cache details available in the app.", label: "Claude windows"},
    "unused-history": {title: "The quota you left behind.", body: "Browse recorded resets across your subscriptions. See unused quota over time, with weekly and session limits kept separate.", note: "Only observed near-reset readings count. Missing periods aren't guessed.", label: "Unused history"},
    overview: {title: "The plans you're keeping.", body: "See current quota left across your AI services. Plans with repeated unused headroom move to the front for review.", note: "Current remaining quota isn't expired waste.", label: "Overview"},
    details: {title: "What went unused.", body: "See the quota left near past resets. A few quiet hours aren't enough to label a whole subscription a waste.", note: "Weekly and session limits stay separate.", label: "Past resets"},
    downgrade: {title: "Maybe the smaller plan is enough.", body: "Compare cheaper tiers. Turn the price difference into a weekly, monthly or yearly budget for something outside a chat window.", note: "Published list prices; check that the tier covers your work.", label: "Smaller plans"},
    savings: {title: "A smaller monthly bill.", body: "Record your completed cancellations and downgrades. Before-and-after prices show the monthly difference.", note: "Projected list-price reduction, not cash already recovered.", label: "Savings"},
    connections: {title: "Use what's already signed in.", body: "Read available usage from existing service sessions. For Claude and Codex, connect the default log folder or choose your own.", note: "Missing data stays unknown.", label: "Connections"},
    enterprise: {title: "Your boss's budget.", body: "Work plans get a seat review. Record a released seat when you're done, without counting company costs as your personal savings.", note: "Some workspace quotas may be shared.", label: "Work accounts"},
  };
  const root = document.documentElement;
  const themeToggle = document.getElementById("theme-toggle");
  let manualTheme = false;
  try { manualTheme = ["light", "dark"].includes(localStorage.getItem("bubble-tax-theme")); } catch {}
  const systemTheme = matchMedia("(prefers-color-scheme: dark)");
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
      tourImage.dataset.light = `assets/${key === "enterprise" ? "enterprise-light" : key}.png`;
      tourImage.dataset.dark = `assets/${key === "enterprise" ? "enterprise" : key + "-dark"}.png`;
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
  const quotaToggle = document.getElementById("mac-quota-toggle");
  quotaToggle.addEventListener("click", () => {
    const expanded = quotaToggle.getAttribute("aria-expanded") !== "true";
    quotaToggle.setAttribute("aria-expanded", String(expanded));
    quotaToggle.setAttribute("aria-label", `${expanded ? "Close" : "Open"} Bubble Tax preview`);
    document.getElementById("mac-popover").hidden = !expanded;
  });
  // Mirror the native 8-second cadence and 130ms fold / 170ms unfold.
  const quotaLabel = document.getElementById("mac-quota-label");
  const heroImage = document.querySelector(".mac-popover img");
  const quotaExamples = [
    {name: "Claude", period: "Weekly", left: 88, image: "overview"},
    {name: "Codex", period: "Weekly", left: 72, image: "overview-openai"},
    {name: "Cursor", period: "Monthly", left: 82, image: "overview-cursor"},
    {name: "Copilot", period: "Monthly", left: 77, image: "overview-copilot"},
    {name: "Antigravity", period: "Weekly", left: 93, image: "overview-antigravity"},
  ];
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  let quotaIndex = 0;
  const renderQuota = () => {
    const example = quotaExamples[quotaIndex];
    quotaLabel.textContent = `† ${example.name} · ${example.period} quota ${example.left}% left`;
    heroImage.dataset.light = `assets/${example.image}.png`;
    heroImage.dataset.dark = `assets/${example.image}-dark.png`;
    heroImage.src = themedSource(heroImage);
    heroImage.alt = `Bubble Tax on macOS showing ${example.name} quota left with sample data.`;
    heroImage.closest("[data-image]").dataset.image = heroImage.getAttribute("src");
    heroImage.closest("[data-image]").dataset.caption = `${example.name} overview — actual macOS app, sample data.`;
  };
  // Warm both appearances so changing services or themes doesn't flash a blank image.
  quotaExamples.slice(1).forEach(example => {
    ["", "-dark"].forEach(suffix => { const image = new Image(); image.src = `assets/${example.image}${suffix}.png`; });
  });
  setInterval(async () => {
    if (document.hidden || document.querySelector("dialog[open]")) return;
    quotaIndex = (quotaIndex + 1) % quotaExamples.length;
    if (reducedMotion.matches) { renderQuota(); return; }
    const fold = quotaLabel.animate([{transform: "rotateX(0deg)"}, {transform: "rotateX(-90deg)"}], {duration: 130, easing: "ease-in", fill: "forwards"});
    await fold.finished;
    renderQuota();
    fold.cancel();
    await quotaLabel.animate([{transform: "rotateX(90deg)"}, {transform: "rotateX(0deg)"}], {duration: 170, easing: "ease-out"}).finished;
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
