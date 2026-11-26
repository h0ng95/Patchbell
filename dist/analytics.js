(() => {
  const measurementId = window.patchbellAnalyticsId;
  if (typeof measurementId !== 'string' || !/^G-[A-Z0-9]+$/.test(measurementId)) return;

  const preferenceKey = 'patchbell.analytics';
  const disableKey = `ga-disable-${measurementId}`;
  const settings = document.querySelector('#analytics-settings');
  const panel = document.querySelector('#analytics-choice');
  const allow = document.querySelector('#analytics-allow');
  const decline = document.querySelector('#analytics-decline');
  const denied = {
    analytics_storage: 'denied',
    ad_storage: 'denied',
    ad_user_data: 'denied',
    ad_personalization: 'denied',
  };
  let tag;
  let savedChoice;

  try {
    savedChoice = localStorage.getItem(preferenceKey);
  } catch {
    // The choice still applies for the current page load.
  }

  function gtag() {
    (window.dataLayer ??= []).push(arguments);
  }

  function startAnalytics() {
    window[disableKey] = false;
    if (!tag) gtag('consent', 'default', denied);
    gtag('consent', 'update', { analytics_storage: 'granted' });
    if (tag) return;

    gtag('js', new Date());
    gtag('config', measurementId, {
      allow_google_signals: false,
      allow_ad_personalization_signals: false,
      cookie_prefix: 'patchbell',
      cookie_path: new URL('.', location.href).pathname,
    });
    tag = document.createElement('script');
    tag.async = true;
    tag.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(measurementId)}`;
    document.head.append(tag);
  }

  function showChoice(visible) {
    panel.hidden = !visible;
    settings.setAttribute('aria-expanded', String(visible));
  }

  function setChoice(choice) {
    try {
      localStorage.setItem(preferenceKey, choice);
    } catch {
      // The choice still applies for the current page load.
    }
    if (choice === 'allow') {
      startAnalytics();
    } else {
      window[disableKey] = true;
      if (tag) gtag('consent', 'update', denied);
    }
    const restoreFocus = panel.contains(document.activeElement);
    showChoice(false);
    if (restoreFocus) settings.focus({ preventScroll: true });
  }

  settings.hidden = false;
  settings.addEventListener('click', () => {
    showChoice(panel.hidden);
    if (!panel.hidden) decline.focus({ preventScroll: true });
  });
  allow.addEventListener('click', () => setChoice('allow'));
  decline.addEventListener('click', () => setChoice('decline'));

  if (savedChoice === 'allow') startAnalytics();
  if (savedChoice !== 'allow' && savedChoice !== 'decline') showChoice(true);
})();
