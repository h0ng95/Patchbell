import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'catalog.dart';

class InstalledSoftware {
  const InstalledSoftware(this.product, this.version, this.location);

  final Product product;
  final String version;
  final String location;

  String get key => '${product.appId ?? product.id}:$version';
}

class MacInstalledApplication {
  const MacInstalledApplication({
    required this.bundleId,
    required this.name,
    required this.version,
    required this.path,
  });

  final String bundleId;
  final String name;
  final String version;
  final String path;

  static MacInstalledApplication? fromChannel(Map<Object?, Object?> value) {
    return switch (value) {
      {
        'bundleId': final String bundleId,
        'name': final String name,
        'version': final String version,
        'path': final String path,
      } =>
        MacInstalledApplication(
            bundleId: bundleId, name: name, version: version, path: path),
      _ => null,
    };
  }
}

class WindowsInstalledApplication {
  const WindowsInstalledApplication({
    required this.name,
    required this.version,
    this.publisher = '',
    this.path = '',
  });

  final String name;
  final String version;
  final String publisher;
  final String path;

  static WindowsInstalledApplication? fromChannel(Map<Object?, Object?> value) {
    return switch (value) {
      {'name': final String name, 'version': final String version} =>
        WindowsInstalledApplication(
          name: name,
          version: version,
          publisher: value['publisher'] as String? ?? '',
          path: value['path'] as String? ?? '',
        ),
      _ => null,
    };
  }
}

/// Reads version metadata from installed products without running their tools.
class InstalledSoftwareScanner {
  Future<List<InstalledSoftware>> scan({
    String? folder,
    Map<String, String> macLocations = const {},
    Iterable<MacInstalledApplication> macApplications = const [],
    Iterable<WindowsInstalledApplication> windowsApplications = const [],
  }) async {
    final inventory = _Inventory();
    for (final app in macApplications) {
      inventory.addMacApplication(app);
    }
    if (folder != null) {
      await inventory.inspectAll([
        folder,
        p.join(folder, '.fvm', 'flutter_sdk'),
        ...await _directories(folder),
      ]);
      inventory.addWindowsApplications(windowsApplications);
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
    inventory.addWindowsApplications(windowsApplications);
    return inventory.results;
  }

  Future<List<InstalledSoftware>> scanNpmProject(String folder) async {
    if (!p.isAbsolute(folder)) return [];
    final project = await _json(folder, 'package.json');
    if (project == null) return [];

    final dependencies = <String>{};
    for (final section in [
      'dependencies',
      'devDependencies',
      'optionalDependencies',
      'peerDependencies',
    ]) {
      final entries = project[section];
      if (entries is Map<String, Object?>) dependencies.addAll(entries.keys);
    }
    final inventory = _Inventory();
    for (final dependency in dependencies.where(_npmPackageName.hasMatch)) {
      final location =
          p.joinAll([folder, 'node_modules', ...dependency.split('/')]);
      final installed = await _json(location, 'package.json');
      final name = installed?['name'];
      final version = installed?['version'];
      if (name is! String ||
          !_npmPackageName.hasMatch(name) ||
          version is! String) {
        continue;
      }
      inventory.addProduct(
        Product.custom(
            name: name, category: ProductCategory.sdk, npmPackage: name),
        version,
        folder,
      );
    }
    return inventory.results;
  }

  static final _npmPackageName = RegExp(
    r'^(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$',
    caseSensitive: false,
  );
}

class _Inventory {
  static const _knownMacBundles = {
    'com.google.chrome': 'chrome',
    'com.docker.docker': 'docker',
    'com.microsoft.vscode': 'vscode',
    'com.jetbrains.intellij': 'intellij',
    'org.mozilla.firefox': 'firefox',
  };
  final _found = <String, InstalledSoftware>{};
  final _visited = <String>{};

  List<InstalledSoftware> get results => _found.values.toList()
    ..sort((a, b) {
      final byName = a.product.name.compareTo(b.product.name);
      if (byName != 0) return byName;
      final left = a.version.split('.');
      final right = b.version.split('.');
      for (var index = 0;
          index < left.length && index < right.length;
          index++) {
        final leftNumber = int.tryParse(left[index]);
        final rightNumber = int.tryParse(right[index]);
        final byPart = switch ((leftNumber, rightNumber)) {
          (final int left, final int right) => right.compareTo(left),
          (int _, null) => -1,
          (null, int _) => 1,
          _ => right[index].compareTo(left[index]),
        };
        if (byPart != 0) return byPart;
      }
      final byLength = right.length.compareTo(left.length);
      if (byLength != 0) return byLength;
      return a.location.compareTo(b.location);
    });

  void addMacApplication(MacInstalledApplication app) {
    final bundleId = app.bundleId.trim().toLowerCase();
    final name = app.name.trim();
    if (bundleId.isEmpty || name.isEmpty || !p.isAbsolute(app.path)) return;
    final knownProduct = _knownMacBundles[bundleId];
    if (knownProduct != null && add(knownProduct, app.version, app.path)) {
      return;
    }

    addProduct(
      Product.custom(
          name: name, category: ProductCategory.app, appId: 'mac:$bundleId'),
      app.version,
      app.path,
    );
  }

  void addWindowsApplications(
      Iterable<WindowsInstalledApplication> applications) {
    final hasEditorMetadata =
        _found.values.any((item) => item.product.id == 'vscode');
    for (final app in applications) {
      final name = app.name.trim();
      if (name.isEmpty) continue;
      final publisher = app.publisher.trim();
      final normalizedName = name.toLowerCase();
      final vendor =
          publisher.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final location = app.path.trim().isNotEmpty
          ? app.path.trim()
          : publisher.isNotEmpty
              ? publisher
              : 'Windows';
      final productId = switch ((normalizedName, vendor)) {
        ('google chrome', 'googlellc' || 'googleinc') => 'chrome',
        ('docker desktop', 'dockerinc' || 'docker') => 'docker',
        (
          'microsoft visual studio code' ||
              'microsoft visual studio code (user)',
          'microsoftcorporation'
        ) =>
          'vscode',
        (final name, 'mozilla' || 'mozillacorporation')
            when _firefoxName.hasMatch(name) =>
          'firefox',
        _ => null,
      };
      if (productId == 'vscode' && hasEditorMetadata) continue;
      if (productId != null && add(productId, app.version, location)) continue;
      addProduct(
        Product.custom(
          name: name,
          category: ProductCategory.app,
          appId: 'windows:$normalizedName:${publisher.toLowerCase()}',
        ),
        app.version,
        location,
      );
    }
  }

  static final _firefoxName = RegExp(r'^mozilla firefox(?: \([^)]+\))?$');

  void addProduct(Product product, String version, String location) {
    final normalized = product.normalizeVersion(version);
    if (normalized == null) return;
    final item = InstalledSoftware(product, normalized, location);
    _found.putIfAbsent(item.key, () => item);
  }

  bool add(String productId, String? version, String location) {
    final product = productsById[productId]!;
    final cleaned = version == null ? null : product.normalizeVersion(version);
    if (cleaned == null ||
        !cleaned
            .split('.')
            .every((component) => int.tryParse(component) != null)) {
      return false;
    }
    final item = InstalledSoftware(product, cleaned, location);
    _found.putIfAbsent(item.key, () => item);
    return true;
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
    // The Windows launcher identifies the active resources after an update.
    final launcher =
        Platform.isWindows ? await _read(root, 'bin/code.cmd') : null;
    final commitFolder = launcher == null
        ? null
        : RegExp(
            r'"%~dp0\.\.\\([a-f0-9]{10})\\resources\\app\\out\\cli\.js"',
            caseSensitive: false,
          ).firstMatch(launcher)?[1];
    final versionedResources =
        commitFolder == null ? null : '$commitFolder/resources/app';

    for (final subdirectory in [
      if (versionedResources != null) versionedResources,
      'Contents/Resources/app',
      'resources/app',
    ]) {
      final package = p.joinAll([root, ...subdirectory.split('/')]);
      final product = await _json(package, 'product.json');
      if (product?['applicationName'] != 'code') continue;
      final info = await _json(package, 'package.json');
      final version = info?['version'];
      if (version is! String) continue;
      final recognized = add('vscode', version, root);
      if (recognized && subdirectory == versionedResources) return;
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
