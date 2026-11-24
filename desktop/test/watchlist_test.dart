import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patchbell_desktop/advisories.dart';
import 'package:patchbell_desktop/catalog.dart';
import 'package:patchbell_desktop/desktop_alerts.dart';
import 'package:patchbell_desktop/mac_menu_bar.dart';
import 'package:patchbell_desktop/main.dart';
import 'package:patchbell_desktop/watchlist.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> _record(String id, String date) => {
      'cve': {'id': id, 'published': date},
    };

class _MemoryPreferences implements SharedPreferencesAsync {
  final _values = <String, String>{};
  String? get saved => _values.values.firstOrNull;

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

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
  }) async {
    titles.add(title);
  }
}

void main() {
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
    messenger.setMockMethodCallHandler(MacMenuBar.channel, (call) async {
      expect(call.method, 'update');
      snapshots.add(call.arguments as Map<Object?, Object?>);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(MacMenuBar.channel, null);
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
        'name': 'Flutter SDK',
        'version': '3.27.4',
        'advisories': 2,
      },
    ]);

    Future<void> sendMenuAction(String method, [Object? argument]) async {
      await messenger.handlePlatformMessage(
        MacMenuBar.channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, argument)),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await sendMenuAction('register');
    expect(find.text('직접 등록'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await sendMenuAction('openItem', affected.key);
    expect(find.text('CVE-2099-1000'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

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
    final link = find.text('NVD 제품 검색 및 연결');
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
