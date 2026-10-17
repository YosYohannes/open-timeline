import 'package:flutter/material.dart';

import '../../models/countries.dart';

Future<({String? code})?> showCountryPicker(
  BuildContext context, {
  required String? selected,
  required List<String> used,
}) {
  return showModalBottomSheet<({String? code})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _CountryList(selected: selected, used: used),
  );
}

class _CountryList extends StatefulWidget {
  const _CountryList({required this.selected, required this.used});

  final String? selected;
  final List<String> used;

  @override
  State<_CountryList> createState() => _CountryListState();
}

class _CountryListState extends State<_CountryList> {
  String _query = '';

  List<String> get _matches {
    final q = _query.trim().toLowerCase();
    final all = kCountries.keys.toList()
      ..sort((a, b) => countryName(a).compareTo(countryName(b)));
    if (q.isEmpty) return all;
    return all
        .where(
          (c) =>
              countryName(c).toLowerCase().contains(q) || c.toLowerCase() == q,
        )
        .toList();
  }

  Widget _tile(BuildContext context, String code) => ListTile(
    key: ValueKey('country-$code'),
    leading: Text(countryFlag(code), style: const TextStyle(fontSize: 24)),
    title: Text(countryName(code)),
    trailing: Text(code, style: Theme.of(context).textTheme.bodySmall),
    selected: code == widget.selected,
    onTap: () => Navigator.pop(context, (code: code)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searching = _query.trim().isNotEmpty;
    final matches = _matches;
    final used = [
      for (final c in widget.used)
        if (kCountries.containsKey(c)) c,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: false,
                decoration: const InputDecoration(
                  hintText: 'Search countries',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (!searching) ...[
                    ListTile(
                      leading: const Icon(Icons.clear_all),
                      title: const Text('No country'),
                      selected: widget.selected == null,
                      onTap: () => Navigator.pop(context, (code: null)),
                    ),
                    if (used.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          'Used before',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      for (final c in used) _tile(context, c),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          'All countries',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                  for (final c in matches) _tile(context, c),
                  if (searching && matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No country matches'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
