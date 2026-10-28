(() => {
  const id = window.BUBBLE_TAX_BAR_CONFIG?.gaMeasurementIds?.[location.hostname];
  // Only known production hosts load their own GA4 stream.
  if (!/^G-[A-Z0-9]+$/.test(id || '') || navigator.globalPrivacyControl) return;
  window.dataLayer = window.dataLayer || [];
  const gtag = function () { window.dataLayer.push(arguments); };
  gtag('js', new Date());
  gtag('config', id, {
    allow_google_signals: false,
    allow_ad_personalization_signals: false,
    page_location: location.origin + location.pathname,
  });
  const script = document.createElement('script');
  script.async = true;
  script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(id)}`;
  document.head.append(script);
  document.getElementById('download-link').addEventListener('click', event => {
    if (event.currentTarget.getAttribute('aria-disabled') === 'true') return;
    gtag('event', 'download_click', {release: window.BUBBLE_TAX_BAR_CONFIG.releaseLabel, transport_type: 'beacon'});
  });
  document.getElementById('copy-brew').addEventListener('click', () => {
    gtag('event', 'homebrew_copy_click');
  });
  document.querySelectorAll('[data-screen]').forEach(button => button.addEventListener('click', () => {
    gtag('event', 'feature_view', {feature: button.dataset.screen});
  }));
})();
