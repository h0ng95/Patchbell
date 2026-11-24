import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:patchbell_desktop/installed_software.dart';
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
