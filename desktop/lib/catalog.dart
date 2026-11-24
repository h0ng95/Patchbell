enum ProductCategory {
  app('일반 앱'),
  editor('에디터'),
  sdk('SDK'),
  runtime('언어·런타임');

  const ProductCategory(this.label);
  final String label;
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.cpe,
    required this.example,
    required this.updateUrl,
    this.aliases = const [],
  });

  Product.custom({
    required this.name,
    required this.category,
    this.cpe,
  })  : id = 'custom:${name.trim().toLowerCase()}',
        example = '1.2.3',
        aliases = const [],
        updateUrl = null;

  final String id;
  final String name;
  final ProductCategory category;
  final String? cpe;
  final String example;
  final String? updateUrl;
  final List<String> aliases;
  String get identity => cpe ?? id;

  String? normalizeVersion(String input) {
    var version = input.trim().toLowerCase();
    if (id == 'go' && version.startsWith('go')) {
      version = version.substring(2);
    }
    if (RegExp(r'^v\d').hasMatch(version)) version = version.substring(1);
    final pattern = switch (id) {
      'chrome' => r'^\d+\.\d+\.\d+\.\d+$',
      'go' || 'firefox' => r'^\d+\.\d+(\.\d+)?$',
      'intellij' || 'docker' => r'^\d+\.\d+(?:\.\d+){0,2}$',
      _ when id.startsWith('custom:') => r'^[0-9a-z][0-9a-z._+\-]*$',
      _ => r'^\d+\.\d+\.\d+$',
    };
    return RegExp(pattern).hasMatch(version) && version.length <= 40
        ? version
        : null;
  }

  String cpeName(String version) {
    final escaped = version.replaceAll('+', r'\+');
    return 'cpe:2.3:a:$cpe:$escaped:*:*:*:*:*:*:*';
  }
}

const products = [
  Product(
    id: 'chrome',
    name: 'Google Chrome',
    category: ProductCategory.app,
    cpe: 'google:chrome',
    example: '131.0.6778.69',
    updateUrl: 'https://support.google.com/chrome/answer/95414',
    aliases: ['크롬'],
  ),
  Product(
    id: 'vscode',
    name: 'Visual Studio Code',
    category: ProductCategory.editor,
    cpe: 'microsoft:visual_studio_code',
    example: '1.96.0',
    updateUrl: 'https://code.visualstudio.com/Download',
    aliases: ['VS Code', '비주얼 스튜디오 코드'],
  ),
  Product(
    id: 'flutter',
    name: 'Flutter SDK',
    category: ProductCategory.sdk,
    cpe: 'flutter:flutter',
    example: '3.27.4',
    updateUrl: 'https://docs.flutter.dev/install/upgrade',
    aliases: ['플러터'],
  ),
  Product(
    id: 'dart',
    name: 'Dart SDK',
    category: ProductCategory.sdk,
    cpe: 'dart:dart_software_development_kit',
    example: '3.6.2',
    updateUrl: 'https://dart.dev/get-dart',
    aliases: ['다트'],
  ),
  Product(
    id: 'node',
    name: 'Node.js',
    category: ProductCategory.runtime,
    cpe: 'nodejs:node.js',
    example: '20.11.1',
    updateUrl: 'https://nodejs.org/en/download',
    aliases: ['노드'],
  ),
  Product(
    id: 'python',
    name: 'Python',
    category: ProductCategory.runtime,
    cpe: 'python:python',
    example: '3.12.0',
    updateUrl: 'https://www.python.org/downloads/',
    aliases: ['파이썬'],
  ),
  Product(
    id: 'go',
    name: 'Go',
    category: ProductCategory.runtime,
    cpe: 'golang:go',
    example: '1.23.2',
    updateUrl: 'https://go.dev/dl/',
    aliases: ['Golang', '고랭'],
  ),
  Product(
    id: 'intellij',
    name: 'IntelliJ IDEA',
    category: ProductCategory.editor,
    cpe: 'jetbrains:intellij_idea',
    example: '2024.3.2',
    updateUrl: 'https://www.jetbrains.com/idea/download/',
    aliases: ['JetBrains', '인텔리제이'],
  ),
  Product(
    id: 'docker',
    name: 'Docker Desktop',
    category: ProductCategory.app,
    cpe: 'docker:desktop',
    example: '4.41.2',
    updateUrl: 'https://docs.docker.com/desktop/',
    aliases: ['도커'],
  ),
  Product(
    id: 'rust',
    name: 'Rust',
    category: ProductCategory.runtime,
    cpe: 'rust-lang:rust',
    example: '1.85.0',
    updateUrl: 'https://www.rust-lang.org/tools/install',
    aliases: ['rustc', '러스트'],
  ),
  Product(
    id: 'kotlin',
    name: 'Kotlin',
    category: ProductCategory.runtime,
    cpe: 'jetbrains:kotlin',
    example: '2.1.20',
    updateUrl: 'https://kotlinlang.org/docs/command-line.html',
    aliases: ['코틀린', 'kotlinc'],
  ),
  Product(
    id: 'dotnet',
    name: '.NET 런타임',
    category: ProductCategory.runtime,
    cpe: 'microsoft:.net',
    example: '9.0.2',
    updateUrl: 'https://dotnet.microsoft.com/en-us/download/dotnet',
    aliases: ['dotnet runtime', '닷넷'],
  ),
  Product(
    id: 'oracle-jdk',
    name: 'Oracle JDK',
    category: ProductCategory.sdk,
    cpe: 'oracle:jdk',
    example: '21.0.6',
    updateUrl: 'https://www.oracle.com/java/technologies/downloads/',
    aliases: ['Java', '자바', '오라클'],
  ),
  Product(
    id: 'ruby',
    name: 'Ruby',
    category: ProductCategory.runtime,
    cpe: 'ruby-lang:ruby',
    example: '3.4.1',
    updateUrl: 'https://www.ruby-lang.org/en/downloads/',
    aliases: ['루비'],
  ),
  Product(
    id: 'php',
    name: 'PHP',
    category: ProductCategory.runtime,
    cpe: 'php:php',
    example: '8.4.2',
    updateUrl: 'https://www.php.net/downloads.php',
  ),
  Product(
    id: 'git',
    name: 'Git',
    category: ProductCategory.app,
    cpe: 'git-scm:git',
    example: '2.49.0',
    updateUrl: 'https://git-scm.com/downloads',
  ),
  Product(
    id: 'firefox',
    name: 'Mozilla Firefox',
    category: ProductCategory.app,
    cpe: 'mozilla:firefox',
    example: '137.0',
    updateUrl: 'https://www.mozilla.org/firefox/new/',
    aliases: ['파이어폭스'],
  ),
];

final productsById = {for (final product in products) product.id: product};
