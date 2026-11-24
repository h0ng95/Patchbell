import 'package:flutter/foundation.dart';
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

  @override
  Widget build(BuildContext context) {
    final text = PatchbellText.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    final language = _languageField(context, text: text, windows: windows);
    void cancel() => Navigator.pop(context);
    const actionSize = Size(78, 36);
    final actionShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));

    return AlertDialog(
      scrollable: windows,
      backgroundColor: windows ? colors.surface : null,
      elevation: windows ? 16 : null,
      shadowColor: windows ? Colors.black.withValues(alpha: 0.26) : null,
      surfaceTintColor: windows ? Colors.transparent : null,
      shape: windows
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.outlineVariant),
            )
          : null,
      insetPadding: windows
          ? const EdgeInsets.symmetric(horizontal: 24, vertical: 20)
          : null,
      titlePadding: windows ? const EdgeInsets.fromLTRB(22, 18, 22, 0) : null,
      contentPadding:
          windows ? const EdgeInsets.fromLTRB(22, 16, 22, 16) : null,
      actionsPadding: windows ? const EdgeInsets.fromLTRB(22, 0, 22, 18) : null,
      title: windows
          ? Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      Icon(Icons.tune_rounded, size: 18, color: colors.primary),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(text.settings,
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 20, fontWeight: FontWeight.w600)),
                ),
              ],
            )
          : Text(text.settings),
      content: SizedBox(
        width: 350,
        child: windows
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: language,
              )
            : language,
      ),
      actions: [
        if (windows)
          OutlinedButton(
            onPressed: cancel,
            style: OutlinedButton.styleFrom(
              minimumSize: actionSize,
              shape: actionShape,
              side: BorderSide(color: colors.outlineVariant),
              foregroundColor: colors.onSurface,
            ),
            child: Text(text.cancel),
          )
        else
          TextButton(onPressed: cancel, child: Text(text.cancel)),
        FilledButton(
          style: windows
              ? FilledButton.styleFrom(
                  minimumSize: actionSize,
                  shape: actionShape,
                )
              : null,
          onPressed: () => Navigator.pop(
            context,
            AppSettings(
              locale: _language == 'system' ? null : Locale(_language),
              themeMode: widget.settings.themeMode,
            ),
          ),
          child: Text(text.save),
        ),
      ],
    );
  }

  Widget _languageField(
    BuildContext context, {
    required PatchbellText text,
    required bool windows,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    final field = DropdownButtonFormField<String>(
      value: _language,
      isExpanded: windows,
      icon: windows ? const Icon(Icons.unfold_more_rounded, size: 17) : null,
      borderRadius: windows ? BorderRadius.circular(8) : null,
      dropdownColor: windows ? colors.surface : null,
      decoration: windows
          ? InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: border,
              enabledBorder: border,
            )
          : InputDecoration(labelText: text.language),
      items: [
        DropdownMenuItem(value: 'system', child: Text(text.system)),
        const DropdownMenuItem(value: 'ko', child: Text('한국어')),
        const DropdownMenuItem(value: 'en', child: Text('English')),
      ],
      onChanged: (selected) {
        if (selected != null) setState(() => _language = selected);
      },
    );
    if (!windows) return field;

    final labelWidget = ExcludeSemantics(
      child: Text(text.language, style: theme.textTheme.bodyMedium),
    );
    final control = Semantics(label: text.language, child: field);
    final stacked = MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(14) > 21;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [labelWidget, const SizedBox(height: 6), control],
            )
          : Row(
              children: [
                Expanded(child: labelWidget),
                const SizedBox(width: 12),
                SizedBox(width: 156, child: control),
              ],
            ),
    );
  }
}

ThemeData patchbellTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final windows = defaultTargetPlatform == TargetPlatform.windows;
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
    typography: windows
        ? Typography.material2021(
            platform: TargetPlatform.macOS,
            colorScheme: colors,
          )
        : null,
    fontFamily: windows ? 'Pretendard' : null,
    scaffoldBackgroundColor:
        dark ? const Color(0xff101916) : const Color(0xfff2f6ed),
    useMaterial3: true,
    inputDecorationTheme:
        const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
