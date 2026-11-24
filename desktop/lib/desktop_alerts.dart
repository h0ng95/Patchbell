import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import 'catalog.dart';
import 'mac_platform.dart';

class DesktopAlerts {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _initialization;

  Future<bool> _initialize() async {
    try {
      final ready = await (_initialization ??= _setup());
      if (!ready) _initialization = null;
      return ready;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<bool> _setup() async {
    final initialized = await _plugin.initialize(
      const InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: 'Patchbell',
          appUserModelId: 'io.github.h0ng95.Patchbell',
          guid: 'e382adf5-6b1e-4a9f-bf89-b10e68b1aac5',
        ),
      ),
      onDidReceiveNotificationResponse: (response) async {
        final link = productsById[response.payload]?.updateUrl;
        if (link != null) await launchUrl(Uri.parse(link));
      },
    );
    return initialized == true;
  }

  Future<bool> requestPermission() async {
    if (Platform.isMacOS) {
      return await macPlatformChannel
              .invokeMethod<bool>('requestNotifications') ??
          false;
    }
    return _initialize();
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? productId,
    String? itemKey,
  }) async {
    if (Platform.isMacOS) {
      await macPlatformChannel.invokeMethod<void>('showNotification', {
        'id': id,
        'title': title,
        'body': body,
        if (itemKey != null) 'itemKey': itemKey,
      });
      return;
    }
    if (!await _initialize()) {
      throw StateError('Desktop notifications could not be initialized.');
    }
    await _plugin.show(id, title, body, const NotificationDetails(),
        payload: productId);
  }
}
