import 'advisories.dart';
import 'catalog.dart';

typedef NpmJsonRequest = Future<Map<String, dynamic>> Function(
  Uri uri, {
  Map<String, Object?>? payload,
});

class NpmClient {
  NpmClient({NpmJsonRequest? request}) : _request = request ?? _send;

  final NpmJsonRequest _request;
  static final _packageName = RegExp(r'^(?:@[\w.-]+/)?[\w.-]+$');

  Future<CatalogPage> searchPackages(String query, {int startIndex = 0}) async {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return const CatalogPage([]);
    final page = await _request(Uri.https(
      'registry.npmjs.org',
      '/-/v1/search',
      {'text': term, 'from': '$startIndex', 'size': '30'},
    ));
    final rows = page['objects'] as List<dynamic>;
    final total = page['total'] as int;
    if (rows.isEmpty && startIndex < total) {
      throw const FormatException('Invalid npm search page');
    }
    final matches = <CatalogMatch>[];
    CatalogMatch? frameworkCore;
    for (final row in rows) {
      final package = row['package'] as Map<String, dynamic>;
      final name = package['name'] as String;
      if (!_packageName.hasMatch(name)) continue;
      final match = CatalogMatch.npm(name, 'npm · 최신 ${package['version']}');
      if (name == '@$term/core') {
        frameworkCore = match;
      } else {
        matches.add(match);
      }
    }
    if (frameworkCore != null) matches.insert(0, frameworkCore);
    final next = startIndex + rows.length;
    return CatalogPage(matches, nextStartIndex: next < total ? next : null);
  }

  Future<List<Advisory>> check(Product product, String version) async {
    final name = product.npmPackage;
    if (name == null || product.normalizeVersion(version) != version) {
      throw ArgumentError(
          'An npm package and an installed version are required.');
    }
    final advisories = <String, Advisory>{};
    final seenTokens = <String>{};
    String? token;
    do {
      final page = await _request(
        Uri.https('api.osv.dev', '/v1/query'),
        payload: {
          'package': {'ecosystem': 'npm', 'name': name},
          'version': version,
          if (token != null) 'page_token': token,
        },
      );
      for (final value in page['vulns'] as List<dynamic>? ?? []) {
        final record = value as Map<String, dynamic>;
        if (record['withdrawn'] != null) continue;
        final id = record['id'] as String;
        advisories[id] = Advisory(
          id: id,
          published: DateTime.parse(
            (record['published'] ?? record['modified']) as String,
          ).toUtc(),
          fromOsv: true,
        );
      }
      token = page['next_page_token'] as String?;
      if (token != null && token.isNotEmpty && !seenTokens.add(token)) {
        throw const FormatException('Repeated OSV page token');
      }
    } while (token != null && token.isNotEmpty);
    return advisories.values.toList()
      ..sort((a, b) => b.published.compareTo(a.published));
  }

  static Future<Map<String, dynamic>> _send(
    Uri uri, {
    Map<String, Object?>? payload,
  }) =>
      requestJson(uri,
          source: payload == null ? 'npm' : 'OSV', payload: payload);
}
