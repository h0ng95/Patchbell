(() => {
  const root = document.documentElement;
  const darkMode = window.matchMedia('(prefers-color-scheme: dark)');
  const english = {
    home: 'Patchbell home',
    navigation: 'Page navigation',
    language: 'Language',
    appearance: 'Appearance',
    system: 'System',
    light: 'Light',
    dark: 'Dark',
    how: 'How it works',
    download: 'Download',
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
    downloadCopy: 'Find the installer for your operating system.',
    comingSoon: 'Coming soon',
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
  }

  applyTheme();
  darkMode.addEventListener('change', applyTheme);

  document.addEventListener('DOMContentLoaded', () => {
    const languageSelect = document.querySelector('#language');
    const themeSelect = document.querySelector('#theme');
    const description = document.querySelector('meta[name="description"]');
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

    languageSelect.value = language;
    themeSelect.value = theme;
    languageSelect.addEventListener('change', () => {
      language = languageSelect.value;
      writePreference('language', language);
      applyLanguage();
    });
    themeSelect.addEventListener('change', () => {
      theme = themeSelect.value;
      writePreference('theme', theme);
      applyTheme();
    });
    window.addEventListener('languagechange', applyLanguage);
    applyLanguage();
    document.querySelector('.site-preferences').hidden = false;
  });
})();
