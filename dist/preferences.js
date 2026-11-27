(() => {
  const root = document.documentElement;
  const darkMode = window.matchMedia('(prefers-color-scheme: dark)');
  const english = {
    home: 'Patchbell home',
    navigation: 'Page navigation',
    language: 'Language',
    system: 'System default',
    darkMode: 'Dark mode',
    how: 'How it works',
    download: 'Download',
    coffee: 'Buy me a coffee',
    eyebrow: 'Security alerts for your software',
    heroFirst: 'Security updates',
    heroSecond: 'for the software',
    heroEmphasis: 'you use.',
    intro: 'Track the software you use. When a security advisory affects an installed version, Patchbell explains why it matters and links to official update instructions.',
    viewDownloads: 'View downloads',
    preview: 'Preview',
    mySoftware: 'My software',
    sampleCount: '3 tracked',
    sampleApps: 'Examples of tracked software',
    installedVersion: 'Installed version',
    updateNeeded: 'Update needed',
    noAlerts: 'No new alerts',
    alertTitle: 'Chrome needs a security update',
    alertCopy: 'A security vulnerability affects your installed version.',
    alertAction: 'View official update instructions',
    stepAdd: 'Add your software',
    stepAddCopy: 'Register the software you use and its installed version.',
    stepCheck: 'Check affected versions',
    stepCheckCopy: 'Patchbell checks whether new security advisories affect your tracked versions.',
    stepAlert: 'Get update alerts',
    stepAlertCopy: 'Get a desktop alert when action is needed, then open the official instructions.',
    downloadTitle: 'Download Patchbell',
    downloadCopy: 'Download the file for your operating system.',
    comingSoon: 'Coming soon',
    footerDeveloper: 'Developed by',
    footerNavigation: 'Footer links',
    footerFeedback: 'Feedback',
    analyticsSettings: 'Analytics settings',
    analyticsTitle: 'Website analytics',
    analyticsDescription: 'Allow Google Analytics to measure visits so we can improve the Patchbell website?',
    analyticsDecline: 'Decline',
    analyticsAllow: 'Allow',
    pageTitle: 'Patchbell — Security update alerts',
    description: 'Get security update alerts for your software with Patchbell for Windows and macOS.',
  };

  function readPreference(key, choices) {
    try {
      const value = localStorage.getItem(`patchbell.${key}`);
      if (choices.includes(value)) return value;
    } catch {
      // Browser storage may be unavailable.
    }
    return 'system';
  }

  function writePreference(key, value) {
    try {
      localStorage.setItem(`patchbell.${key}`, value);
    } catch {
      // The selection still applies to the current page.
    }
  }

  let theme = readPreference('theme', ['light', 'dark']);
  let language = readPreference('language', ['ko', 'en']);

  function applyTheme() {
    const systemTheme = darkMode.matches ? 'dark' : 'light';
    root.dataset.theme = theme === 'system' ? systemTheme : theme;
    document.querySelector('meta[name="theme-color"]').content =
      root.dataset.theme === 'dark' ? '#101916' : '#f6f7ef';
    document.querySelector('#theme-toggle')
      ?.setAttribute('aria-checked', String(root.dataset.theme === 'dark'));
  }

  applyTheme();
  darkMode.addEventListener('change', applyTheme);

  document.addEventListener('DOMContentLoaded', () => {
    const languagePicker = document.querySelector('.language-picker');
    const languageSummary = languagePicker.querySelector('summary');
    const languageCode = document.querySelector('#language-code');
    const languageOptions = languagePicker.querySelectorAll('input[name="language"]');
    const themeToggle = document.querySelector('#theme-toggle');
    const description = document.querySelector('meta[name="description"]');
    const coffeeLink = document.querySelector('.nav-coffee');
    const koreanTitle = document.title;
    const koreanDescription = description.content;
    const strings = [...document.querySelectorAll('[data-i18n], [data-i18n-label]')].map(node => {
      const attribute = node.hasAttribute('data-i18n-label') ? 'aria-label' : null;
      return {
        node,
        attribute,
        key: node.dataset.i18nLabel ?? node.dataset.i18n,
        korean: attribute ? node.getAttribute(attribute) : node.textContent,
      };
    });

    function applyLanguage() {
      const systemLanguage = navigator.languages
        .map(locale => locale.split('-')[0])
        .find(locale => locale === 'en' || locale === 'ko') ?? 'en';
      root.lang = language === 'system' ? systemLanguage : language;
      languageCode.textContent = root.lang.toUpperCase();
      for (const option of languageOptions) option.checked = option.value === language;
      const useEnglish = root.lang === 'en';
      for (const { node, attribute, key, korean } of strings) {
        const translated = useEnglish ? english[key] : korean;
        if (attribute) node.setAttribute(attribute, translated);
        else node.textContent = translated;
      }
      document.title = useEnglish ? english.pageTitle : koreanTitle;
      description.content = useEnglish ? english.description : koreanDescription;
      document.dispatchEvent(new Event('patchbell:language'));
    }

    function setLanguage(value) {
      language = value;
      writePreference('language', language);
      applyLanguage();
    }

    for (const option of languageOptions) {
      option.addEventListener('change', () => setLanguage(option.value));
      option.addEventListener('click', () => {
        languagePicker.open = false;
        languageSummary.focus();
      });
    }
    document.addEventListener('click', event => {
      if (!languagePicker.contains(event.target)) languagePicker.open = false;
    });
    languagePicker.addEventListener('focusout', event => {
      if (event.relatedTarget && !languagePicker.contains(event.relatedTarget)) {
        languagePicker.open = false;
      }
    });
    languagePicker.addEventListener('keydown', event => {
      if (event.key === 'Escape' && languagePicker.open) {
        event.preventDefault();
        languagePicker.open = false;
        languageSummary.focus();
      }
    });
    themeToggle.addEventListener('click', () => {
      theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
      writePreference('theme', theme);
      applyTheme();
    });
    window.addEventListener('languagechange', applyLanguage);
    applyLanguage();
    applyTheme();
    document.querySelector('.site-preferences').hidden = false;
    try {
      const url = new URL(window.patchbellSupportUrl);
      if (url.protocol === 'https:' &&
          ['buymeacoffee.com', 'www.buymeacoffee.com'].includes(url.hostname) &&
          !url.port && !url.username && !url.password &&
          /^\/[a-zA-Z0-9_-]+\/?$/.test(url.pathname)) {
        coffeeLink.href = url.origin + url.pathname;
        coffeeLink.hidden = false;
      }
    } catch {
      // Show the link once a creator page has been configured.
    }
  });
})();
