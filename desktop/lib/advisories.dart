import 'dart:convert';
import 'dart:io';

import 'catalog.dart';
import 'strings.dart';

class Advisory {
  const Advisory({
    required this.id,
    required this.published,
    this.score,
    this.fromOsv = false,
  });

  final String id;
  final DateTime published;
  final double? score;
  final bool fromOsv;

  Uri get url => fromOsv
      ? Uri.https('osv.dev', '/vulnerability/$id')
      : Uri.https('nvd.nist.gov', '/vuln/detail/$id');

  factory Advisory.fromJson(Map<String, dynamic> json) {
    return Advisory(
      id: json['id'] as String,
      published: DateTime.parse(json['published'] as String).toUtc(),
      score: (json['score'] as num?)?.toDouble(),
      fromOsv: json['fromOsv'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'published': published.toIso8601String(),
        'score': score,
        if (fromOsv) 'fromOsv': true,
      };
}

class AdvisoryRequestException implements Exception {
  const AdvisoryRequestException(this.source, this.status);

  final String source;
  final int status;

  String message(PatchbellText text) => status == HttpStatus.tooManyRequests
      ? text.requestLimit(source)
      : text.responseError(source, status);
}

typedef GetNvdPage = Future<Map<String, dynamic>> Function(Uri uri);

class CatalogMatch {
  const CatalogMatch(this.cpe, this.subtitle, this.name)
      : npmPackage = null,
        latestVersion = null;

  const CatalogMatch.npm(String package,
      {this.latestVersion, this.subtitle = 'npm'})
      : cpe = null,
        npmPackage = package,
        name = package;

  final String? cpe;
  final String? npmPackage;
  final String? latestVersion;
  final String subtitle;
  final String name;
  String get key => cpe ?? 'npm:$npmPackage';
}

class CatalogPage {
  const CatalogPage(this.matches, {this.nextStartIndex});

  final List<CatalogMatch> matches;
  final int? nextStartIndex;
}

class NvdClient {
  NvdClient({
    GetNvdPage? getPage,
    this.requestSpacing = const Duration(milliseconds: 6250),
  }) : _getPage = getPage ?? _request;

  final GetNvdPage _getPage;
  final Duration requestSpacing;
  final _sinceLastRequest = Stopwatch();
  Future<void> _requestQueue = Future.value();
  static final _applicationCpe =
      RegExp(r'^cpe:2\.3:a:((?:\\.|[^:\\])+):((?:\\.|[^:\\])+):');

  Future<CatalogPage> searchProducts(String name, {int startIndex = 0}) async {
    final term = name.trim();
    if (term.isEmpty) return const CatalogPage([]);
    final page = await _fetch(Uri.https(
      'services.nvd.nist.gov',
      '/rest/json/cpes/2.0',
      {
        'keywordSearch': term,
        'cpeMatchString': 'cpe:2.3:a',
        'resultsPerPage': '250',
        'startIndex': '$startIndex',
      },
    ));
    final rows = page['products'] as List<dynamic>;
    final total = page['totalResults'] as int;
    if (page['startIndex'] != startIndex ||
        (rows.isEmpty && startIndex < total)) {
      throw const FormatException('Invalid NVD product page');
    }
    final unique = <String, CatalogMatch>{};
    for (final record in rows) {
      final cpe =
          (record as Map<String, dynamic>)['cpe'] as Map<String, dynamic>;
      if (cpe['deprecated'] == true) continue;
      final parts = _applicationCpe.firstMatch(cpe['cpeName'] as String);
      if (parts == null) continue;
      final vendor = parts[1]!;
      final product = parts[2]!;
      final key = '$vendor:$product';
      unique.putIfAbsent(
        key,
        () => CatalogMatch(
            key, vendor.replaceAll('_', ' '), product.replaceAll('_', ' ')),
      );
    }
    final productName = term.toLowerCase().replaceAll('_', ' ');
    final matches = unique.values.toList()
      ..sort((a, b) {
        final aExact = a.name == productName;
        final bExact = b.name == productName;
        if (aExact != bExact) return aExact ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    final next = startIndex + rows.length;
    return CatalogPage(matches, nextStartIndex: next < total ? next : null);
  }

  Future<Map<String, dynamic>> _fetch(Uri uri) {
    final request = _requestQueue.then((_) async {
      final wait = requestSpacing - _sinceLastRequest.elapsed;
      if (_sinceLastRequest.isRunning && wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      _sinceLastRequest
        ..reset()
        ..start();
      return _getPage(uri);
    });
    _requestQueue = request.then<void>((_) {}, onError: (Object _) {});
    return request;
  }

  Future<List<Advisory>> check(Product product, String version) async {
    if (product.cpe == null) {
      throw ArgumentError('The product has no NVD catalog mapping.');
    }
    if (product.normalizeVersion(version) != version) {
      throw ArgumentError.value(version, 'version', 'Invalid product version');
    }

    final advisories = <String, Advisory>{};
    var start = 0;
    var total = 0;
    do {
      final page = await _fetch(Uri.https(
        'services.nvd.nist.gov',
        '/rest/json/cves/2.0',
        {
          'cpeName': product.cpeName(version),
          'isVulnerable': '',
          'noRejected': '',
          'resultsPerPage': '1000',
          'startIndex': '$start',
        },
      ));

      final rows = page['vulnerabilities'] as List<dynamic>;
      total = page['totalResults'] as int;
      if (page['startIndex'] != start || (rows.isEmpty && start < total)) {
        throw const FormatException('Invalid NVD results page');
      }
      for (final row in rows) {
        final cve =
            (row as Map<String, dynamic>)['cve'] as Map<String, dynamic>;
        if (cve['vulnStatus'] == 'Rejected') continue;
        final id = cve['id'] as String;
        if (!RegExp(r'^CVE-\d{4}-\d{4,}$').hasMatch(id)) {
          throw const FormatException('Invalid CVE identifier');
        }
        final stamp = cve['published'] as String;
        advisories[id] = Advisory(
          id: id,
          published: DateTime.parse(stamp.endsWith('Z') ? stamp : '${stamp}Z'),
          score: _score(cve['metrics'] as Map<String, dynamic>?),
        );
      }
      start += rows.length;
    } while (start < total);

    return advisories.values.toList()
      ..sort((a, b) => b.published.compareTo(a.published));
  }

  static double? _score(Map<String, dynamic>? metrics) {
    for (final format in [
      'cvssMetricV40',
      'cvssMetricV31',
      'cvssMetricV30',
      'cvssMetricV2',
    ]) {
      final entries = metrics?[format] as List<dynamic>?;
      if (entries == null || entries.isEmpty) continue;
      final primary = entries.firstWhere(
        (entry) => entry['type'] == 'Primary',
        orElse: () => entries.first,
      );
      return (primary['cvssData']['baseScore'] as num?)?.toDouble();
    }
    return null;
  }

  static Future<Map<String, dynamic>> _request(Uri uri) =>
      requestJson(uri, source: 'NVD');
}

Future<Map<String, dynamic>> requestJson(
  Uri uri, {
  required String source,
  Map<String, Object?>? payload,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'Patchbell/0.1';
  const timeout = Duration(seconds: 25);
  try {
    final request = await client
        .openUrl(payload == null ? 'GET' : 'POST', uri)
        .timeout(timeout);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (payload != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
    }
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw AdvisoryRequestException(source, response.statusCode);
    }

    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}
