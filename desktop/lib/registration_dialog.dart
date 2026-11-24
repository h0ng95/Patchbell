import 'dart:async';

import 'package:flutter/material.dart';

import 'advisories.dart';
import 'catalog.dart';
import 'watchlist.dart';

class RegistrationDialog extends StatefulWidget {
  const RegistrationDialog({super.key, required this.watchlist, this.item});

  final Watchlist watchlist;
  final TrackedVersion? item;

  @override
  State<RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<RegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _version = TextEditingController(text: widget.item?.version);
  late final _name = TextEditingController(text: widget.item?.product.name);
  late ProductCategory _category;
  late bool _custom;
  Product? _product;
  String? _linkedCpe;
  String? _linkedNpm;

  @override
  void initState() {
    super.initState();
    final existing = widget.item?.product;
    _custom = existing?.id.startsWith('custom:') ?? false;
    _category = existing?.category ?? ProductCategory.sdk;
    _product = _custom ? null : existing;
    _linkedCpe = _custom ? existing?.cpe : null;
    _linkedNpm = _custom ? existing?.npmPackage : null;
  }

  @override
  void dispose() {
    _version.dispose();
    _name.dispose();
    super.dispose();
  }

  Product? get _selection => _custom
      ? Product.custom(
          name: _name.text.trim(),
          category: _category,
          cpe: _linkedCpe,
          npmPackage: _linkedNpm,
        )
      : _product;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final product = _selection!;
    widget.watchlist.register(
      product,
      product.normalizeVersion(_version.text)!,
      previous: widget.item,
    );
    Navigator.pop(context, true);
  }

  void _selectPreset(Product product) {
    setState(() {
      if (_product != product) _version.clear();
      _product = product;
      _custom = false;
    });
  }

  void _selectCatalogMatch(CatalogMatch match) {
    for (final preset in products) {
      if (preset.identity == match.key) {
        _selectPreset(preset);
        return;
      }
    }
    setState(() {
      _custom = true;
      _product = null;
      _linkedCpe = match.cpe;
      _linkedNpm = match.npmPackage;
      if (_linkedNpm != null) _category = ProductCategory.sdk;
      _name.text = match.name;
      _version.clear();
    });
  }

  Future<void> _linkProduct() async {
    final match = await showDialog<CatalogMatch>(
      context: context,
      builder: (_) => _CatalogDialog(
        initialQuery: _name.text.trim(),
        watchlist: widget.watchlist,
      ),
    );
    if (mounted && match != null) {
      setState(() {
        _linkedCpe = match.cpe;
        _linkedNpm = match.npmPackage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item == null && !_custom && _product == null) {
      return _CatalogDialog(
        initialQuery: '',
        watchlist: widget.watchlist,
        onPreset: _selectPreset,
        onMatch: _selectCatalogMatch,
        onManual: (query) => setState(() {
          if (query.isNotEmpty && query != _name.text.trim()) {
            _name.text = query;
            _linkedCpe = null;
            _linkedNpm = null;
            _version.clear();
          }
          _custom = true;
        }),
      );
    }
    return AlertDialog(
      title: Text(widget.item == null ? '항목 등록' : '항목 수정'),
      content: SizedBox(
        width: 430,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.item == null) ...[
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _product = null;
                      _custom = false;
                    }),
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('제품 검색으로 돌아가기'),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_custom) ...[
                  TextFormField(
                    controller: _name,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: '제품 이름',
                      hintText: '예: Rust, Zig, Kotlin SDK',
                      counterText: '',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '제품 이름을 입력해 주세요.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<ProductCategory>(
                    value: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '분류'),
                    items: [
                      for (final category in ProductCategory.values)
                        DropdownMenuItem(
                          value: category,
                          child: Text(category.label),
                        ),
                    ],
                    onChanged: (value) => setState(() => _category = value!),
                  ),
                ] else
                  InputDecorator(
                    decoration: const InputDecoration(labelText: '소프트웨어'),
                    child:
                        Text('${_product!.name} · ${_product!.category.label}'),
                  ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _version,
                  maxLength: 40,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: '설치 버전',
                    hintText: _selection?.example,
                    counterText: '',
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  validator: (input) {
                    final product = _selection;
                    if (product == null) return null;
                    final version = product.normalizeVersion(input ?? '');
                    if (version == null) {
                      return '설치 버전을 입력해 주세요 (예: ${product.example}).';
                    }
                    if (widget.watchlist
                        .contains(product, version, except: widget.item)) {
                      return '이미 등록한 제품과 버전이에요.';
                    }
                    return null;
                  },
                ),
                if (_custom) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _linkProduct,
                        icon: const Icon(Icons.link_rounded),
                        label: Text(_selection!.canCheck
                            ? '공지 출처 변경'
                            : '제품·패키지 검색 및 연결'),
                      ),
                      if (_selection!.canCheck)
                        IconButton(
                          tooltip: '공지 출처 연결 해제',
                          onPressed: () => setState(() {
                            _linkedCpe = null;
                            _linkedNpm = null;
                          }),
                          icon: const Icon(Icons.link_off_rounded),
                        ),
                    ],
                  ),
                  Text(
                    _linkedNpm != null
                        ? 'npm · $_linkedNpm'
                        : _linkedCpe ?? '제품이나 패키지를 연결하면 등록한 버전의 공지를 확인해요.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}

enum _CatalogSource {
  npm('npm'),
  nvd('NVD');

  const _CatalogSource(this.label);
  final String label;
}

class _CatalogDialog extends StatefulWidget {
  const _CatalogDialog({
    required this.initialQuery,
    required this.watchlist,
    this.onPreset,
    this.onMatch,
    this.onManual,
  });

  final String initialQuery;
  final Watchlist watchlist;
  final ValueChanged<Product>? onPreset;
  final ValueChanged<CatalogMatch>? onMatch;
  final ValueChanged<String>? onManual;

  @override
  State<_CatalogDialog> createState() => _CatalogDialogState();
}

class _CatalogDialogState extends State<_CatalogDialog> {
  static const _typingDelay = Duration(milliseconds: 450);
  static const _searchTimeout = Duration(seconds: 15);
  static const _nestCore = CatalogMatch.npm('@nestjs/core', 'NestJS · npm');
  late final _query = TextEditingController(text: widget.initialQuery);
  final _listScrollController = ScrollController();
  final _cachedResults = <(_CatalogSource, String), CatalogPage>{};
  final _errors = <_CatalogSource, String>{};
  final _activeQueries = <_CatalogSource, String>{};
  final _queuedQueries = <_CatalogSource, String>{};
  ProductCategory? _category;
  Timer? _debounce;
  bool _expandNpmResults = false;

  bool get _showPresets => widget.onPreset != null;
  String get _term => _query.text.trim();
  CatalogPage? _results(_CatalogSource source) =>
      _cachedResults[(source, _term.toLowerCase())];
  CatalogMatch? get _quickPackage =>
      const {'nest', 'nestjs', 'nestjscore', '네스트'}.contains(_fold(_term))
          ? _nestCore
          : null;
  bool get _searching =>
      _activeQueries.containsValue(_term) ||
      _queuedQueries.containsValue(_term) ||
      (_debounce?.isActive ?? false);

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) _searchAll();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  List<Product> get _presets {
    if (!_showPresets) return [];
    final searchTerm = _fold(_query.text);
    return products.where((product) {
      return (_category == null || product.category == _category) &&
          [product.name, product.id, ...product.aliases]
              .any((value) => _fold(value).contains(searchTerm));
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  String _fold(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');

  void _queryChanged(String value) {
    _debounce?.cancel();
    _queuedQueries.clear();
    final term = value.trim();
    if (_fold(term).isNotEmpty &&
        _CatalogSource.values.any((source) => _results(source) == null)) {
      _debounce = Timer(_typingDelay, _searchAll);
    }
    setState(() {
      _errors.clear();
      _expandNpmResults = false;
    });
    if (_listScrollController.hasClients) _listScrollController.jumpTo(0);
  }

  void _searchAll() {
    _debounce?.cancel();
    for (final source in _CatalogSource.values) {
      unawaited(_search(source));
    }
  }

  Future<void> _search(_CatalogSource source, {int startIndex = 0}) async {
    final term = _term;
    if (term.isEmpty) return;
    final cacheKey = (source, term.toLowerCase());
    final cached = _cachedResults[cacheKey];
    if (startIndex == 0 && cached != null) return;
    if (startIndex != 0 && cached?.nextStartIndex != startIndex) return;
    if (_activeQueries.containsKey(source)) {
      if (startIndex == 0 && _activeQueries[source] != term) {
        setState(() => _queuedQueries[source] = term);
      }
      return;
    }
    setState(() {
      _activeQueries[source] = term;
      _errors.remove(source);
    });
    try {
      final search = switch (source) {
        _CatalogSource.npm => widget.watchlist.searchPackages,
        _CatalogSource.nvd => widget.watchlist.searchProducts,
      };
      final page =
          await search(term, startIndex: startIndex).timeout(_searchTimeout);
      if (!mounted) return;
      final unique = {
        for (final item in [...?cached?.matches, ...page.matches])
          item.key: item,
      };
      setState(() {
        if (cached == null && _cachedResults.length >= 16) {
          _cachedResults.remove(_cachedResults.keys.first);
        }
        _cachedResults[cacheKey] = CatalogPage(unique.values.toList(),
            nextStartIndex: page.nextStartIndex);
      });
    } catch (error) {
      if (mounted && _term == term) {
        setState(() => _errors[source] = switch (error) {
              TimeoutException() => '${source.label} 검색 응답이 늦어지고 있어요.',
              AdvisoryRequestException(:final message) => message,
              _ => '${source.label} 검색 결과를 불러오지 못했어요.',
            });
      }
    } finally {
      if (mounted) {
        final retryLatest = _queuedQueries[source] == _term;
        setState(() {
          _activeQueries.remove(source);
          _queuedQueries.remove(source);
        });
        if (retryLatest) unawaited(_search(source));
      }
    }
  }

  void _selectRemote(CatalogMatch match) {
    final onMatch = widget.onMatch;
    if (onMatch == null) {
      Navigator.pop(context, match);
    } else {
      onMatch(match);
    }
  }

  Widget _matchTile(CatalogMatch match) => ListTile(
        dense: true,
        title: Text(match.name),
        subtitle: Text(match.subtitle),
        onTap: () => _selectRemote(match),
      );

  List<Widget> _resultSlivers(_CatalogSource source, Set<String> presetKeys) {
    final result = _results(source);
    final matches = result?.matches
            .where((match) => !presetKeys.contains(match.key))
            .toList() ??
        [];
    final next = result?.nextStartIndex;
    final error = _errors[source];
    final busy = _activeQueries.containsKey(source);
    const previewSize = 3;
    final preview = source == _CatalogSource.npm &&
        !_expandNpmResults &&
        matches.length > previewSize;
    return [
      if (matches.isNotEmpty || next != null)
        SliverToBoxAdapter(child: _ResultHeading('${source.label} 검색 결과')),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _matchTile(matches[index]),
          childCount: preview ? previewSize : matches.length,
        ),
      ),
      if (_activeQueries[source] == _term || _queuedQueries[source] == _term)
        SliverToBoxAdapter(child: _ResultHeading('${source.label} 검색 중…')),
      if (error != null)
        SliverToBoxAdapter(
          child: Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      if (preview || next != null || error != null)
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: busy
                  ? null
                  : () {
                      if (preview) {
                        setState(() => _expandNpmResults = true);
                      } else {
                        unawaited(_search(source, startIndex: next ?? 0));
                      }
                    },
              child: Text(error == null
                  ? '${source.label} 결과 더 보기'
                  : '${source.label} 다시 시도'),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final presets = _presets;
    final quickPackage = _quickPackage;
    final presetKeys = {
      for (final product in presets) product.identity,
      if (quickPackage != null) quickPackage.key,
    };
    final noMatches = presets.isEmpty &&
        quickPackage == null &&
        _CatalogSource.values.every((source) {
          final result = _results(source);
          return result != null &&
              result.matches.isEmpty &&
              result.nextStartIndex == null;
        });
    return AlertDialog(
      title: Text(_showPresets ? '항목 등록' : '제품·패키지 연결'),
      content: SizedBox(
        width: 470,
        height: (MediaQuery.sizeOf(context).height * .62).clamp(180.0, 390.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: '제품 이름 검색',
                hintText: '예: Python, Docker, NestJS',
                counterText: '',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              textInputAction: TextInputAction.search,
              onChanged: _queryChanged,
              onSubmitted: (_) => _searchAll(),
            ),
            if (_showPresets) ...[
              const SizedBox(height: 9),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('전체'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                  for (final category in ProductCategory.values)
                    ChoiceChip(
                      label: Text(category.label),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (_searching &&
                presetKeys.isEmpty &&
                _CatalogSource.values.every(
                  (source) => _results(source)?.matches.isNotEmpty != true,
                ))
              const LinearProgressIndicator(semanticsLabel: '제품·패키지 검색 중'),
            Expanded(
              child: Scrollbar(
                controller: _listScrollController,
                thumbVisibility: true,
                child: CustomScrollView(
                  controller: _listScrollController,
                  slivers: [
                    if (presetKeys.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _ResultHeading('빠른 선택 · ${presetKeys.length}개'),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final product = presets[index];
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              title: Text(product.name),
                              trailing: Text(
                                product.category.label,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              onTap: () => widget.onPreset!(product),
                            );
                          },
                          childCount: presets.length,
                        ),
                      ),
                      if (quickPackage != null)
                        SliverToBoxAdapter(child: _matchTile(quickPackage)),
                    ],
                    for (final source in _CatalogSource.values)
                      ..._resultSlivers(source, presetKeys),
                    if (noMatches)
                      const SliverToBoxAdapter(
                        child: _ResultHeading(
                          '일치하는 제품이나 패키지가 없어요.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.onManual != null)
          TextButton(
            onPressed: () => widget.onManual!(_query.text.trim()),
            child: const Text('직접 등록'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

class _ResultHeading extends StatelessWidget {
  const _ResultHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}
