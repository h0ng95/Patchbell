import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'catalog.dart';
import 'installed_software.dart';
import 'mac_platform.dart';
import 'strings.dart';

class InstalledSoftwareDialog extends StatefulWidget {
  const InstalledSoftwareDialog({
    super.key,
    required this.isRegistered,
  });

  final bool Function(Product, String) isRegistered;

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
      final locations =
          folder == null && defaultTargetPlatform == TargetPlatform.macOS
              ? await macPlatformChannel
                  .invokeMapMethod<String, String>('discoveryLocations')
              : null;
      final found =
          await _scanner.scan(folder: folder, macLocations: locations ?? {});
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
            Text(text.scanIntro),
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
                  itemBuilder: (context, index) {
                    final item = entries[index];
                    final registered =
                        widget.isRegistered(item.product, item.version);
                    return CheckboxListTile(
                      key: ValueKey(item.key),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '${text.productName(item.product)} ${item.version}'),
                      subtitle: Tooltip(
                        message: item.location,
                        child: Text(
                          registered
                              ? text.trackedLocation(item.location)
                              : item.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  },
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
