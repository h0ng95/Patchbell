import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'watchlist.dart';

/// Shares the running watchlist with the native macOS status menu.
class MacMenuBar {
  MacMenuBar({
    required this.watchlist,
    required this.onRegister,
    required this.onOpenItem,
    required this.onOpenAlerts,
  });

  static const channel =
      MethodChannel('io.github.h0ng95.patchbell/status_menu');

  final Watchlist watchlist;
  final VoidCallback onRegister;
  final ValueChanged<String> onOpenItem;
  final VoidCallback onOpenAlerts;

  void connect() {
    channel.setMethodCallHandler(_handleAction);
    watchlist.addListener(_sendStatus);
    _sendStatus();
  }

  void disconnect() {
    watchlist.removeListener(_sendStatus);
    channel.setMethodCallHandler(null);
  }

  void _sendStatus() => unawaited(_updateNativeMenu());

  Future<void> _updateNativeMenu() async {
    final items = watchlist.items;
    final affected = items.where((item) => item.advisories.isNotEmpty).toList()
      ..sort((a, b) =>
          b.advisories.first.published.compareTo(a.advisories.first.published));
    try {
      await channel.invokeMethod<void>('update', {
        'loaded': watchlist.loaded,
        'loadFailed': watchlist.loadError != null,
        'checking': watchlist.checking,
        'canCheck': items.any((item) => item.product.cpe != null),
        'checkFailed': items.any((item) => watchlist.checkError(item) != null),
        'notifications': watchlist.notifications,
        'affected': [
          for (final item in affected)
            {
              'key': item.key,
              'name': item.product.name,
              'version': item.version,
              'advisories': item.advisories.length,
            },
        ],
      });
    } on MissingPluginException {
      // AppKit requests a fresh snapshot when its status menu is ready.
    } on PlatformException catch (error) {
      debugPrint('Patchbell could not refresh its menu bar: ${error.code}');
    }
  }

  Future<void> _handleAction(MethodCall call) async {
    switch (call.method) {
      case 'requestStatus':
        _sendStatus();
      case 'register':
        onRegister();
      case 'openItem':
        if (call.arguments case final String key) onOpenItem(key);
      case 'openAlerts':
        onOpenAlerts();
      case 'check':
        unawaited(watchlist.checkAll());
      default:
        throw MissingPluginException(call.method);
    }
  }
}
