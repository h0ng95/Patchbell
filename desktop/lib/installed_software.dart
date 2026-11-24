import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'catalog.dart';

class InstalledSoftware {
  const InstalledSoftware(this.product, this.version, this.location);

  final Product product;
  final String version;
  final String location;

  String get key => '${product.id}:$version';
}

/// Reads version metadata from installed products without running their tools.
class InstalledSoftwareScanner {
  Future<List<InstalledSoftware>> scan({
    String? folder,
    Map<String, String> macLocations = const {},
  }) async {
    final inventory = _Inventory();
    if (folder != null) {
      await inventory.inspectAll([
        folder,
        p.join(folder, '.fvm', 'flutter_sdk'),
        ...await _directories(folder),
      ]);
      return inventory.results;
    }

    final env = Platform.environment;
    final roots = <String>{};
    final home =
        (macLocations['home'] ?? env['USERPROFILE'] ?? env['HOME']) ?? '';
    if (home.isNotEmpty && p.isAbsolute(home)) {
      roots.addAll([
        p.join(home, 'flutter'),
        p.join(home, 'dart-sdk'),
        p.join(home, 'development', 'flutter'),
        p.join(home, 'Development', 'flutter'),
        p.join(home, 'dev', 'flutter'),
        p.join(home, 'sdk', 'flutter'),
        p.join(home, 'sdks', 'flutter'),
        p.join(home, 'tools', 'flutter'),
        p.join(home, 'Applications', 'Visual Studio Code.app'),
      ]);
      for (final manager in [
        p.join(home, 'fvm', 'versions'),
        p.join(home, '.fvm', 'versions'),
        p.join(home, '.nvm', 'versions', 'node'),
        p.join(home, '.volta', 'tools', 'image', 'node'),
        p.join(home, '.pyenv', 'versions'),
        p.join(home, '.pyenv', 'pyenv-win', 'versions'),
      ]) {
        roots.addAll(await _directories(manager));
      }
      for (final manager in [
        p.join(home, '.local', 'share', 'mise', 'installs'),
        p.join(home, '.asdf', 'installs'),
      ]) {
        for (final tool in ['flutter', 'dart', 'node', 'nodejs', 'python']) {
          roots.addAll(await _directories(p.join(manager, tool)));
        }
      }
    }
    for (final binDir
        in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
      final absoluteDir = binDir.trim().replaceAll('"', '');
      if (!p.isAbsolute(absoluteDir)) continue;
      if (p.basename(absoluteDir).toLowerCase() == 'bin') {
        roots.add(p.dirname(absoluteDir));
      } else if (Platform.isWindows) {
        roots.add(absoluteDir);
      }
    }

    if (Platform.isMacOS) {
      final editor = macLocations['codePath'];
      if (editor != null) {
        inventory.add('vscode', macLocations['codeVersion'], editor);
        roots.add(editor);
      }
      roots.addAll([
        '/Applications/Visual Studio Code.app',
        '/usr/local',
        '/opt/local',
        '/opt/homebrew',
      ]);
      for (final prefix in ['/opt/homebrew', '/usr/local']) {
        roots.addAll([
          p.join(prefix, 'opt', 'dart', 'libexec'),
          p.join(prefix, 'share', 'flutter'),
        ]);
        for (final formula in await _directories(p.join(prefix, 'Cellar'))) {
          if (RegExp(r'^(?:node|python)(?:@[\d.]+)?$')
              .hasMatch(p.basename(formula))) {
            roots.addAll(await _directories(formula));
          }
        }
        for (final version
            in await _directories(p.join(prefix, 'Caskroom', 'flutter'))) {
          roots.addAll([version, p.join(version, 'flutter')]);
        }
      }
      roots.addAll(
          await _directories('/Library/Frameworks/Python.framework/Versions'));
      roots.addAll(await _directories(
        '/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions',
      ));
    } else if (Platform.isWindows) {
      final localAppData = env['LOCALAPPDATA'];
      if (localAppData != null) {
        roots.add(p.join(localAppData, 'Programs', 'Microsoft VS Code'));
        roots.addAll(
            await _directories(p.join(localAppData, 'Programs', 'Python')));
      }
      for (final directory in [env['ProgramFiles'], env['ProgramFiles(x86)']]
          .whereType<String>()) {
        roots.addAll([
          p.join(directory, 'Microsoft VS Code'),
          p.join(directory, 'nodejs')
        ]);
        roots.addAll((await _directories(directory)).where((root) =>
            RegExp(r'^Python\d+$', caseSensitive: false)
                .hasMatch(p.basename(root))));
      }
      for (final location
          in [env['NVM_HOME'], env['FVM_CACHE_PATH']].whereType<String>()) {
        roots.addAll(await _directories(location));
        roots.addAll(await _directories(p.join(location, 'versions')));
      }
    }

    await inventory.inspectAll(roots);
    return inventory.results;
  }
}

class _Inventory {
  final _found = <String, InstalledSoftware>{};
  final _visited = <String>{};

  List<InstalledSoftware> get results => _found.values.toList()
    ..sort((a, b) {
      final byName = a.product.name.compareTo(b.product.name);
      if (byName != 0) return byName;
      final left = a.version.split('.').map(int.parse).toList();
      final right = b.version.split('.').map(int.parse).toList();
      for (var index = 0; index < left.length; index++) {
        final byPart = right[index].compareTo(left[index]);
        if (byPart != 0) return byPart;
      }
      return a.location.compareTo(b.location);
    });

  void add(String productId, String? version, String location) {
    final product = productsById[productId]!;
    final cleaned = version == null ? null : product.normalizeVersion(version);
    if (cleaned == null ||
        !cleaned
            .split('.')
            .every((component) => int.tryParse(component) != null)) {
      return;
    }
    final item = InstalledSoftware(product, cleaned, location);
    _found.putIfAbsent(item.key, () => item);
  }

  Future<void> inspectAll(Iterable<String> roots) async {
    // SDK locations can point to the same real installation via symlinks.
    for (final root in roots) {
      if (!p.isAbsolute(root)) continue;
      try {
        final real = await Directory(root).resolveSymbolicLinks();
        if (_visited.add(real)) await _inspect(real);
      } on FileSystemException {
        // Nonexistent paths or paths outside permitted folders are skipped.
      }
    }
  }

  Future<void> _inspect(String root) async {
    final flutter = await _hasFile(root, ['bin/flutter', 'bin/flutter.bat']);
    if (flutter) {
      final cache = await _json(root, 'bin/cache/flutter.version.json');
      final cachedVersion =
          cache?['frameworkVersion'] ?? cache?['flutterVersion'];
      add(
        'flutter',
        cachedVersion is String ? cachedVersion : await _read(root, 'version'),
        root,
      );
      final bundledDart = p.join(root, 'bin', 'cache', 'dart-sdk');
      await _inspectDart(bundledDart);
    } else {
      await _inspectDart(root);
    }

    await _inspectNode(root);
    await _inspectPython(root);
    await _inspectEditor(root);
  }

  Future<void> _inspectDart(String root) async {
    if (await _hasFile(root, ['bin/dart', 'bin/dart.exe'])) {
      add('dart', await _read(root, 'version'), root);
    }
  }

  Future<void> _inspectNode(String root) async {
    if (!await _hasFile(root, ['bin/node', 'node.exe', 'node'])) return;
    final header = await _read(root, 'include/node/node_version.h');
    if (header != null) {
      final parts = [
        for (final part in ['MAJOR', 'MINOR', 'PATCH'])
          RegExp(r'^#\s*define\s+NODE_' + part + r'_VERSION\s+(\d+)',
                  multiLine: true)
              .firstMatch(header)?[1],
      ];
      if (parts.every((part) => part != null)) {
        add('node', parts.join('.'), root);
        return;
      }
    }
    add('node', _versionInFolderName(root), root);
  }

  Future<void> _inspectPython(String root) async {
    final folderVersion = _versionInFolderName(root);
    final majorMinor = folderVersion?.split('.').take(2).join('.');
    if (!await _hasFile(root, [
      'bin/python3',
      'bin/python',
      'python.exe',
      'Python',
      'Python3',
      if (majorMinor != null) 'bin/python$majorMinor',
    ])) {
      return;
    }
    final includes = await _directories(p.join(root, 'include'));
    for (final path in [
      p.join(root, 'Headers'),
      p.join(root, 'include'),
      ...includes.where((path) => p.basename(path).startsWith('python')),
    ]) {
      final header = await _read(path, 'patchlevel.h');
      final version = header == null
          ? null
          : RegExp(r'^#\s*define\s+PY_VERSION\s+"([^"]+)"', multiLine: true)
              .firstMatch(header)?[1];
      if (version != null) {
        add('python', version, root);
        return;
      }
    }
    add('python', folderVersion, root);
  }

  Future<void> _inspectEditor(String root) async {
    for (final subdirectory in ['Contents/Resources/app', 'resources/app']) {
      final package = p.joinAll([root, ...subdirectory.split('/')]);
      final product = await _json(package, 'product.json');
      if (product?['applicationName'] != 'code') continue;
      final info = await _json(package, 'package.json');
      final version = info?['version'];
      if (version is String) add('vscode', version, root);
    }
  }
}

String? _versionInFolderName(String path) =>
    RegExp(r'^v?(\d+\.\d+\.\d+)(?:_\d+)?$').firstMatch(p.basename(path))?[1];

Future<List<String>> _directories(String location) async {
  final directories = <String>[];
  try {
    await for (final item in Directory(location).list(followLinks: false)) {
      if (item is Directory || item is Link) {
        directories.add(item.path);
        if (directories.length == 160) break;
      }
    }
  } on FileSystemException {
    // Optional installation locations may be unavailable.
  }
  return directories;
}

Future<bool> _hasFile(String root, Iterable<String> relativePaths) async {
  for (final path in relativePaths) {
    if (await File(p.joinAll([root, ...path.split('/')])).exists()) return true;
  }
  return false;
}

Future<String?> _read(String root, String path) async {
  final file = File(p.joinAll([root, ...path.split('/')]));
  try {
    if (await file.length() > 1024 * 1024) return null;
    return await file.readAsString();
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

Future<Map<String, Object?>?> _json(String root, String path) async {
  final text = await _read(root, path);
  if (text == null) return null;
  try {
    final value = jsonDecode(text);
    return value is Map<String, Object?> ? value : null;
  } on FormatException {
    return null;
  }
}
