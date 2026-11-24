const releases = window.patchbellReleases ?? {};
const formats = { windows: 'x64 · ZIP', macos: 'Universal · DMG' };

function showReleases() {
  const english = document.documentElement.lang === 'en';
  for (const [platform, release] of Object.entries(releases)) {
    if (!release) continue;

    const card = document.querySelector(`[data-platform="${platform}"]`);
    const link = card.querySelector('.platform-download');
    const platformName = card.querySelector('h3').textContent;
    const version = english ? `Version ${release.version}` : `버전 ${release.version}`;
    card.querySelector('.platform-status').textContent = `${version} · ${formats[platform]}`;
    link.href = release.url;
    link.download = '';
    link.setAttribute('aria-label', english
      ? `Download Patchbell for ${platformName}`
      : `${platformName}용 패치벨 다운로드`);
    link.hidden = false;
  }
}

document.addEventListener('patchbell:language', showReleases);
showReleases();
