import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import 'catalog.dart';

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
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
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
    // With all permission prompts deferred, the macOS plugin returns false
    // after recording the settings. Permission is requested separately.
    return Platform.isMacOS || initialized == true;
  }

  Future<bool> requestPermission() async {
    if (!await _initialize()) return false;
    if (!Platform.isMacOS) return true;
    return await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true) ??
        false;
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? productId,
  }) async {
    if (!await _initialize()) {
      throw StateError('Desktop notifications could not be initialized.');
    }
    await _plugin.show(id, title, body, const NotificationDetails(),
        payload: productId);
  }
}
