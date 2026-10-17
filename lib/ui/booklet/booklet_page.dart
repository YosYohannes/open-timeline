import 'package:flutter/material.dart';

import '../../models/booklet.dart';
import '../../models/countries.dart';
import '../../models/entry.dart';
import '../../store/journal_store.dart';
import '../app/store_scope.dart';
import 'book_cover.dart';
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

const kBookRatio = 0.70710678;
const _tabHeight = 30.0;
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
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: LayoutBuilder(
                builder: (context, box) =>
                    _buildBook(context, booklet, box.biggest),
              ),
            ),
    );
  }

  Widget _buildBook(BuildContext context, Booklet booklet, Size size) {
    final store = StoreScope.read(context);
    final room = size.height - _tabHeight;
    var bookWidth = size.width;
    var bookHeight = bookWidth / kBookRatio;
    if (bookHeight > room) {
      bookHeight = room;
      bookWidth = bookHeight * kBookRatio;
    }
    final left = (size.width - bookWidth) / 2;
    final top = _tabHeight + (room - bookHeight) / 2;
    final area = Size(
      bookWidth - _pageInset * 2,
      bookHeight - _pageInset * 2 - _headerHeight - _footerHeight,
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
      BookCover(booklet: booklet),
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
        Positioned(
          left: left,
          top: top,
          width: bookWidth,
          height: bookHeight,
          child: BookPager(pages: pages, controller: _book),
        ),
        Positioned(
          left: left,
          top: top - _tabHeight,
          width: bookWidth,
          height: _tabHeight,
          child: ListenableBuilder(
            listenable: _book,
            builder: (context, _) {
              final page = _book.page;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
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
                ),
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
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 140),
          height: selected ? _tabHeight : _tabHeight - 6,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111111),
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
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
