import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:patchbell_desktop/installed_software.dart';
import 'package:patchbell_desktop/watchlist.dart';
import 'package:path/path.dart' as p;

void main() {
  test('reads five installed tool versions from a selected folder', () async {
    final sandbox =
        await Directory.systemTemp.createTemp('patchbell-inventory-');
    addTearDown(() => sandbox.delete(recursive: true));

    Future<void> put(String relativePath, String contents) async {
      final file = File(p.joinAll([sandbox.path, ...relativePath.split('/')]));
      await file.create(recursive: true);
      await file.writeAsString(contents);
    }

    await put('flutter/bin/flutter', '');
    await put('flutter/bin/dart', '');
    await put('flutter/version', '3.27.4');
    await put('flutter/bin/cache/flutter.version.json',
        '{"frameworkVersion":"3.27.4"}');
    await put('flutter/bin/cache/dart-sdk/bin/dart', '');
    await put('flutter/bin/cache/dart-sdk/version', '3.6.2');
    await put('dart-sdk/bin/dart.exe', '');
    await put('dart-sdk/version', '3.7.0');

    for (final location in ['node-bundled', 'node-duplicate']) {
      await put('$location/bin/node', '');
      await put('$location/include/node/node_version.h', '''
#define NODE_MAJOR_VERSION 22
#define NODE_MINOR_VERSION 15
#define NODE_PATCH_VERSION 0
''');
    }

    await put('python/bin/python3', '');
    await put(
      'python/include/python3.13/patchlevel.h',
      '#define PY_VERSION "3.13.2"',
    );
    await put(
      'editor/resources/app/product.json',
      '{"applicationName":"code"}',
    );
    await put('editor/resources/app/package.json', '{"version":"1.96.0"}');

    final items = await InstalledSoftwareScanner().scan(folder: sandbox.path);
    expect(items.map((item) => item.key).toSet(), {
      'flutter:3.27.4',
      'dart:3.6.2',
      'dart:3.7.0',
      'node:22.15.0',
      'python:3.13.2',
      'vscode:1.96.0',
    });
    expect(items, hasLength(6));
  });

  test('finds the Windows VS Code version selected by its launcher', () async {
    final sandbox =
        await Directory.systemTemp.createTemp('patchbell-vscode-inventory-');
    addTearDown(() => sandbox.delete(recursive: true));
    final install = p.join(sandbox.path, 'Microsoft VS Code');

    final launcher = File(p.join(install, 'bin', 'code.cmd'));
    await launcher.create(recursive: true);
    await launcher.writeAsString(
      r'"%~dp0..\Code.exe" "%~dp0..\034f571df5\resources\app\out\cli.js" %*',
    );
    for (final (folder, version) in [
      ('034f571df5', '1.118.1'),
      ('1234567890', '1.119.0'),
    ]) {
      final package = p.join(install, folder, 'resources', 'app');
      await Directory(package).create(recursive: true);
      await File(p.join(package, 'product.json'))
          .writeAsString('{"applicationName":"code"}');
      await File(p.join(package, 'package.json'))
          .writeAsString('{"version":"$version"}');
    }

    final items = await InstalledSoftwareScanner().scan(folder: sandbox.path);
    expect(items.map((item) => item.key), ['vscode:1.118.1']);
    expect(
        items.single.location, await Directory(install).resolveSymbolicLinks());
  }, skip: !Platform.isWindows);

  test('reads Mac app versions and links only recognized bundle identifiers',
      () async {
    final sandbox =
        await Directory.systemTemp.createTemp('patchbell-app-inventory-');
    addTearDown(() => sandbox.delete(recursive: true));

    MacInstalledApplication app(String id, String name, String version) =>
        MacInstalledApplication(
          bundleId: id,
          name: name,
          version: version,
          path: p.join(sandbox.path, '$name.app'),
        );

    final items = await InstalledSoftwareScanner().scan(
      folder: sandbox.path,
      macApplications: [
        app('com.google.Chrome', 'Google Chrome', '131.0.6778.69'),
        app('org.example.Editor', 'Editor', '2025.2'),
        app('org.example.Editor', 'Editor', '2025.11.1-beta'),
        app('org.example.Editor', 'Editor', '2025.2'),
        app('org.example.SecondEditor', 'Editor', '2025.2'),
        app('org.example.NoVersion', 'No Version', ''),
      ],
    );

    expect(items.map((item) => item.key), [
      'mac:org.example.editor:2025.11.1-beta',
      'mac:org.example.editor:2025.2',
      'mac:org.example.secondeditor:2025.2',
      'chrome:131.0.6778.69',
    ]);
    expect(items.last.product.cpe, 'google:chrome');
    expect(items.first.product.cpe, isNull);
    final original = TrackedVersion(
        product: items.first.product, version: items.first.version);
    final restored = TrackedVersion.fromJson(original.toJson())!;
    expect(restored.product.appId, 'mac:org.example.editor');
    expect(restored.key, original.key);
    final legacy = original.toJson();
    final legacyMetadata = legacy['custom'] as Map<String, Object?>;
    legacyMetadata
      ..remove('appId')
      ..['macBundleId'] = 'org.example.editor';
    expect(TrackedVersion.fromJson(legacy)!.key, original.key);
  });

  test(
      'Windows registry apps deduplicate and link known name and publisher pairs',
      () async {
    final sandbox =
        await Directory.systemTemp.createTemp('patchbell-registry-fixture-');
    addTearDown(() => sandbox.delete(recursive: true));
    const chrome = WindowsInstalledApplication(
        name: 'Google Chrome',
        version: '131.0.6778.69',
        publisher: 'Google LLC');
    final items = await InstalledSoftwareScanner().scan(
      folder: sandbox.path,
      windowsApplications: const [
        chrome,
        chrome,
        WindowsInstalledApplication(
            name: 'Example Editor', version: '2.1', publisher: 'Example'),
        WindowsInstalledApplication(
            name: 'Google Chrome', version: '1.0.0', publisher: 'Unknown'),
        WindowsInstalledApplication(name: 'Version missing', version: ''),
      ],
    );
    expect(items, hasLength(3));
    expect(items.where((item) => item.product.canCheck).single.product.cpe,
        'google:chrome');
    final unlinked =
        items.firstWhere((item) => item.product.name == 'Example Editor');
    expect(unlinked.product.appId, 'windows:example editor:example');
    expect(unlinked.product.canCheck, isFalse);
    expect(unlinked.location, 'Example');
  });

  test(
      'npm project scanning uses installed package versions and supports scoped aliases',
      () async {
    final sandbox =
        await Directory.systemTemp.createTemp('patchbell-npm-fixture-');
    addTearDown(() => sandbox.delete(recursive: true));
    Future<void> put(String path, String content) async {
      final file = File(p.joinAll([sandbox.path, ...path.split('/')]));
      await file.create(recursive: true);
      await file.writeAsString(content);
    }

    await put('first/package.json', '''
      {"dependencies":{"@nestjs/core":"^11.0.0","uninstalled":"1.2.3"},
       "devDependencies":{"nest-alias":"npm:@nestjs/common@^11","../outside":"1.0.0"}}
    ''');
    await put('first/node_modules/@nestjs/core/package.json',
        '{"name":"@nestjs/core","version":"11.1.6"}');
    await put('first/node_modules/nest-alias/package.json',
        '{"name":"@nestjs/common","version":"11.1.7"}');
    await put('first/node_modules/undeclared/package.json',
        '{"name":"undeclared","version":"4.5.6"}');
    await put(
        'first/outside/package.json', '{"name":"outside","version":"1.0.0"}');
    await put(
        'second/package.json', '{"dependencies":{"@nestjs/core":"^10.0.0"}}');
    await put('second/node_modules/@nestjs/core/package.json',
        '{"name":"@nestjs/core","version":"10.4.20"}');

    final scanner = InstalledSoftwareScanner();
    final first = await scanner.scanNpmProject(p.join(sandbox.path, 'first'));
    final second = await scanner.scanNpmProject(p.join(sandbox.path, 'second'));
    expect(first.map((item) => (item.product.npmPackage, item.version)), [
      ('@nestjs/common', '11.1.7'),
      ('@nestjs/core', '11.1.6'),
    ]);
    expect(second.single.product.npmPackage, '@nestjs/core');
    expect(second.single.version, '10.4.20');
    expect(second.single.key, isNot(first.last.key));
  });

  test('ignores app folders with malformed or unrecognized metadata', () async {
    final sandbox =
        await Directory.systemTemp.createTemp('patchbell-bad-inventory-');
    addTearDown(() => sandbox.delete(recursive: true));
    final flutter = File(p.join(sandbox.path, 'bin', 'flutter'));
    await flutter.create(recursive: true);
    final cache =
        File(p.join(sandbox.path, 'bin', 'cache', 'flutter.version.json'));
    await cache.create(recursive: true);
    await cache.writeAsString('{"frameworkVersion":42}');

    expect(
        await InstalledSoftwareScanner().scan(folder: sandbox.path), isEmpty);
  });
}
