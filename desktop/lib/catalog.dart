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
  });

  Product.custom({
    required this.name,
    required this.category,
    this.cpe,
  })  : id = 'custom:${name.trim().toLowerCase()}',
        example = '1.2.3',
        updateUrl = null;

  final String id;
  final String name;
  final ProductCategory category;
  final String? cpe;
  final String example;
  final String? updateUrl;
  String get identity => cpe ?? id;

  String? normalizeVersion(String input) {
    var version = input.trim().toLowerCase();
    if (id == 'go' && version.startsWith('go')) {
      version = version.substring(2);
    }
    if (RegExp(r'^v\d').hasMatch(version)) version = version.substring(1);
    final pattern = switch (id) {
      'chrome' => r'^\d+\.\d+\.\d+\.\d+$',
      'go' => r'^\d+\.\d+(\.\d+)?$',
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
  ),
  Product(
    id: 'vscode',
    name: 'Visual Studio Code',
    category: ProductCategory.editor,
    cpe: 'microsoft:visual_studio_code',
    example: '1.96.0',
    updateUrl: 'https://code.visualstudio.com/Download',
  ),
  Product(
    id: 'flutter',
    name: 'Flutter SDK',
    category: ProductCategory.sdk,
    cpe: 'flutter:flutter',
    example: '3.27.4',
    updateUrl: 'https://docs.flutter.dev/install/upgrade',
  ),
  Product(
    id: 'dart',
    name: 'Dart SDK',
    category: ProductCategory.sdk,
    cpe: 'dart:dart_software_development_kit',
    example: '3.6.2',
    updateUrl: 'https://dart.dev/get-dart',
  ),
  Product(
    id: 'node',
    name: 'Node.js',
    category: ProductCategory.runtime,
    cpe: 'nodejs:node.js',
    example: '20.11.1',
    updateUrl: 'https://nodejs.org/en/download',
  ),
  Product(
    id: 'python',
    name: 'Python',
    category: ProductCategory.runtime,
    cpe: 'python:python',
    example: '3.12.0',
    updateUrl: 'https://www.python.org/downloads/',
  ),
  Product(
    id: 'go',
    name: 'Go',
    category: ProductCategory.runtime,
    cpe: 'golang:go',
    example: '1.23.2',
    updateUrl: 'https://go.dev/dl/',
  ),
];

final productsById = {for (final product in products) product.id: product};
