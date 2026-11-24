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

  @override
  void initState() {
    super.initState();
    final existing = widget.item?.product;
    _custom = existing?.id.startsWith('custom:') ?? false;
    _category = existing?.category ?? ProductCategory.sdk;
    _product = _custom ? null : existing;
    _linkedCpe = _custom ? existing?.cpe : null;
  }

  @override
  void dispose() {
    _version.dispose();
    _name.dispose();
    super.dispose();
  }

  Product? get _selection => _custom
      ? Product.custom(
          name: _name.text.trim(), category: _category, cpe: _linkedCpe)
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

  Future<void> _linkProduct() async {
    final match = await showDialog<CatalogMatch>(
      context: context,
      builder: (_) => _CatalogDialog(
        initialQuery: _name.text.trim(),
        search: widget.watchlist.searchProducts,
      ),
    );
    if (mounted && match != null) setState(() => _linkedCpe = match.cpe);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
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
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('빠른 선택')),
                        ButtonSegment(value: true, label: Text('직접 등록')),
                      ],
                      selected: {_custom},
                      onSelectionChanged: (value) =>
                          setState(() => _custom = value.first),
                    ),
                    const SizedBox(height: 14),
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
                      validator: (value) =>
                          value == null || value.trim().isEmpty
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
                    DropdownButtonFormField<Product>(
                      value: _product,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '소프트웨어'),
                      items: [
                        for (final product in products)
                          DropdownMenuItem(
                            value: product,
                            child: Text(
                                '${product.name} · ${product.category.label}'),
                          ),
                      ],
                      onChanged: widget.item == null
                          ? (value) => setState(() => _product = value)
                          : null,
                      validator: (value) =>
                          value == null ? '제품을 선택해 주세요.' : null,
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
                          label: Text(_linkedCpe == null
                              ? 'NVD 제품 검색 및 연결'
                              : 'NVD 제품 변경'),
                        ),
                        if (_linkedCpe != null)
                          IconButton(
                            tooltip: '공지 출처 연결 해제',
                            onPressed: () => setState(() => _linkedCpe = null),
                            icon: const Icon(Icons.link_off_rounded),
                          ),
                      ],
                    ),
                    Text(
                      _linkedCpe ?? '제품을 연결하면 등록한 버전의 공지를 확인해요.',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
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

class _CatalogDialog extends StatefulWidget {
  const _CatalogDialog({required this.initialQuery, required this.search});

  final String initialQuery;
  final Future<List<CatalogMatch>> Function(String) search;

  @override
  State<_CatalogDialog> createState() => _CatalogDialogState();
}

class _CatalogDialogState extends State<_CatalogDialog> {
  late final _query = TextEditingController(text: widget.initialQuery);
  List<CatalogMatch>? _results;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) unawaited(_search());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final term = _query.text.trim();
    if (term.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _results = null;
    });
    try {
      final results = await widget.search(term);
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is AdvisoryRequestException
            ? error.message
            : 'NVD 제품 목록을 불러오지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('NVD 제품 연결'),
        content: SizedBox(
          width: 440,
          height: (MediaQuery.sizeOf(context).height * .54).clamp(180.0, 350.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: '제품 또는 공급사 이름',
                        counterText: '',
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _loading ? null : _search,
                    child: const Text('검색'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_results?.isEmpty ?? false)
                const Text('제품을 찾지 못했어요. 공식 제품명이나 공급사 이름으로 검색해 보세요.'),
              if (_results?.isNotEmpty ?? false)
                Expanded(
                  child: ListView.builder(
                    itemCount: _results!.length,
                    itemBuilder: (context, index) {
                      final match = _results![index];
                      return ListTile(
                        title: Text(match.product.replaceAll('_', ' ')),
                        subtitle: Text(match.vendor.replaceAll('_', ' ')),
                        trailing: const Icon(Icons.link_rounded),
                        onTap: () => Navigator.pop(context, match),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      );
}
