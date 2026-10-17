import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/booklet.dart';
import '../../models/countries.dart';
import '../../models/entry.dart';
import '../../store/journal_store.dart';
import '../app/store_scope.dart';
import 'book_cover.dart';
import 'book_pager.dart';
import 'collage_layout.dart';
import 'stamp_cutout.dart';
import 'stamp_image.dart';
import 'stamp_print.dart';

const kBookRatio = 0.70710678;
const _contentsPage = 1;
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
  _PageSpec({required this.section, required this.placed});

  final int section;
  final List<Placed> placed;
}

class _BookletPageState extends State<BookletPage> {
  final _book = BookController();
  String _signature = '';
  Future<void>? _ready;
  String _layoutKey = '';
  List<_PageSpec> _specs = const [];
  List<int> _starts = const [];

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
      appBar: AppBar(title: Text(title)),
      body: booklet == null
          ? const Center(child: Text('This booklet is empty'))
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: _withCutouts(
                booklet,
                (context) => LayoutBuilder(
                  builder: (context, box) =>
                      _buildBook(context, booklet, box.biggest),
                ),
              ),
            ),
    );
  }

  List<(File, String)> _cutoutFiles(Booklet booklet) {
    final store = StoreScope.read(context);
    return [
      for (final e in booklet.stamps)
        if (e.blend && e.media.any(isImage))
          (store.mediaFile(e, e.media.firstWhere(isImage)), e.cutout),
    ];
  }

  Widget _withCutouts(Booklet booklet, WidgetBuilder builder) {
    final files = _cutoutFiles(booklet);
    final signature = [
      for (final e in booklet.stamps)
        '${e.id}:${e.media.join(',')}:${e.blend}:${e.size}:${e.cutout}',
    ].join('|');
    if (signature != _signature) {
      _signature = signature;
      final pending = [
        for (final f in files)
          if (!hasCutout(f.$1, f.$2)) f,
      ];
      _ready = pending.isEmpty
          ? null
          : Future.wait([for (final f in pending) cutoutOf(f.$1, f.$2)]);
    }
    final ready = _ready;
    if (ready == null) return builder(context);
    return FutureBuilder<void>(
      future: ready,
      builder: (context, snap) => snap.connectionState == ConnectionState.done
          ? builder(context)
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildBook(BuildContext context, Booklet booklet, Size size) {
    final store = StoreScope.read(context);
    var bookWidth = size.width;
    var bookHeight = bookWidth / kBookRatio;
    if (bookHeight > size.height) {
      bookHeight = size.height;
      bookWidth = bookHeight * kBookRatio;
    }
    final area = Size(
      bookWidth - _pageInset * 2,
      bookHeight - _pageInset * 2 - _headerHeight - _footerHeight,
    );
    final key = '$_signature|${area.width}|${area.height}';
    if (key != _layoutKey) {
      _layoutKey = key;
      final specs = <_PageSpec>[];
      final starts = <int>[];
      for (var s = 0; s < booklet.sections.length; s++) {
        final items = [
          for (final e in booklet.sections[s].stamps) _itemOf(store, e),
        ];
        starts.add(_contentsPage + 1 + specs.length);
        for (final page in layoutCollage(items, area)) {
          specs.add(_PageSpec(section: s, placed: page));
        }
      }
      _specs = specs;
      _starts = starts;
    }
    final specs = _specs;
    final starts = _starts;
    final byId = {for (final e in booklet.stamps) e.id: e};
    String seriesName(int s) => booklet.sections[s].series.isEmpty
        ? 'Other'
        : booklet.sections[s].series;
    void toContents() => _book.goTo(_contentsPage);

    final pages = <Widget>[
      BookCover(booklet: booklet),
      _Paper(
        title: 'Contents',
        number: _contentsPage,
        child: _Contents(
          rows: [
            for (var s = 0; s < booklet.sections.length; s++)
              (
                name: seriesName(s),
                count: booklet.sections[s].stamps.length,
                page: starts[s],
              ),
          ],
          onOpen: _book.goTo,
        ),
      ),
      for (var i = 0; i < specs.length; i++)
        _Paper(
          title: seriesName(specs[i].section),
          number: _contentsPage + 1 + i,
          onNumberTap: toContents,
          child: Stack(
            children: [
              for (final p in specs[i].placed)
                if (byId[p.id] != null)
                  StampPrint(entry: byId[p.id]!, placed: p),
            ],
          ),
        ),
    ];

    return Center(
      child: SizedBox(
        width: bookWidth,
        height: bookHeight,
        child: BookPager(pages: pages, controller: _book),
      ),
    );
  }

  CollageItem _itemOf(JournalStore store, Entry e) {
    final image = e.media.where(isImage).firstOrNull;
    if (image == null) {
      return CollageItem(id: e.id, ratio: 1.0, size: e.size);
    }
    final file = store.mediaFile(e, image);
    final cut = e.blend ? cachedCutout(file, e.cutout) : null;
    return CollageItem(
      id: e.id,
      ratio: cut?.ratio ?? aspectRatioOf(file),
      size: e.size,
      mask: cut?.mask,
    );
  }
}

class _Contents extends StatelessWidget {
  const _Contents({required this.rows, required this.onOpen});

  final List<({String name, int count, int page})> rows;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 18),
      children: [
        for (var i = 0; i < rows.length; i++)
          InkWell(
            key: ValueKey('contents-$i'),
            onTap: () => onOpen(rows[i].page),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      rows[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF3D372B),
                        fontSize: 16,
                        fontFamily: 'serif',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    rows[i].count == 1 ? '1 stamp' : '${rows[i].count} stamps',
                    style: const TextStyle(color: kInkBrown, fontSize: 10),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
                      child: CustomPaint(
                        size: Size(double.infinity, 2),
                        painter: _Dots(),
                      ),
                    ),
                  ),
                  Text(
                    '${rows[i].page}',
                    style: const TextStyle(
                      color: Color(0xFF3D372B),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Dots extends CustomPainter {
  const _Dots();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFB9AE95);
    for (var x = 0.0; x < size.width; x += 5) {
      canvas.drawCircle(Offset(x + 1, size.height / 2), 0.9, paint);
    }
  }

  @override
  bool shouldRepaint(_Dots old) => false;
}

class _Paper extends StatelessWidget {
  const _Paper({
    required this.title,
    required this.number,
    required this.child,
    this.onNumberTap,
  });

  final String title;
  final int number;
  final Widget child;
  final VoidCallback? onNumberTap;

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
                Expanded(child: child),
                SizedBox(
                  height: _footerHeight,
                  child: Center(
                    child: InkWell(
                      key: ValueKey('page-number-$number'),
                      onTap: onNumberTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '$number',
                          style: const TextStyle(
                            color: kInkBrown,
                            fontSize: 11,
                          ),
                        ),
                      ),
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
