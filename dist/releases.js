// Set each platform to { url: "./downloads/filename", version: "1.0.0" }
// when its installer is ready. An HTTPS release URL also works.
const releases = {
  windows: null,
  macos: null,
};

function showReleases() {
  const english = document.documentElement.lang === 'en';
  for (const [platform, release] of Object.entries(releases)) {
    if (!release) continue;

    const card = document.querySelector(`[data-platform="${platform}"]`);
    const link = card.querySelector('.platform-download');
    const platformName = card.querySelector('h3').textContent;
    card.querySelector('.platform-status').textContent =
      english ? `Version ${release.version}` : `버전 ${release.version}`;
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
