import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'advisories.dart';
import 'catalog.dart';
import 'desktop_alerts.dart';
import 'installed_software.dart';
import 'installed_software_dialog.dart';
import 'mac_menu_bar.dart';
import 'registration_dialog.dart';
import 'watchlist.dart';

const _page = Color(0xff101916);
const _surface = Color(0xff19271f);
const _border = Color(0xff364a3d);
const _mint = Color(0xffc9f88b);
const _muted = Color(0xffacc0b1);
const _warning = Color(0xfff7d68f);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PatchbellApp(
    watchlist: Watchlist(
      preferences: SharedPreferencesAsync(),
      client: NvdClient(),
      alerts: DesktopAlerts(),
    ),
  ));
}

class PatchbellApp extends StatefulWidget {
  const PatchbellApp({super.key, required this.watchlist});

  final Watchlist watchlist;

  @override
  State<PatchbellApp> createState() => _PatchbellAppState();
}

class _PatchbellAppState extends State<PatchbellApp> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.watchlist.load());
  }

  @override
  void dispose() {
    widget.watchlist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: _mint,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _mint,
      onPrimary: const Color(0xff1b301c),
      surface: _surface,
      onSurface: const Color(0xffeff5ed),
      onSurfaceVariant: _muted,
      outline: _border,
      outlineVariant: _border,
    );
    return MaterialApp(
      title: 'Patchbell',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: colors,
        scaffoldBackgroundColor: _page,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: _Home(watchlist: widget.watchlist),
    );
  }
}

IconData _categoryIcon(ProductCategory category) => switch (category) {
      ProductCategory.app => Icons.apps_rounded,
      ProductCategory.editor => Icons.edit_note_rounded,
      ProductCategory.sdk => Icons.inventory_2_outlined,
      ProductCategory.runtime => Icons.code_rounded,
    };

String _date(DateTime value, {bool includeTime = false}) {
  final date = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  final day = '${date.year}.${two(date.month)}.${two(date.day)}';
  return includeTime ? '$day ${two(date.hour)}:${two(date.minute)}' : day;
}

Future<void> _open(BuildContext context, Uri url) async {
  try {
    if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // The same feedback applies when the platform cannot open the URL.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('브라우저에서 링크를 열지 못했어요.')),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.watchlist});

  final Watchlist watchlist;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  ProductCategory? _filter;
  MacMenuBar? _menuBar;

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

  void _showAlerts() {
    final watchlist = widget.watchlist;
    showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: watchlist,
        builder: (context, _) => AlertDialog(
          title: const Text('데스크톱 알림'),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('새 보안 공지 알림'),
                  subtitle: const Text('앱이 실행 중일 때 새 공지를 알려드려요.'),
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
              child: const Text('테스트 알림'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watchlist = widget.watchlist;
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
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _border)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _mint,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.notifications_none_rounded,
                          color: Color(0xff1b301c), size: 21),
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
                      label: const Text('데스크톱 알림'),
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
                                child: const Text('다시 시도'),
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
                          '내 소프트웨어',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          '등록한 앱과 개발 도구의 보안 공지를 확인하세요.',
                          style: TextStyle(color: _muted),
                        ),
                        const SizedBox(height: 17),
                        Wrap(
                          spacing: 9,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _register,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('항목 등록'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _scanInstalled,
                              icon: const Icon(Icons.manage_search_rounded),
                              label: const Text('설치 버전 찾기'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  !items.any((item) => item.product.canCheck) ||
                                          watchlist.checking
                                      ? null
                                      : watchlist.checkAll,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(
                                  watchlist.checking ? '확인 중' : '보안 공지 확인'),
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
                              style: const TextStyle(color: _warning),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                                child: _Metric(
                                    label: '등록 항목', value: items.length)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _Metric(
                                    label: '공지 있는 항목', value: noticeCount)),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            ChoiceChip(
                              label: const Text('전체'),
                              selected: _filter == null,
                              onSelected: (_) => setState(() => _filter = null),
                            ),
                            for (final category in ProductCategory.values)
                              ChoiceChip(
                                label: Text(category.label),
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
                        const Text(
                          '보안 공지 출처는 NIST NVD와 OSV예요.',
                          style: TextStyle(fontSize: 12, color: _muted),
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
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _surface,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: _muted))),
            const SizedBox(width: 7),
            Text('$value', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      );
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.hasItems});
  final bool hasItems;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            const Icon(Icons.inventory_2_outlined, color: _muted),
            const SizedBox(height: 7),
            Text(hasItems ? '이 분류에 등록한 항목이 없어요.' : '첫 항목을 등록해 보세요.'),
            if (!hasItems) ...[
              const SizedBox(height: 5),
              const Text(
                '프로그램, 에디터, SDK, 언어와 런타임을 등록할 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted),
              ),
            ],
          ],
        ),
      );
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
    final count = item.advisories.length;
    final (label, color) = switch ((checking, error, item.checkedAt, count)) {
      (true, _, _, _) => ('확인 중', _mint),
      (_, String _, _, _) => ('확인 실패', _warning),
      (_, _, null, _) when !item.product.canCheck => ('공지 출처 미연결', _muted),
      (_, _, null, _) => ('미확인', _muted),
      (_, _, _, 0) => ('일치 공지 없음', _muted),
      _ => ('공지 $count건', _warning),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
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
                        color: const Color(0xff26392c),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(_categoryIcon(item.product.category),
                          size: 20, color: _mint),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.product.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            '${item.product.category.label} · ${item.version}',
                            style: const TextStyle(color: _muted, fontSize: 12),
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
            tooltip: '${item.product.name} 관리',
            onSelected: (action) => action == 'edit' ? onEdit() : onRemove(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('항목 수정')),
              PopupMenuItem(value: 'remove', child: Text('등록 해제')),
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
    builder: (context) => AlertDialog(
      title: Text(item.product.name),
      scrollable: true,
      content: SizedBox(
        width: 470,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${item.product.category.label} · 등록 버전 ${item.version}'),
            if (item.checkedAt != null) ...[
              const SizedBox(height: 5),
              Text('최근 확인 ${_date(item.checkedAt!, includeTime: true)}',
                  style: const TextStyle(color: _muted)),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error, style: const TextStyle(color: _warning)),
            ],
            const SizedBox(height: 16),
            if (!item.product.canCheck)
              const Text('항목 수정에서 제품이나 패키지를 연결하면 보안 공지를 확인할 수 있어요.')
            else if (item.advisories.isEmpty && error == null)
              Text(item.checkedAt == null
                  ? '아직 조회한 보안 공지가 없어요.'
                  : '이 버전에 일치하는 공개 공지가 없어요.')
            else if (item.advisories.isNotEmpty) ...[
              const Text('제품과 버전이 일치한 공지예요. 공지에서 운영체제와 수정 버전을 확인하세요.'),
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
                        '${_date(advisory.published)}'
                        '${score == null ? '' : ' · CVSS $score'}',
                      ),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
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
          child: const Text('닫기'),
        ),
        if (item.product.updateUrl case final updateUrl?)
          FilledButton.tonalIcon(
            onPressed: () => _open(context, Uri.parse(updateUrl)),
            icon: const Icon(Icons.open_in_new_rounded, size: 17),
            label: const Text('공식 업데이트 안내'),
          ),
      ],
    ),
  );
}
