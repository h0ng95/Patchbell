import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

class AppSettings {
  const AppSettings({this.locale, this.themeMode = ThemeMode.system});

  static const _storageKey = 'patchbell.appearance.v1';
  final Locale? locale;
  final ThemeMode themeMode;

  static Future<AppSettings> load(SharedPreferencesAsync preferences) async {
    try {
      final saved = await preferences.getStringList(_storageKey);
      if (saved != null && saved.length == 2) {
        return AppSettings(
          locale: switch (saved[0]) {
            'ko' => const Locale('ko'),
            'en' => const Locale('en'),
            _ => null,
          },
          themeMode: ThemeMode.values.byName(saved[1]),
        );
      }
    } catch (_) {
      // System defaults also apply when preferences cannot be read.
    }
    return const AppSettings();
  }

  Future<void> save(SharedPreferencesAsync preferences) =>
      preferences.setStringList(
        _storageKey,
        [locale?.languageCode ?? 'system', themeMode.name],
      );
}

class AppSettingsDialog extends StatefulWidget {
  const AppSettingsDialog({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends State<AppSettingsDialog> {
  late String _language = widget.settings.locale?.languageCode ?? 'system';
  late ThemeMode _mode = widget.settings.themeMode;

  @override
  Widget build(BuildContext context) {
    final text = PatchbellText.of(context);
    return AlertDialog(
      title: Text(text.settings),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _language,
              decoration: InputDecoration(labelText: text.language),
              items: [
                DropdownMenuItem(value: 'system', child: Text(text.system)),
                const DropdownMenuItem(value: 'ko', child: Text('한국어')),
                const DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (value) => setState(() => _language = value!),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<ThemeMode>(
              value: _mode,
              decoration: InputDecoration(labelText: text.appearance),
              items: [
                DropdownMenuItem(
                    value: ThemeMode.system, child: Text(text.system)),
                DropdownMenuItem(
                    value: ThemeMode.light, child: Text(text.light)),
                DropdownMenuItem(value: ThemeMode.dark, child: Text(text.dark)),
              ],
              onChanged: (value) => setState(() => _mode = value!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(text.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            AppSettings(
              locale: _language == 'system' ? null : Locale(_language),
              themeMode: _mode,
            ),
          ),
          child: Text(text.save),
        ),
      ],
    );
  }
}

ThemeData patchbellTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: const Color(0xff4e7832),
  ).copyWith(
    primary: dark ? const Color(0xffc9f88b) : const Color(0xff315b24),
    onPrimary: dark ? const Color(0xff1b301c) : Colors.white,
    surface: dark ? const Color(0xff19271f) : const Color(0xfffffff9),
    onSurface: dark ? const Color(0xffeff5ed) : const Color(0xff18251e),
    onSurfaceVariant: dark ? const Color(0xffacc0b1) : const Color(0xff405649),
    outline: dark ? const Color(0xff667d6e) : const Color(0xff63796a),
    outlineVariant: dark ? const Color(0xff364a3d) : const Color(0xffccd9cd),
    secondaryContainer:
        dark ? const Color(0xff26392c) : const Color(0xffe3eedb),
    tertiary: dark ? const Color(0xfff7d68f) : const Color(0xff735015),
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor:
        dark ? const Color(0xff101916) : const Color(0xfff2f6ed),
    useMaterial3: true,
    inputDecorationTheme:
        const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
