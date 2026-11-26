import 'package:flutter/widgets.dart';

import 'catalog.dart';

class PatchbellText {
  const PatchbellText(this.locale);

  static const english = PatchbellText(Locale('en'));
  static const supportedLocales = [Locale('en'), Locale('ko')];
  static PatchbellText of(BuildContext context) =>
      PatchbellText(Localizations.localeOf(context));

  final Locale locale;
  bool get _ko => locale.languageCode == 'ko';
  String _choose(String ko, String en) => _ko ? ko : en;
  String _plural(int count, String singular, String plural) =>
      count == 1 ? singular : plural;

  String get settings => _choose('설정', 'Settings');
  String get buyMeACoffee => _choose('개발자에게 커피 한 잔', 'Buy me a coffee');
  String get language => _choose('언어', 'Language');
  String get system => _choose('시스템 설정', 'System default');
  String get switchToLight => _choose('라이트 모드로 전환', 'Switch to light mode');
  String get switchToDark => _choose('다크 모드로 전환', 'Switch to dark mode');
  String get close => _choose('닫기', 'Close');
  String get cancel => _choose('취소', 'Cancel');
  String get save => _choose('저장', 'Save');
  String get retry => _choose('다시 시도', 'Try again');
  String get all => _choose('전체', 'All');
  String get select => _choose('선택', 'Select');
  String get linkFailed => _choose(
      '브라우저에서 링크를 열지 못했어요.', 'Could not open the link in your browser.');
  String get settingsSaveFailed =>
      _choose('설정을 저장하지 못했어요.', 'Could not save your settings.');

  String category(ProductCategory category) => switch (category) {
        ProductCategory.app => _choose('일반 앱', 'Apps'),
        ProductCategory.editor => _choose('에디터', 'Editors'),
        ProductCategory.sdk => 'SDK',
        ProductCategory.runtime => _choose('언어·런타임', 'Languages & runtimes'),
      };
  String productName(Product product) => product.id == 'dotnet'
      ? _choose('.NET 런타임', '.NET Runtime')
      : product.name;

  String get mySoftware => _choose('내 소프트웨어', 'My software');
  String get homeIntro => _choose('등록한 앱과 개발 도구의 보안 공지를 확인하세요.',
      'Track security advisories for your apps and developer tools.');
  String get register => _choose('항목 등록', 'Add software');
  String get scan => _choose('설치 버전 찾기', 'Find installed versions');
  String get checkAdvisories => _choose('보안 공지 확인', 'Check advisories');
  String get checking => _choose('확인 중', 'Checking');
  String get registered => _choose('등록 항목', 'Tracked items');
  String get affectedItems => _choose('공지 있는 항목', 'Items with advisories');
  String get sources => _choose('보안 공지 출처는 NIST NVD와 OSV예요.',
      'Advisories are sourced from NIST NVD and OSV.');
  String get emptyCategory =>
      _choose('이 분류에 등록한 항목이 없어요.', 'No tracked items in this category.');
  String get addFirstItem => _choose('첫 항목을 등록해 보세요.', 'Add your first item.');
  String get emptyDescription => _choose('프로그램, 에디터, SDK, 언어와 런타임을 등록할 수 있어요.',
      'Track apps, editors, SDKs, languages, and runtimes.');
  String get checkFailed => _choose('확인 실패', 'Check failed');
  String get unlinked => _choose('공지 출처 미연결', 'No advisory source');
  String get findSource => _choose('출처 찾기', 'Find source');
  String get unchecked => _choose('미확인', 'Not checked');
  String get noMatches => _choose('일치 공지 없음', 'No matching advisories');
  String advisoryCount(int count) => _choose(
      '공지 $count건', '$count ${_plural(count, 'advisory', 'advisories')}');
  String manage(String name) => _choose('$name 관리', 'Manage $name');
  String get edit => _choose('항목 수정', 'Edit item');
  String get remove => _choose('등록 해제', 'Stop tracking');
  String trackedVersion(String version) =>
      _choose('등록 버전 $version', 'Tracked version $version');
  String lastChecked(String date) =>
      _choose('최근 확인 $date', 'Last checked $date');
  String get linkSourceToCheck => _choose(
      '이 항목의 보안 공지를 확인하려면 같은 제품이나 패키지를 연결해 주세요.',
      'Link the matching product or package to check advisories for this item.');
  String get nothingChecked =>
      _choose('아직 조회한 보안 공지가 없어요.', 'Advisories have not been checked yet.');
  String get noVersionAdvisories => _choose(
      '이 버전에 일치하는 공개 공지가 없어요.', 'No public advisories match this version.');
  String get advisoryDetails => _choose(
      '제품과 버전이 일치한 공지예요. 공지에서 운영체제와 수정 버전을 확인하세요.',
      'These advisories match the product and version. Open an advisory for affected platforms and fixed versions.');
  String get updateInstructions =>
      _choose('공식 업데이트 안내', 'Official update instructions');

  String get desktopAlerts => _choose('데스크톱 알림', 'Desktop alerts');
  String get newAdvisoryAlerts =>
      _choose('새 보안 공지 알림', 'Alerts for new advisories');
  String get alertsWhileRunning => _choose(
      '앱이 실행 중일 때 새 공지를 알려드려요.', 'Get alerts while Patchbell is running.');
  String get testAlert => _choose('테스트 알림', 'Test notification');
  String alertTitle(String name) =>
      _choose('$name 보안 공지', '$name security advisory');
  String alertBody(String version, int count) => _choose(
      '등록 버전 $version · 새 보안 공지 $count건',
      'Tracked version $version · $count new ${_plural(count, 'advisory', 'advisories')}');
  String get testAlertTitle =>
      _choose('Patchbell 테스트 알림', 'Patchbell test notification');
  String get testAlertBody => _choose('등록한 버전에 새 보안 공지가 생기면 이렇게 알려드려요.',
      'This is how Patchbell will alert you about new advisories for tracked versions.');
  String get alertPermission => _choose('시스템 설정에서 Patchbell 알림을 허용해 주세요.',
      'Allow Patchbell notifications in your system settings.');
  String get alertEnableFailed =>
      _choose('데스크톱 알림을 켜지 못했어요.', 'Could not enable desktop notifications.');
  String get alertFailed =>
      _choose('데스크톱 알림을 보내지 못했어요.', 'Could not send a desktop notification.');
  String get testAlertSent =>
      _choose('테스트 알림을 보냈어요.', 'Test notification sent.');
  String get windowsTestAlertHelp => _choose(
      '배너가 안 보이면 Windows 방해 금지 설정을 확인해 주세요.',
      'If you don’t see a banner, check Do not disturb in Windows Settings.');
  String get openWindowsNotificationSettings =>
      _choose('Windows 알림 설정 열기', 'Open Windows notification settings');
  String get testAlertFailed =>
      _choose('테스트 알림을 보내지 못했어요.', 'Could not send the test notification.');
  String get loadFailed => _choose('저장된 항목을 읽지 못했어요. 다시 시도해 주세요.',
      'Could not load your saved items. Try again.');
  String get storageFailed => _choose(
      '변경사항을 이 기기에 저장하지 못했어요.', 'Could not save changes on this device.');
  String get advisoriesFailed => _choose('보안 공지를 확인하지 못했어요. 연결 상태를 확인해 주세요.',
      'Could not check advisories. Check your internet connection.');
  String requestLimit(String source) => _choose(
      '$source 요청 한도에 도달했어요. 잠시 후 다시 확인해 주세요.',
      '$source rate limit reached. Try again in a moment.');
  String responseError(String source, int status) => _choose(
      '$source 응답 오류 ($status)', '$source returned an error ($status).');

  String get backToSearch => _choose('제품 검색으로 돌아가기', 'Back to search');
  String get productNameLabel => _choose('제품 이름', 'Product name');
  String get productNameExample =>
      _choose('예: Rust, Zig, Kotlin SDK', 'e.g. Rust, Zig, Kotlin SDK');
  String get enterProductName =>
      _choose('제품 이름을 입력해 주세요.', 'Enter a product name.');
  String get categoryLabel => _choose('분류', 'Category');
  String get software => _choose('소프트웨어', 'Software');
  String get installedVersion => _choose('설치 버전', 'Installed version');
  String enterVersion(String example) => _choose(
      '설치 버전을 입력해 주세요 (예: $example).',
      'Enter your installed version (e.g. $example).');
  String get alreadyRegistered => _choose(
      '이미 등록한 제품과 버전이에요.', 'You already track this product and version.');
  String get changeSource => _choose('공지 출처 변경', 'Change advisory source');
  String get findAndLink =>
      _choose('제품·패키지 검색 및 연결', 'Find and link a product or package');
  String get disconnectSource =>
      _choose('공지 출처 연결 해제', 'Unlink advisory source');
  String get linkedSourceHelp => _choose('제품이나 패키지를 연결하면 등록한 버전의 공지를 확인해요.',
      'Link a product or package to check advisories for your version.');
  String searchSlow(String source) => _choose(
      '$source 검색 응답이 늦어지고 있어요.', '$source is taking too long to respond.');
  String searchFailed(String source) =>
      _choose('$source 검색 결과를 불러오지 못했어요.', 'Could not load $source results.');
  String searchResults(String source) =>
      _choose('$source 검색 결과', '$source results');
  String searchingSource(String source) =>
      _choose('$source 검색 중…', 'Searching $source…');
  String moreResults(String source) =>
      _choose('$source 결과 더 보기', 'More $source results');
  String retrySource(String source) =>
      _choose('$source 다시 시도', 'Retry $source');
  String get linkProduct => _choose('제품·패키지 연결', 'Link a product or package');
  String get linkAppSource => _choose('보안 공지 출처 연결', 'Link advisory source');
  String get searchLabel => _choose('제품 이름 검색', 'Search by product name');
  String get searchExample =>
      _choose('예: Python, Docker, NestJS', 'e.g. Python, Docker, NestJS');
  String get searching =>
      _choose('제품·패키지 검색 중', 'Searching products and packages');
  String quickPicks(int count) =>
      _choose('빠른 선택 · $count개', 'Quick picks · $count');
  String get nothingFound =>
      _choose('일치하는 제품이나 패키지가 없어요.', 'No matching products or packages.');
  String get chooseMatchingSource => _choose('등록한 항목과 같은 제품이나 패키지를 선택해 주세요.',
      'Choose the same product or package as the item you are tracking.');
  String get noSourceFound => _choose(
      '연결할 출처 후보가 없어요. 제조사나 영문 제품명으로 다시 검색해 보세요.',
      'No sources found. Try searching by publisher or the English product name.');
  String get addManually => _choose('직접 등록', 'Add manually');
  String npmVersion(String version) =>
      _choose('npm · 최신 $version', 'npm · Latest $version');

  String get nothingInFolder => _choose('이 폴더에서 지원하는 도구의 설치 버전을 찾지 못했어요.',
      'No supported tools were found in this folder.');
  String get scanFailed => _choose('설치 버전을 읽지 못했어요. 설치 폴더를 선택해 보세요.',
      'Could not read installed versions. Try choosing the installation folder.');
  String get folderFailed =>
      _choose('폴더를 열지 못했어요.', 'Could not open the folder.');
  String get scanIntro => _choose('이 컴퓨터에서 찾은 앱과 개발 도구 중 추적할 항목을 고르세요.',
      'Choose which apps and developer tools on this computer to track.');
  String get scanEmpty => _choose('설치 버전을 찾지 못했어요. 도구가 설치된 폴더를 선택해 검색할 수 있어요.',
      'No installed versions found. Choose an installation folder to search.');
  String trackedLocation(String path) =>
      _choose('등록됨 · $path', 'Tracked · $path');
  String get selectFolder => _choose('설치 폴더 선택', 'Choose installation folder');
  String get selectNpmProject => _choose('npm 프로젝트 선택', 'Choose npm project');
  String get noProjectPackages => _choose(
      '설치된 npm 패키지를 찾지 못했어요. package.json과 node_modules가 있는 폴더를 선택하세요.',
      'No installed npm packages found. Choose a folder with package.json and node_modules.');
  String addSelected(int count) => _choose(count == 0 ? '선택 등록' : '$count개 등록',
      count == 0 ? 'Add selected' : 'Add $count');

  String menuBadge(int count) => _choose('Patchbell · 확인할 항목 $count개',
      'Patchbell · $count ${_plural(count, 'item', 'items')} to review');
  String menuAffected(int count) => _choose('확인할 보안 공지 · $count개 항목',
      'Security advisories · $count ${_plural(count, 'item', 'items')}');
  String menuAdvisoryCount(int count) =>
      _choose('$count건', advisoryCount(count));
  String get menuLoadFailed =>
      _choose('등록 목록을 불러오지 못했어요', 'Could not load tracked items');
  String get menuLoading => _choose('등록 목록 불러오는 중…', 'Loading tracked items…');
  String get menuNoAdvisories =>
      _choose('표시할 보안 공지가 없어요', 'No advisories to show');
  String get menuChecking => _choose('보안 공지 확인 중…', 'Checking advisories…');
  String get menuCheckFailed =>
      _choose('일부 항목의 조회에 실패했어요', 'Some items could not be checked');
  String get menuRegister => _choose('등록하기…', 'Add software…');
  String get menuOpen => _choose('내 소프트웨어 열기', 'Open My Software');
  String get menuQuit => _choose('Patchbell 종료', 'Quit Patchbell');
}

typedef LocalizedMessage = String Function(PatchbellText text);
