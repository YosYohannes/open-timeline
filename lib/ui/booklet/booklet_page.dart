import 'package:flutter/material.dart';

import '../../models/booklet.dart';
import '../../models/countries.dart';
import '../../models/entry.dart';
import '../../store/journal_store.dart';
import '../app/store_scope.dart';
import 'book_pager.dart';
import 'collage_layout.dart';
import 'stamp_image.dart';
import 'stamp_print.dart';

const _tabColors = [
  Color(0xFFE0795F),
  Color(0xFF8FB5A0),
  Color(0xFFE3C26A),
  Color(0xFF9BA7D6),
  Color(0xFFD69BB5),
  Color(0xFFB5A07A),
];

const _pageInset = 16.0;
const _headerHeight = 26.0;
const _footerHeight = 22.0;

class BookletPage extends StatefulWidget {
  const BookletPage({super.key, required this.country});

  final String? country;

  @override
  State<BookletPage> createState() => _BookletPageState();
}

class _PageSpec {
  _PageSpec({
    required this.section,
    required this.placed,
    required this.number,
  });

  final int section;
  final List<Placed> placed;
  final int number;
}

class _BookletPageState extends State<BookletPage> {
  final _book = BookController();

  @override
  void dispose() {
    _book.dispose();
    super.dispose();
  }

  Booklet? _find(List<Booklet> all) =>
      all.where((b) => b.country == widget.country).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final booklet = _find(store.booklets);
    final title = widget.country == null
        ? 'Unsorted'
        : countryLabel(widget.country!);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ListenableBuilder(
            listenable: _book,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  booklet == null
                      ? ''
                      : (_book.page == 0 ? 'Cover' : 'Page ${_book.page}'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ],
      ),
      body: booklet == null
          ? const Center(child: Text('This booklet is empty'))
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 0, 16),
              child: LayoutBuilder(
                builder: (context, box) =>
                    _buildBook(context, booklet, box.biggest),
              ),
            ),
    );
  }

  Widget _buildBook(BuildContext context, Booklet booklet, Size size) {
    final store = StoreScope.read(context);
    final bookWidth = size.width - 24;
    final area = Size(
      bookWidth - _pageInset * 2,
      size.height - _pageInset * 2 - _headerHeight - _footerHeight,
    );
    final specs = <_PageSpec>[];
    final starts = <int>[];
    for (var s = 0; s < booklet.sections.length; s++) {
      final stamps = booklet.sections[s].stamps;
      final items = [
        for (final e in stamps)
          CollageItem(id: e.id, ratio: _ratioOf(store, e), size: e.size),
      ];
      starts.add(specs.length + 1);
      final pages = layoutCollage(items, area);
      for (var p = 0; p < pages.length; p++) {
        specs.add(_PageSpec(section: s, placed: pages[p], number: p + 1));
      }
    }
    final byId = {for (final e in booklet.stamps) e.id: e};

    final pages = <Widget>[
      _Cover(booklet: booklet),
      for (var i = 0; i < specs.length; i++)
        _Paper(
          title: booklet.sections[specs[i].section].series.isEmpty
              ? 'Other'
              : booklet.sections[specs[i].section].series,
          number: i + 1,
          total: specs.length,
          children: [
            for (final p in specs[i].placed)
              if (byId[p.id] != null) StampPrint(entry: byId[p.id]!, placed: p),
          ],
        ),
    ];

    return Stack(
      children: [
        Positioned.fill(
          right: 24,
          child: BookPager(pages: pages, controller: _book),
        ),
        Positioned(
          right: 0,
          top: 24,
          width: 24,
          child: ListenableBuilder(
            listenable: _book,
            builder: (context, _) {
              final page = _book.page;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var s = 0; s < booklet.sections.length; s++)
                    _Tab(
                      key: ValueKey('tab-$s'),
                      label: booklet.sections[s].series.isEmpty
                          ? 'Other'
                          : booklet.sections[s].series,
                      color: _tabColors[s % _tabColors.length],
                      selected:
                          page >= starts[s] &&
                          (s + 1 >= starts.length || page < starts[s + 1]),
                      onTap: () => _book.goTo(starts[s]),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  double _ratioOf(JournalStore store, Entry e) {
    final image = e.media.where(isImage).firstOrNull;
    if (image == null) return 1.0;
    return aspectRatioOf(store.mediaFile(e, image));
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: selected ? 24 : 18,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(6),
              ),
            ),
            child: RotatedBox(
              quarterTurns: 1,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({
    required this.title,
    required this.number,
    required this.total,
    required this.children,
  });

  final String title;
  final int number;
  final int total;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kPaperColor,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(_pageInset),
            child: Column(
              children: [
                SizedBox(
                  height: _headerHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kInkBrown,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(child: Stack(children: children)),
                SizedBox(
                  height: _footerHeight,
                  child: Center(
                    child: Text(
                      '$number',
                      style: const TextStyle(color: kInkBrown, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.booklet});

  final Booklet booklet;

  static String _span(Booklet b) {
    String m(DateTime d) =>
        '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
    final a = m(b.first);
    final z = m(b.last);
    return a == z ? a : '$a – $z';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = booklet.country;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A18),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
        border: Border.all(color: const Color(0xFF3A372F)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              code == null ? '📖' : countryFlag(code),
              style: const TextStyle(fontSize: 72),
            ),
            const SizedBox(height: 16),
            Text(
              booklet.name,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: const Color(0xFFE9DFC8),
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${booklet.count} ${booklet.count == 1 ? 'stamp' : 'stamps'}',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFFB9AE95),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _span(booklet),
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8E846E),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Swipe to turn the page',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6E664F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
