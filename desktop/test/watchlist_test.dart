import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patchbell_desktop/advisories.dart';
import 'package:patchbell_desktop/app_settings.dart';
import 'package:patchbell_desktop/catalog.dart';
import 'package:patchbell_desktop/desktop_alerts.dart';
import 'package:patchbell_desktop/mac_platform.dart';
import 'package:patchbell_desktop/main.dart';
import 'package:patchbell_desktop/npm_packages.dart';
import 'package:patchbell_desktop/watchlist.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> _record(String id, String date) => {
      'cve': {'id': id, 'published': date},
    };

NpmClient _emptyNpm() =>
    NpmClient(request: (_, {payload}) async => {'objects': [], 'total': 0});

class _MemoryPreferences implements SharedPreferencesAsync {
  final _values = <String, String>{};
  final _lists = <String, List<String>>{};
  String? get saved => _values.values.firstOrNull;

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<List<String>?> getStringList(String key) async => _lists[key];

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _lists[key] = List.of(value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAlerts extends DesktopAlerts {
  final titles = <String>[];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? productId,
    String? itemKey,
  }) async {
    titles.add(title);
  }
}

void main() {
  final dispatcher =
      TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
  setUp(() => dispatcher.localesTestValue = const [Locale('ko')]);
  tearDown(dispatcher.clearLocalesTestValue);

  test('queries the installed CPE version and collects all pages', () async {
    final calls = <Uri>[];
    final nvd = NvdClient(
      requestSpacing: Duration.zero,
      getPage: (uri) async {
        calls.add(uri);
        final index = int.parse(uri.queryParameters['startIndex']!);
        return {
          'startIndex': index,
          'totalResults': 2,
          'vulnerabilities': [
            index == 0
                ? _record('CVE-2099-1000', '2099-01-01T08:00:00')
                : _record('CVE-2099-1001', '2099-02-01T08:00:00'),
          ],
        };
      },
    );

    final records = await nvd.check(productsById['flutter']!, '3.27.4');
    expect(
        records.map((record) => record.id), ['CVE-2099-1001', 'CVE-2099-1000']);
    expect(records.first.published.isUtc, isTrue);
    expect(calls.map((call) => call.queryParameters['startIndex']), ['0', '1']);
    expect(
      calls.first.queryParameters['cpeName'],
      'cpe:2.3:a:flutter:flutter:3.27.4:*:*:*:*:*:*:*',
    );
    expect(calls.first.queryParameters, contains('isVulnerable'));
    expect(calls.first.queryParameters, contains('noRejected'));
  });

  test('an incomplete NVD response fails instead of showing zero matches', () {
    final nvd = NvdClient(getPage: (_) async {
      return {'startIndex': 0, 'totalResults': 4, 'vulnerabilities': []};
    });
    expect(
      nvd.check(productsById['dart']!, '3.6.2'),
      throwsFormatException,
    );
  });

  test('an unlinked SDK and its build tag can be saved and restored', () async {
    final prefs = _MemoryPreferences();
    final watchlist = Watchlist(
      preferences: prefs,
      client: NvdClient(getPage: (_) async {
        fail('An unlinked product must not be queried.');
      }),
      alerts: _RecordingAlerts(),
    );
    addTearDown(watchlist.dispose);
    await watchlist.load();
    final product = Product.custom(
      name: 'Custom toolchain',
      category: ProductCategory.sdk,
    );
    final version = product.normalizeVersion('nightly-2026.11.24');
    expect(version, 'nightly-2026.11.24');
    watchlist.register(product, version!);
    await watchlist.checkAll();
    await Future<void>.delayed(Duration.zero);

    final data = jsonDecode(prefs.saved!) as Map<String, dynamic>;
    final stored = TrackedVersion.fromJson(
      (data['items'] as List<dynamic>).single as Map<String, dynamic>,
    )!;
    expect(stored.product.name, 'Custom toolchain');
    expect(stored.product.cpe, isNull);
    expect(stored.checkedAt, isNull);
    expect(stored.version, version);
  });

  testWidgets(
      'the Mac menu counts affected versions and opens existing dialogs',
      (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final snapshots = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(macPlatformChannel, (call) async {
      expect(call.method, 'update');
      snapshots.add(call.arguments as Map<Object?, Object?>);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(macPlatformChannel, null);
    });

    final checkedAt = DateTime.now();
    final affected = TrackedVersion(
      product: productsById['flutter']!,
      version: '3.27.4',
      checkedAt: checkedAt,
      advisories: [
        Advisory(id: 'CVE-2099-1000', published: checkedAt),
        Advisory(id: 'CVE-2099-1001', published: checkedAt),
      ],
    );
    final clean = TrackedVersion(
      product: productsById['dart']!,
      version: '3.6.2',
      checkedAt: checkedAt,
    );
    final prefs = _MemoryPreferences();
    await prefs.setString(
      'patchbell.watchlist.v1',
      jsonEncode({
        'items': [affected.toJson(), clean.toJson()],
        'notifications': false,
      }),
    );
    await tester.pumpWidget(PatchbellApp(
      watchlist: Watchlist(
        preferences: prefs,
        client: NvdClient(),
        alerts: _RecordingAlerts(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(snapshots.last['affected'], [
      {
        'key': affected.key,
        'title': 'Flutter SDK 3.27.4 · 2건',
      },
    ]);
    expect(snapshots.last['labels'], containsPair('register', '등록하기…'));

    Future<void> sendMenuAction(String method, [Object? argument]) async {
      await messenger.handlePlatformMessage(
        macPlatformChannel.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, argument)),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await sendMenuAction('register');
    expect(find.text('직접 등록'), findsOneWidget);
    expect(find.text('제품 이름 검색'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await sendMenuAction('openItem', affected.key);
    expect(find.text('CVE-2099-1000'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('Windows tray badge counts items and clears after a check',
      (tester) async {
    const channel = MethodChannel('io.github.h0ng95.patchbell/window');
    final messenger = tester.binding.defaultBinaryMessenger;
    final updates = <List<Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setTrayBadge') {
        updates.add(call.arguments as List<Object?>);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final now = DateTime.now();
    final affected = TrackedVersion(
      product: productsById['flutter']!,
      version: '3.27.4',
      checkedAt: now,
      advisories: [
        Advisory(id: 'CVE-2099-1000', published: now),
        Advisory(id: 'CVE-2099-1001', published: now),
      ],
    );
    final preferences = _MemoryPreferences();
    await preferences.setString(
      'patchbell.watchlist.v1',
      jsonEncode({
        'items': [affected.toJson()],
        'notifications': false
      }),
    );
    final watchlist = Watchlist(
      preferences: preferences,
      client: NvdClient(
        getPage: (_) async => {
          'startIndex': 0,
          'totalResults': 0,
          'vulnerabilities': [],
        },
      ),
      alerts: _RecordingAlerts(),
    );
    await tester.pumpWidget(PatchbellApp(watchlist: watchlist));
    await tester.pumpAndSettle();
    expect(updates.last,
        [1, 'Patchbell · 확인할 항목 1개', '내 소프트웨어 열기', 'Patchbell 종료']);

    await tester.tap(find.text('보안 공지 확인'));
    await tester.pumpAndSettle();
    expect(updates.last, [0, 'Patchbell', '내 소프트웨어 열기', 'Patchbell 종료']);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('Windows test notifications show banner troubleshooting',
      (tester) async {
    final alerts = _RecordingAlerts();
    await tester.pumpWidget(PatchbellApp(
      watchlist: Watchlist(
        preferences: _MemoryPreferences(),
        client: NvdClient(),
        alerts: alerts,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('데스크톱 알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    final settingsButton = find.text('Windows 알림 설정 열기');
    expect(settingsButton, findsNothing);
    await tester.tap(find.text('테스트 알림'));
    await tester.pumpAndSettle();

    expect(alerts.titles, ['Patchbell 테스트 알림']);
    expect(find.text('테스트 알림을 보냈어요.'), findsOneWidget);
    expect(find.text('배너가 안 보이면 Windows 방해 금지 설정을 확인해 주세요.'), findsOneWidget);
    expect(settingsButton, findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(settingsButton, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('language and the top-bar theme toggle persist after reopening',
      (tester) async {
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    final preferences = _MemoryPreferences();
    final alerts = _RecordingAlerts();
    Watchlist createWatchlist() => Watchlist(
          preferences: preferences,
          client: NvdClient(),
          alerts: alerts,
        );
    await tester.pumpWidget(PatchbellApp(
      watchlist: createWatchlist(),
      preferences: preferences,
    ));
    await tester.pumpAndSettle();
    final koreanHome = find.text('내 소프트웨어');
    expect(Theme.of(tester.element(koreanHome)).brightness, Brightness.dark);
    await tester.tap(find.byTooltip('라이트 모드로 전환'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(koreanHome)).brightness, Brightness.light);
    expect((await AppSettings.load(preferences)).themeMode, ThemeMode.light);
    await tester.tap(find.byTooltip('다크 모드로 전환'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(koreanHome)).brightness, Brightness.dark);

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<ThemeMode>), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('My software'), findsOneWidget);
    expect(Theme.of(tester.element(find.text('My software'))).brightness,
        Brightness.dark);
    await tester.tap(find.text('Add software'));
    await tester.pumpAndSettle();
    expect(find.text('Search by product name'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desktop alerts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alerts for new advisories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test notification'));
    await tester.pumpAndSettle();
    expect(alerts.titles, ['Patchbell test notification']);
    expect(find.text('Test notification sent.'), findsOneWidget);

    final settings = await AppSettings.load(preferences);
    expect(settings.locale, const Locale('en'));
    expect(settings.themeMode, ThemeMode.dark);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(PatchbellApp(
      watchlist: createWatchlist(),
      preferences: preferences,
      settings: settings,
    ));
    await tester.pumpAndSettle();
    expect(find.text('My software'), findsOneWidget);
    expect(Theme.of(tester.element(find.text('My software'))).brightness,
        Brightness.dark);
    await tester.tap(find.byTooltip('Switch to light mode'));
    await tester.pumpAndSettle();
    final toggledSettings = await AppSettings.load(preferences);
    expect(toggledSettings.locale, const Locale('en'));
    expect(toggledSettings.themeMode, ThemeMode.light);
    await tester.pumpWidget(const SizedBox.shrink());
  },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.windows,
      }));

  testWidgets('registration combines presets with paginated NVD matches',
      (tester) async {
    final requests = <Uri>[];
    final watchlist = Watchlist(
      preferences: _MemoryPreferences(),
      alerts: _RecordingAlerts(),
      npm: _emptyNpm(),
      client: NvdClient(
        requestSpacing: Duration.zero,
        getPage: (uri) async {
          requests.add(uri);
          if (uri.path.contains('/cpes/')) {
            final startIndex = int.parse(uri.queryParameters['startIndex']!);
            return {
              'startIndex': startIndex,
              'totalResults': 4,
              'products': [
                {
                  'cpe': {
                    'cpeName': 'cpe:2.3:a:docker:desktop:4.41.2:*:*:*:*:*:*:*',
                  },
                },
                if (startIndex == 0)
                  {
                    'cpe': {
                      'cpeName':
                          'cpe:2.3:a:docker:desktop:4.41.3:*:*:*:*:*:*:*',
                    },
                  }
                else
                  {
                    'cpe': {
                      'cpeName':
                          'cpe:2.3:a:fixture:docker_compiler:1.2.0:*:*:*:*:*:*:*',
                    },
                  },
              ],
            };
          }
          return {'startIndex': 0, 'totalResults': 0, 'vulnerabilities': []};
        },
      ),
    );
    await tester.pumpWidget(PatchbellApp(watchlist: watchlist));
    await tester.pumpAndSettle();
    await tester.tap(find.text('항목 등록'));
    await tester.pumpAndSettle();
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, '인텔리제이');
    await tester.pump();
    expect(find.text('IntelliJ IDEA'), findsOneWidget);
    expect(requests, isEmpty);
    await tester.enterText(searchField, 'Doc');
    await tester.pump(const Duration(milliseconds: 200));
    expect(requests, isEmpty);
    await tester.enterText(searchField, 'Docker');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Docker Desktop'), findsOneWidget);
    expect(requests.single.queryParameters['keywordSearch'], 'Docker');
    expect(find.text('desktop'), findsNothing);
    await tester.tap(find.text('NVD 결과 더 보기'));
    await tester.pumpAndSettle();
    expect(
        requests.map((uri) => uri.queryParameters['startIndex']), ['0', '2']);
    expect(find.text('Docker Desktop'), findsOneWidget);
    expect(find.text('desktop'), findsNothing);
    expect(find.text('NVD 결과 더 보기'), findsNothing);
    await tester.tap(find.text('docker compiler'));
    await tester.pumpAndSettle();
    expect(find.text('fixture:docker_compiler'), findsOneWidget);
    final version = find.byType(TextFormField).last;
    await tester.ensureVisible(version);
    await tester.enterText(version, '1.2.0');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(watchlist.items.single.product.cpe, 'fixture:docker_compiler');
    expect(
      requests.last.queryParameters['cpeName'],
      'cpe:2.3:a:fixture:docker_compiler:1.2.0:*:*:*:*:*:*:*',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('NestJS can be registered while NVD is slow and checked by OSV',
      (tester) async {
    final nvdResponse = Completer<Map<String, dynamic>>();
    final osvRequests = <Map<String, Object?>>[];
    final prefs = _MemoryPreferences();
    final alerts = _RecordingAlerts();
    await prefs.setString('patchbell.watchlist.v1',
        jsonEncode({'notifications': true, 'items': []}));
    final watchlist = Watchlist(
      preferences: prefs,
      alerts: alerts,
      client: NvdClient(
        requestSpacing: Duration.zero,
        getPage: (_) => nvdResponse.future,
      ),
      npm: NpmClient(request: (uri, {payload}) async {
        if (payload == null) {
          expect(uri.host, 'registry.npmjs.org');
          expect(uri.queryParameters['text'], 'nest');
          return {
            'total': 2,
            'objects': [
              {
                'package': {'name': '@nestjs/core', 'version': '11.1.9'}
              },
              {
                'package': {'name': '@nestjs/common', 'version': '11.1.9'}
              },
            ],
          };
        }
        expect(uri.host, 'api.osv.dev');
        osvRequests.add(payload);
        if (payload['page_token'] == null) {
          return {'next_page_token': 'second'};
        }
        return {
          'vulns': [
            {'id': 'GHSA-TEST-TEST-TEST', 'modified': '2026-01-01T00:00:00Z'},
          ],
        };
      }),
    );
    await tester.pumpWidget(PatchbellApp(watchlist: watchlist));
    await tester.pumpAndSettle();
    await tester.tap(find.text('항목 등록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nest');
    await tester.pump();
    expect(find.text('@nestjs/core'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('@nestjs/core'), findsOneWidget);
    expect(find.text('@nestjs/common'), findsOneWidget);
    expect(find.text('NVD 검색 중…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.text('NVD 다시 시도'), findsOneWidget);
    expect(find.text('@nestjs/core'), findsOneWidget);
    nvdResponse.complete({'products': [], 'totalResults': 0, 'startIndex': 0});

    await tester.tap(find.text('@nestjs/core'));
    await tester.pumpAndSettle();
    expect(find.text('npm · @nestjs/core'), findsOneWidget);
    final versionField = find.byType(TextFormField).last;
    await tester.ensureVisible(versionField);
    await tester.enterText(versionField, '11.1.6');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(osvRequests.first, {
      'package': {'ecosystem': 'npm', 'name': '@nestjs/core'},
      'version': '11.1.6',
    });
    expect(osvRequests.last['page_token'], 'second');
    expect(alerts.titles, ['@nestjs/core 보안 공지']);
    expect(find.text('공지 1건'), findsOneWidget);
    final saved =
        jsonDecode(prefs.saved!)['items'].single as Map<String, dynamic>;
    final restored = TrackedVersion.fromJson(saved)!;
    expect(restored.product.identity, 'npm:@nestjs/core');
    expect(restored.advisories.single.url.host, 'osv.dev');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a custom SDK can be linked, checked, and restored',
      (tester) async {
    final prefs = _MemoryPreferences();
    final alerts = _RecordingAlerts();
    final requests = <Uri>[];
    final client = NvdClient(
      requestSpacing: Duration.zero,
      getPage: (uri) async {
        requests.add(uri);
        if (uri.path.contains('/cpes/')) {
          return {
            'startIndex': 0,
            'totalResults': 2,
            'products': [
              for (final version in ['1.83.0', '1.84.0'])
                {
                  'cpe': {
                    'deprecated': false,
                    'cpeName':
                        'cpe:2.3:a:rust-lang:rust:$version:*:*:*:*:*:*:*',
                  },
                },
            ],
          };
        }
        return {
          'startIndex': 0,
          'totalResults': 1,
          'vulnerabilities': [_record('CVE-2099-1000', '2099-01-01T08:00:00')],
        };
      },
    );
    Watchlist createWatchlist() => Watchlist(
          preferences: prefs,
          client: client,
          alerts: alerts,
          npm: _emptyNpm(),
        );

    await tester.pumpWidget(PatchbellApp(watchlist: createWatchlist()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('데스크톱 알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 보안 공지 알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('항목 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('직접 등록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Rust SDK');
    await tester.enterText(find.byType(TextFormField).at(1), '1.84.0');
    final link = find.text('제품·패키지 검색 및 연결');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('rust'), findsOneWidget);
    await tester.tap(find.text('rust'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('Rust SDK'), findsOneWidget);
    expect(find.text('공지 1건'), findsOneWidget);
    expect(requests.first.queryParameters['keywordSearch'], 'Rust SDK');
    expect(requests.last.queryParameters['cpeName'],
        'cpe:2.3:a:rust-lang:rust:1.84.0:*:*:*:*:*:*:*');
    expect(jsonDecode(prefs.saved!)['items'], hasLength(1));
    expect(alerts.titles, ['Rust SDK 보안 공지']);

    await tester.tap(find.text('Rust SDK'));
    await tester.pumpAndSettle();
    expect(find.text('CVE-2099-1000'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(PatchbellApp(watchlist: createWatchlist()));
    await tester.pumpAndSettle();
    expect(find.text('Rust SDK'), findsOneWidget);
    expect(find.text('공지 1건'), findsOneWidget);
    expect(requests, hasLength(2));
    await tester.tap(find.text('보안 공지 확인'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(3));
    expect(alerts.titles, ['Rust SDK 보안 공지']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
