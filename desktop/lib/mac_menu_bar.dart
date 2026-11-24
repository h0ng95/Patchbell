import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mac_platform.dart';
import 'watchlist.dart';

/// Shares the running watchlist with the native macOS status menu.
class MacMenuBar {
  MacMenuBar({
    required this.watchlist,
    required this.onRegister,
    required this.onScanInstalled,
    required this.onOpenItem,
    required this.onOpenAlerts,
  });

  final Watchlist watchlist;
  final VoidCallback onRegister;
  final VoidCallback onScanInstalled;
  final ValueChanged<String> onOpenItem;
  final VoidCallback onOpenAlerts;

  void connect() {
    macPlatformChannel.setMethodCallHandler(_handleAction);
    watchlist.addListener(refresh);
    refresh();
  }

  void disconnect() {
    watchlist.removeListener(refresh);
    macPlatformChannel.setMethodCallHandler(null);
  }

  void refresh() => unawaited(_updateNativeMenu());

  Future<void> _updateNativeMenu() async {
    final items = watchlist.items;
    final text = watchlist.text;
    final affected = items.where((item) => item.advisories.isNotEmpty).toList()
      ..sort((a, b) =>
          b.advisories.first.published.compareTo(a.advisories.first.published));
    try {
      await macPlatformChannel.invokeMethod<void>('update', {
        'loaded': watchlist.loaded,
        'loadFailed': watchlist.loadError != null,
        'checking': watchlist.checking,
        'canCheck': items.any((item) => item.product.canCheck),
        'checkFailed': items.any((item) => watchlist.checkError(item) != null),
        'notifications': watchlist.notifications,
        'labels': {
          'badge': text.menuBadge(affected.length),
          'affected': text.menuAffected(affected.length),
          'loadFailed': text.menuLoadFailed,
          'loading': text.menuLoading,
          'noAdvisories': text.menuNoAdvisories,
          'checking': text.menuChecking,
          'checkFailed': text.menuCheckFailed,
          'register': text.menuRegister,
          'scan': '${text.scan}…',
          'open': text.menuOpen,
          'check': text.checkAdvisories,
          'alerts': '${text.desktopAlerts}…',
          'quit': text.menuQuit,
        },
        'affected': [
          for (final item in affected)
            {
              'key': item.key,
              'title': '${text.productName(item.product)} ${item.version} · '
                  '${text.menuAdvisoryCount(item.advisories.length)}',
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
        refresh();
      case 'register':
        onRegister();
      case 'scanInstalled':
        onScanInstalled();
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
