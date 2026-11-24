import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'advisories.dart';
import 'app_settings.dart';
import 'catalog.dart';
import 'desktop_alerts.dart';
import 'installed_software.dart';
import 'installed_software_dialog.dart';
import 'mac_menu_bar.dart';
import 'registration_dialog.dart';
import 'strings.dart';
import 'watchlist.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = SharedPreferencesAsync();
  final settings = await AppSettings.load(preferences);
  runApp(PatchbellApp(
    preferences: preferences,
    settings: settings,
    watchlist: Watchlist(
      preferences: preferences,
      client: NvdClient(),
      alerts: DesktopAlerts(),
    ),
  ));
}

class PatchbellApp extends StatefulWidget {
  const PatchbellApp({
    super.key,
    required this.watchlist,
    this.preferences,
    this.settings = const AppSettings(),
  });

  final Watchlist watchlist;
  final SharedPreferencesAsync? preferences;
  final AppSettings settings;

  @override
  State<PatchbellApp> createState() => _PatchbellAppState();
}

class _PatchbellAppState extends State<PatchbellApp> {
  late AppSettings _settings = widget.settings;

  Future<bool> _applySettings(AppSettings settings) async {
    final preferences = widget.preferences;
    if (preferences != null) {
      try {
        await settings.save(preferences);
      } catch (_) {
        return false;
      }
    }
    if (mounted) setState(() => _settings = settings);
    return true;
  }

  @override
  void dispose() {
    widget.watchlist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Patchbell',
        debugShowCheckedModeBanner: false,
        supportedLocales: PatchbellText.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        locale: _settings.locale,
        theme: patchbellTheme(Brightness.light),
        darkTheme: patchbellTheme(Brightness.dark),
        themeMode: _settings.themeMode,
        home: _Home(
          watchlist: widget.watchlist,
          settings: _settings,
          onSettingsChanged: _applySettings,
        ),
      );
}

IconData _categoryIcon(ProductCategory category) => switch (category) {
      ProductCategory.app => Icons.apps_rounded,
      ProductCategory.editor => Icons.edit_note_rounded,
      ProductCategory.sdk => Icons.inventory_2_outlined,
      ProductCategory.runtime => Icons.code_rounded,
    };

String _date(BuildContext context, DateTime value, {bool includeTime = false}) {
  final date = value.toLocal();
  final localizations = MaterialLocalizations.of(context);
  final day = localizations.formatCompactDate(date);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
  return includeTime ? '$day $time' : day;
}

Future<void> _open(BuildContext context, Uri url) async {
  try {
    if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // The same feedback applies when the platform cannot open the URL.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(PatchbellText.of(context).linkFailed)),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({
    required this.watchlist,
    required this.settings,
    required this.onSettingsChanged,
  });

  final Watchlist watchlist;
  final AppSettings settings;
  final Future<bool> Function(AppSettings) onSettingsChanged;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  ProductCategory? _filter;
  MacMenuBar? _menuBar;
  bool _savingSettings = false;
  bool _loadingStarted = false;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _menuBar = MacMenuBar(
        watchlist: widget.watchlist,
        onRegister: () {
          if (_canOpenMenuDialog) unawaited(_register());
        },
        onScanInstalled: () {
          if (_canOpenMenuDialog) unawaited(_scanInstalled());
        },
        onOpenItem: _openMenuItem,
        onOpenAlerts: () {
          if (_canOpenMenuDialog) _showAlerts();
        },
      )..connect();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = PatchbellText.of(context);
    if (current.locale != widget.watchlist.text.locale) {
      widget.watchlist.text = current;
      _menuBar?.refresh();
    }
    if (!_loadingStarted) {
      _loadingStarted = true;
      unawaited(widget.watchlist.load());
    }
  }

  @override
  void dispose() {
    _menuBar?.disconnect();
    super.dispose();
  }

  bool get _canOpenMenuDialog =>
      mounted &&
      widget.watchlist.loaded &&
      ModalRoute.of(context)?.isCurrent == true;

  void _openMenuItem(String key) {
    if (!_canOpenMenuDialog) return;
    for (final item in widget.watchlist.items) {
      if (item.key == key) {
        _showDetails(context, item, widget.watchlist.checkError(item));
        return;
      }
    }
  }

  Future<void> _register([TrackedVersion? item]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          RegistrationDialog(watchlist: widget.watchlist, item: item),
    );
    if (saved == true && mounted) setState(() => _filter = null);
  }

  Future<void> _scanInstalled() async {
    final watchlist = widget.watchlist;
    final selected = await showDialog<List<InstalledSoftware>>(
      context: context,
      builder: (_) => InstalledSoftwareDialog(isRegistered: watchlist.contains),
    );
    if (!mounted || selected == null) return;
    for (final item in selected) {
      if (!watchlist.contains(item.product, item.version)) {
        watchlist.register(item.product, item.version);
      }
    }
    setState(() => _filter = null);
  }

  Future<void> _showSettings() async {
    final settings = await showDialog<AppSettings>(
      context: context,
      builder: (_) => AppSettingsDialog(settings: widget.settings),
    );
    if (!mounted || settings == null) return;
    setState(() => _savingSettings = true);
    final saved = await widget.onSettingsChanged(settings);
    if (!mounted) return;
    setState(() => _savingSettings = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(PatchbellText.of(context).settingsSaveFailed)),
      );
    }
  }

  void _showAlerts() {
    final watchlist = widget.watchlist;
    showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: watchlist,
        builder: (context, _) {
          final text = PatchbellText.of(context);
          return AlertDialog(
            title: Text(text.desktopAlerts),
            content: SizedBox(
              width: 390,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(text.newAdvisoryAlerts),
                    subtitle: Text(text.alertsWhileRunning),
                    value: watchlist.notifications,
                    onChanged: watchlist.changingNotifications
                        ? null
                        : watchlist.setNotifications,
                  ),
                  if (watchlist.notificationMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(watchlist.notificationMessage!),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    watchlist.notifications ? watchlist.sendTestAlert : null,
                child: Text(text.testAlert),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context),
                child: Text(text.close),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watchlist = widget.watchlist;
    final text = PatchbellText.of(context);
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: watchlist,
      builder: (context, _) {
        final items = watchlist.items;
        final visible = items
            .where(
                (item) => _filter == null || _filter == item.product.category)
            .toList();
        final noticeCount =
            items.where((item) => item.advisories.isNotEmpty).length;
        return Scaffold(
          body: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: colors.outlineVariant)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(Icons.notifications_none_rounded,
                          color: colors.onPrimary, size: 21),
                    ),
                    const SizedBox(width: 10),
                    Text('Patchbell',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            )),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: watchlist.loaded ? _showAlerts : null,
                      icon: Icon(
                        watchlist.notifications
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_none_rounded,
                      ),
                      label: Text(text.desktopAlerts),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _savingSettings ? null : _showSettings,
                      tooltip: text.settings,
                      icon: Icon(Icons.settings_outlined,
                          semanticLabel: text.settings),
                    ),
                  ],
                ),
              ),
              if (!watchlist.loaded)
                Expanded(
                  child: Center(
                    child: watchlist.loadError == null
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(watchlist.loadError!),
                              TextButton(
                                onPressed: watchlist.load,
                                child: Text(text.retry),
                              ),
                            ],
                          ),
                  ),
                )
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: constraints.maxWidth > 950
                            ? (constraints.maxWidth - 900) / 2
                            : 22,
                        vertical: 22,
                      ),
                      children: [
                        Text(
                          text.mySoftware,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          text.homeIntro,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 17),
                        Wrap(
                          spacing: 9,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _register,
                              icon: const Icon(Icons.add_rounded),
                              label: Text(text.register),
                            ),
                            OutlinedButton.icon(
                              onPressed: _scanInstalled,
                              icon: const Icon(Icons.manage_search_rounded),
                              label: Text(text.scan),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  !items.any((item) => item.product.canCheck) ||
                                          watchlist.checking
                                      ? null
                                      : watchlist.checkAll,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(watchlist.checking
                                  ? text.checking
                                  : text.checkAdvisories),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (watchlist.checking) const LinearProgressIndicator(),
                        if (watchlist.storageError != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              watchlist.storageError!,
                              style: TextStyle(color: colors.tertiary),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                                child: _Metric(
                                    label: text.registered,
                                    value: items.length)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _Metric(
                                    label: text.affectedItems,
                                    value: noticeCount)),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            ChoiceChip(
                              label: Text(text.all),
                              selected: _filter == null,
                              onSelected: (_) => setState(() => _filter = null),
                            ),
                            for (final category in ProductCategory.values)
                              ChoiceChip(
                                label: Text(text.category(category)),
                                selected: _filter == category,
                                onSelected: (_) =>
                                    setState(() => _filter = category),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (visible.isEmpty)
                          _EmptyList(hasItems: items.isNotEmpty),
                        for (final item in visible)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _WatchRow(
                              item: item,
                              checking: watchlist.checkingKey == item.key,
                              error: watchlist.checkError(item),
                              onDetails: () => _showDetails(
                                  context, item, watchlist.checkError(item)),
                              onEdit: () => _register(item),
                              onRemove: () => watchlist.remove(item),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          text.sources,
                          style: TextStyle(
                              fontSize: 12, color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(color: colors.onSurfaceVariant))),
          const SizedBox(width: 7),
          Text('$value', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.hasItems});
  final bool hasItems;

  @override
  Widget build(BuildContext context) {
    final text = PatchbellText.of(context);
    final colors = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, color: colors.onSurfaceVariant),
          const SizedBox(height: 7),
          Text(hasItems ? text.emptyCategory : text.addFirstItem),
          if (!hasItems) ...[
            const SizedBox(height: 5),
            Text(
              text.emptyDescription,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _WatchRow extends StatelessWidget {
  const _WatchRow({
    required this.item,
    required this.checking,
    required this.error,
    required this.onDetails,
    required this.onEdit,
    required this.onRemove,
  });

  final TrackedVersion item;
  final bool checking;
  final String? error;
  final VoidCallback onDetails;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = PatchbellText.of(context);
    final colors = Theme.of(context).colorScheme;
    final name = text.productName(item.product);
    final count = item.advisories.length;
    final (label, color) = switch ((checking, error, item.checkedAt, count)) {
      (true, _, _, _) => (text.checking, colors.primary),
      (_, String _, _, _) => (text.checkFailed, colors.tertiary),
      (_, _, null, _) when !item.product.canCheck => (
          text.unlinked,
          colors.onSurfaceVariant
        ),
      (_, _, null, _) => (text.unchecked, colors.onSurfaceVariant),
      (_, _, _, 0) => (text.noMatches, colors.onSurfaceVariant),
      _ => (text.advisoryCount(count), colors.tertiary),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onDetails,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(_categoryIcon(item.product.category),
                          size: 20, color: colors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            '${text.category(item.product.category)} · ${item.version}',
                            style: TextStyle(
                                color: colors.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: text.manage(name),
            onSelected: (action) => action == 'edit' ? onEdit() : onRemove(),
            itemBuilder: (context) => [
              PopupMenuItem(value: 'edit', child: Text(text.edit)),
              PopupMenuItem(value: 'remove', child: Text(text.remove)),
            ],
          ),
        ],
      ),
    );
  }
}

void _showDetails(BuildContext context, TrackedVersion item, [String? error]) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final text = PatchbellText.of(context);
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(text.productName(item.product)),
        scrollable: true,
        content: SizedBox(
          width: 470,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  '${text.category(item.product.category)} · ${text.trackedVersion(item.version)}'),
              if (item.checkedAt != null) ...[
                const SizedBox(height: 5),
                Text(
                    text.lastChecked(
                        _date(context, item.checkedAt!, includeTime: true)),
                    style: TextStyle(color: colors.onSurfaceVariant)),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error, style: TextStyle(color: colors.tertiary)),
              ],
              const SizedBox(height: 16),
              if (!item.product.canCheck)
                Text(text.linkSourceToCheck)
              else if (item.advisories.isEmpty && error == null)
                Text(item.checkedAt == null
                    ? text.nothingChecked
                    : text.noVersionAdvisories)
              else if (item.advisories.isNotEmpty) ...[
                Text(text.advisoryDetails),
                const SizedBox(height: 7),
                SizedBox(
                  width: double.infinity,
                  height: (item.advisories.length * 68.0).clamp(68.0, 250.0),
                  child: ListView.builder(
                    primary: false,
                    itemCount: item.advisories.length,
                    itemBuilder: (context, index) {
                      final advisory = item.advisories[index];
                      final score = advisory.score?.toStringAsFixed(1);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(advisory.id),
                        subtitle: Text(
                          '${_date(context, advisory.published)}'
                          '${score == null ? '' : ' · CVSS $score'}',
                        ),
                        trailing:
                            const Icon(Icons.open_in_new_rounded, size: 18),
                        onTap: () => _open(context, advisory.url),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(text.close),
          ),
          if (item.product.updateUrl case final updateUrl?)
            FilledButton.tonalIcon(
              onPressed: () => _open(context, Uri.parse(updateUrl)),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: Text(text.updateInstructions),
            ),
        ],
      );
    },
  );
}
