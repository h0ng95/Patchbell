import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'catalog.dart';
import 'installed_software.dart';
import 'mac_platform.dart';
import 'registration_dialog.dart';
import 'strings.dart';
import 'watchlist.dart';

class InstalledSoftwareDialog extends StatefulWidget {
  const InstalledSoftwareDialog({
    super.key,
    required this.watchlist,
  });

  final Watchlist watchlist;

  @override
  State<InstalledSoftwareDialog> createState() =>
      _InstalledSoftwareDialogState();
}

class _InstalledSoftwareDialogState extends State<InstalledSoftwareDialog> {
  final _scanner = InstalledSoftwareScanner();
  final _found = <String, InstalledSoftware>{};
  final _selected = <String>{};
  bool _scanning = true;
  LocalizedMessage? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  Future<void> _scan([String? folder]) async {
    if (folder != null) {
      setState(() {
        _scanning = true;
        _error = null;
      });
    }
    try {
      final macOS = defaultTargetPlatform == TargetPlatform.macOS;
      final locations = macOS && folder == null
          ? await macPlatformChannel
              .invokeMapMethod<String, String>('discoveryLocations')
          : null;
      final apps = macOS
          ? await macPlatformChannel.invokeListMethod<Map<Object?, Object?>>(
              'installedApplications', folder)
          : null;
      final found = await _scanner.scan(
        folder: folder,
        macLocations: locations ?? {},
        macApplications: (apps ?? [])
            .map(MacInstalledApplication.fromChannel)
            .whereType<MacInstalledApplication>(),
      );
      if (!mounted) return;
      setState(() {
        for (final item in found) {
          _found.putIfAbsent(item.key, () => item);
        }
        if (folder != null && found.isEmpty) {
          _error = (text) => text.nothingInFolder;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = (text) => text.scanFailed);
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _chooseFolder() async {
    try {
      final folder = await getDirectoryPath(
        confirmButtonText: PatchbellText.of(context).select,
      );
      if (folder != null && mounted) await _scan(folder);
    } catch (_) {
      if (mounted) setState(() => _error = (text) => text.folderFailed);
    }
  }

  Future<void> _linkApp(InstalledSoftware item) async {
    final match = await showAdvisoryCatalog(
      context,
      widget.watchlist,
      item.product.name,
      productsOnly: true,
    );
    if (!mounted || match?.cpe == null) return;
    final product = Product.custom(
      name: item.product.name,
      category: item.product.category,
      macBundleId: item.product.macBundleId,
      cpe: match!.cpe,
    );
    setState(() {
      _found[item.key] =
          InstalledSoftware(product, item.version, item.location);
      if (widget.watchlist.contains(product, item.version)) {
        _selected.remove(item.key);
      }
    });
  }

  Widget _appRow(InstalledSoftware item, PatchbellText text) {
    final registered = widget.watchlist.contains(item.product, item.version);
    final tile = CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${text.productName(item.product)} ${item.version}'),
      subtitle: Tooltip(
        message: item.location,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!item.product.canCheck) Text(text.unlinked),
            Text(
              registered ? text.trackedLocation(item.location) : item.location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      value: registered || _selected.contains(item.key),
      onChanged: registered || _scanning
          ? null
          : (enabled) => setState(() {
                if (enabled == true) {
                  _selected.add(item.key);
                } else {
                  _selected.remove(item.key);
                }
              }),
    );
    return Row(
      key: ValueKey(item.key),
      children: [
        Expanded(child: tile),
        if (!registered && !item.product.canCheck)
          IconButton(
            onPressed: _scanning ? null : () => _linkApp(item),
            tooltip: text.linkAppSource,
            icon: Icon(Icons.link_rounded, semanticLabel: text.linkAppSource),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = PatchbellText.of(context);
    final entries = _found.values.toList();
    final canRegister = _selected.isNotEmpty && !_scanning;
    return AlertDialog(
      title: Text(text.scan),
      content: SizedBox(
        width: 500,
        height: (MediaQuery.sizeOf(context).height * .52).clamp(160.0, 350.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(defaultTargetPlatform == TargetPlatform.macOS
                ? text.scanMacIntro
                : text.scanIntro),
            const SizedBox(height: 12),
            if (_scanning) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(_error!(text)),
              ),
            if (entries.isEmpty && !_scanning && _error == null)
              Text(text.scanEmpty),
            if (entries.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _appRow(entries[index], text),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _scanning ? null : _chooseFolder,
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: Text(text.selectFolder),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(text.close),
        ),
        FilledButton(
          onPressed: canRegister
              ? () => Navigator.pop(
                    context,
                    entries
                        .where((entry) => _selected.contains(entry.key))
                        .toList(),
                  )
              : null,
          child: Text(text.addSelected(_selected.length)),
        ),
      ],
    );
  }
}
