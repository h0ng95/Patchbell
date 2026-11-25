import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advisories.dart';
import 'catalog.dart';
import 'desktop_alerts.dart';
import 'npm_packages.dart';
import 'strings.dart';

const checkInterval = Duration(hours: 2);

enum _NotificationStatus {
  alertFailed,
  permissionRequired,
  enableFailed,
  testSent,
  testFailed,
}

class TrackedVersion {
  const TrackedVersion({
    required this.product,
    required this.version,
    this.checkedAt,
    this.advisories = const [],
    this.notified = const {},
  });

  final Product product;
  final String version;
  final DateTime? checkedAt;
  final List<Advisory> advisories;
  final Set<String> notified;

  String get key => '${product.identity}:$version';

  TrackedVersion withResult({
    required DateTime checkedAt,
    required List<Advisory> advisories,
    required Set<String> notified,
  }) {
    return TrackedVersion(
      product: product,
      version: version,
      checkedAt: checkedAt,
      advisories: advisories,
      notified: notified,
    );
  }

  Map<String, Object?> toJson() => {
        'productId': product.id,
        if (product.id.startsWith('custom:'))
          'custom': {
            'name': product.name,
            'category': product.category.name,
            'cpe': product.cpe,
            if (product.npmPackage != null) 'npmPackage': product.npmPackage,
            if (product.macBundleId != null) 'macBundleId': product.macBundleId,
          },
        'version': version,
        'checkedAt': checkedAt?.toIso8601String(),
        'advisories': advisories.map((record) => record.toJson()).toList(),
        'notified': notified.toList(),
      };

  static TrackedVersion? fromJson(Map<String, dynamic> json) {
    final custom = json['custom'] as Map<String, dynamic>?;
    final product = custom == null
        ? productsById[json['productId']]
        : Product.custom(
            name: custom['name'] as String,
            category:
                ProductCategory.values.byName(custom['category'] as String),
            cpe: custom['cpe'] as String?,
            npmPackage: custom['npmPackage'] as String?,
            macBundleId: custom['macBundleId'] as String?,
          );
    final version = product?.normalizeVersion(json['version'] as String);
    if (product == null || version == null) return null;
    final checkedAt = json['checkedAt'] as String?;
    return TrackedVersion(
      product: product,
      version: version,
      checkedAt: checkedAt == null ? null : DateTime.parse(checkedAt),
      advisories: (json['advisories'] as List<dynamic>)
          .map((value) => Advisory.fromJson(value as Map<String, dynamic>))
          .toList(),
      notified: (json['notified'] as List<dynamic>).cast<String>().toSet(),
    );
  }
}

class Watchlist extends ChangeNotifier {
  Watchlist({
    required SharedPreferencesAsync preferences,
    required NvdClient client,
    required DesktopAlerts alerts,
    NpmClient? npm,
  })  : _preferences = preferences,
        _client = client,
        _alerts = alerts,
        _npm = npm ?? NpmClient();

  static const _storageKey = 'patchbell.watchlist.v1';
  final SharedPreferencesAsync _preferences;
  final NvdClient _client;
  final NpmClient _npm;
  final DesktopAlerts _alerts;
  final _items = <TrackedVersion>[];
  final _errors = <String, LocalizedMessage>{};
  Future<void> _pendingSave = Future.value();
  Timer? _timer;
  bool _disposed = false;
  bool _checkAgain = false;
  bool _loading = false;
  bool loaded = false;
  bool checking = false;
  bool notifications = false;
  bool changingNotifications = false;
  String? checkingKey;
  PatchbellText text = PatchbellText.english;
  bool _loadFailed = false;
  bool _storageFailed = false;
  _NotificationStatus? _notificationStatus;

  List<TrackedVersion> get items => List.unmodifiable(_items);
  int get affectedCount =>
      _items.where((item) => item.advisories.isNotEmpty).length;
  String? get loadError => _loadFailed ? text.loadFailed : null;
  String? get storageError => _storageFailed ? text.storageFailed : null;
  bool get testAlertSent => _notificationStatus == _NotificationStatus.testSent;
  String? get notificationMessage => switch (_notificationStatus) {
        _NotificationStatus.alertFailed => text.alertFailed,
        _NotificationStatus.permissionRequired => text.alertPermission,
        _NotificationStatus.enableFailed => text.alertEnableFailed,
        _NotificationStatus.testSent => text.testAlertSent,
        _NotificationStatus.testFailed => text.testAlertFailed,
        null => null,
      };
  String? checkError(TrackedVersion item) => _errors[item.key]?.call(text);
  Future<CatalogPage> searchProducts(String term, {int startIndex = 0}) =>
      _client.searchProducts(term, startIndex: startIndex);
  Future<CatalogPage> searchPackages(String term, {int startIndex = 0}) =>
      _npm.searchPackages(term, startIndex: startIndex);

  Future<void> load() async {
    if (loaded || _loading || _disposed) return;
    _loading = true;
    _loadFailed = false;
    _update();
    try {
      final raw = await _preferences.getString(_storageKey);
      if (_disposed) return;
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final items = (data['items'] as List<dynamic>)
            .map((value) =>
                TrackedVersion.fromJson(value as Map<String, dynamic>))
            .whereType<TrackedVersion>();
        _items
          ..clear()
          ..addAll(items);
        notifications = data['notifications'] as bool;
      }
      loaded = true;
      _timer = Timer.periodic(
        checkInterval,
        (_) => unawaited(checkAll(onlyDue: true)),
      );
      unawaited(checkAll(onlyDue: true));
    } catch (error) {
      _loadFailed = true;
    } finally {
      _loading = false;
      _update();
    }
  }

  bool contains(Product product, String version, {TrackedVersion? except}) =>
      _items.any((item) =>
          (item.product.identity == product.identity ||
              (product.macBundleId != null &&
                  item.product.macBundleId == product.macBundleId)) &&
          item.version == version &&
          item.key != except?.key);

  void register(Product product, String version, {TrackedVersion? previous}) {
    final index = _items.indexWhere((item) => item.key == previous?.key);
    final existing = index == -1 ? null : _items[index];
    final sameVersion = existing != null &&
        existing.product.cpe == product.cpe &&
        existing.product.npmPackage == product.npmPackage &&
        existing.product.macBundleId == product.macBundleId &&
        existing.version == version;
    if (sameVersion &&
        existing.product.name == product.name &&
        existing.product.category == product.category) {
      return;
    }
    final item = TrackedVersion(
      product: product,
      version: version,
      checkedAt: sameVersion ? existing.checkedAt : null,
      advisories: sameVersion ? existing.advisories : const [],
      notified: sameVersion ? existing.notified : const {},
    );
    if (previous == null) {
      _items.add(item);
    } else {
      if (index == -1) return;
      _items[index] = item;
      _errors.remove(previous.key);
    }
    _save();
    _update();

    if (checking) {
      _checkAgain = true;
    } else {
      unawaited(checkAll(onlyDue: true));
    }
  }

  void remove(TrackedVersion item) {
    _items.removeWhere((existing) => existing.key == item.key);
    _errors.remove(item.key);
    _save();
    _update();
  }

  Future<void> checkAll({bool onlyDue = false}) async {
    if (!loaded || checking || _disposed) return;
    final threshold = DateTime.now().subtract(checkInterval);
    final batch = _items
        .where((item) =>
            item.product.canCheck &&
            (!onlyDue ||
                item.checkedAt == null ||
                item.checkedAt!.isBefore(threshold)))
        .toList();
    if (batch.isEmpty) return;

    checking = true;
    try {
      for (final item in batch) {
        if (_disposed) return;
        if (!_items.contains(item)) continue;
        checkingKey = item.key;
        _errors.remove(item.key);
        _update();
        await _checkOne(item);
      }
    } finally {
      checking = false;
      checkingKey = null;
      _update();
      if (_checkAgain && !_disposed) {
        _checkAgain = false;
        unawaited(checkAll(onlyDue: true));
      }
    }
  }

  Future<void> _checkOne(TrackedVersion item) async {
    try {
      final records = await (item.product.npmPackage == null
          ? _client.check(item.product, item.version)
          : _npm.check(item.product, item.version));
      if (_disposed || !_items.contains(item)) return;
      final checkedAt = DateTime.now();
      final checked = item.withResult(
        checkedAt: checkedAt,
        advisories: records,
        notified: item.notified,
      );
      _items[_items.indexOf(item)] = checked;
      _save();
      _update();

      final fresh =
          records.where((record) => !item.notified.contains(record.id));
      if (notifications && fresh.isNotEmpty) {
        try {
          await _alerts.show(
            id: item.key.hashCode & 0x7fffffff,
            title: text.alertTitle(text.productName(item.product)),
            body: text.alertBody(item.version, fresh.length),
            productId: item.product.id,
            itemKey: item.key,
          );
          final index = _items.indexOf(checked);
          if (!_disposed && index != -1) {
            _items[index] = checked.withResult(
              checkedAt: checkedAt,
              advisories: records,
              notified: {...item.notified, ...fresh.map((record) => record.id)},
            );
            _save();
          }
        } catch (_) {
          _notificationStatus = _NotificationStatus.alertFailed;
        }
      }
    } catch (error) {
      if (_items.contains(item)) {
        _errors[item.key] = error is AdvisoryRequestException
            ? error.message
            : (text) => text.advisoriesFailed;
      }
    }
    _update();
  }

  Future<void> setNotifications(bool enabled) async {
    if (changingNotifications) return;
    changingNotifications = true;
    _notificationStatus = null;
    _update();
    try {
      notifications = enabled && await _alerts.requestPermission();
      if (enabled && !notifications) {
        _notificationStatus = _NotificationStatus.permissionRequired;
      }
      _save();
    } catch (_) {
      _notificationStatus = _NotificationStatus.enableFailed;
    } finally {
      changingNotifications = false;
      _update();
    }
  }

  Future<void> sendTestAlert() async {
    try {
      await _alerts.show(
        id: 0,
        title: text.testAlertTitle,
        body: text.testAlertBody,
      );
      _notificationStatus = _NotificationStatus.testSent;
    } catch (_) {
      _notificationStatus = _NotificationStatus.testFailed;
    }
    _update();
  }

  void _save() {
    final snapshot = jsonEncode({
      'items': _items.map((item) => item.toJson()).toList(),
      'notifications': notifications,
    });
    _pendingSave = _pendingSave.then((_) async {
      try {
        await _preferences.setString(_storageKey, snapshot);
        _storageFailed = false;
      } catch (_) {
        _storageFailed = true;
      }
      _update();
    });
  }

  void _update() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
