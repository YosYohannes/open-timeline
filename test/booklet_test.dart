import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/booklet.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/ui/booklet/collage_layout.dart';
import 'package:open_timeline/ui/booklet/stamp_cutout.dart';
import 'package:open_timeline/ui/booklet/stamp_image.dart';
import 'package:open_timeline/ui/booklet/subject_segmenter.dart';

Entry stamp(
  String id, {
  String? country,
  String series = '',
  DateTime? time,
  String kind = kindStamp,
  bool deleted = false,
}) => Entry(
  id: id,
  kind: kind,
  author: 'a@x',
  time: time ?? DateTime.utc(2026, 10, 17),
  utcOffsetMinutes: 0,
  country: country,
  series: series,
  deleted: deleted,
  updated: DateTime.utc(2026, 10, 17),
);

void main() {
  group('booklets', () {
    test('one booklet per country, sorted by name, with Unsorted last', () {
      final booklets = buildBooklets([
        stamp('20261001-100000-aaaa', country: 'TW'),
        stamp('20261002-100000-bbbb', country: 'JP'),
        stamp('20261003-100000-cccc'),
        stamp('20261004-100000-dddd', country: 'JP'),
      ]);
      expect(booklets.map((b) => b.name), ['Japan', 'Taiwan', 'Unsorted']);
      expect(booklets.map((b) => b.count), [2, 1, 1]);
      expect(booklets.last.country, isNull);
    });

    test('posts and deleted entries never appear', () {
      final booklets = buildBooklets([
        stamp('20261001-100000-aaaa', country: 'JP', kind: kindPost),
        stamp('20261002-100000-bbbb', country: 'JP', deleted: true),
        stamp('20261003-100000-cccc', country: 'JP'),
      ]);
      expect(booklets.single.count, 1);
    });

    test(
      'series run in the order they were started, Other last, stamps by date',
      () {
        final b = buildBooklets([
          stamp(
            '20260901-100000-aaaa',
            country: 'JP',
            series: 'Metro',
            time: DateTime.utc(2026, 9, 1),
          ),
          stamp(
            '20260801-100000-bbbb',
            country: 'JP',
            series: 'JR',
            time: DateTime.utc(2026, 8, 1),
          ),
          stamp(
            '20260701-100000-cccc',
            country: 'JP',
            time: DateTime.utc(2026, 7, 1),
          ),
          stamp(
            '20260815-100000-dddd',
            country: 'JP',
            series: 'JR',
            time: DateTime.utc(2026, 8, 15),
          ),
          stamp(
            '20260805-100000-eeee',
            country: 'JP',
            series: 'JR',
            time: DateTime.utc(2026, 8, 5),
          ),
        ]).single;
        expect(b.sections.map((s) => s.series), ['JR', 'Metro', '']);
        expect(b.sections.first.stamps.map((e) => e.id), [
          '20260801-100000-bbbb',
          '20260805-100000-eeee',
          '20260815-100000-dddd',
        ]);
        expect(b.first, DateTime.utc(2026, 7, 1));
        expect(b.last, DateTime.utc(2026, 9, 1));
        expect(b.latest.id, '20260901-100000-aaaa');
      },
    );
  });

  group('collage', () {
    const area = Size(340, 520);
    List<CollageItem> items(
      int n, {
      String size = sizeMedium,
      double ratio = 1,
    }) => [
      for (var i = 0; i < n; i++)
        CollageItem(id: 'i$i', ratio: ratio, size: size),
    ];

    test('every item is placed exactly once, inside the page', () {
      final pages = layoutCollage(items(25), area);
      final ids = pages.expand((p) => p).map((p) => p.id).toList();
      expect(ids, [for (var i = 0; i < 25; i++) 'i$i']);
      for (final page in pages) {
        for (final p in page) {
          expect(p.rect.left, greaterThanOrEqualTo(-0.01));
          expect(p.rect.right, lessThanOrEqualTo(area.width + 0.01));
          expect(p.rect.top, greaterThanOrEqualTo(-0.01));
          expect(p.rect.bottom, lessThanOrEqualTo(area.height + 0.01));
        }
      }
    });

    test('items on a page never overlap', () {
      final pages = layoutCollage([
        const CollageItem(id: 'a', ratio: 1, size: sizeLarge),
        const CollageItem(id: 'b', ratio: 1.6, size: sizeSmall),
        const CollageItem(id: 'c', ratio: 0.6, size: sizeMedium),
        const CollageItem(id: 'd', ratio: 1, size: sizeMedium),
        const CollageItem(id: 'e', ratio: 2.2, size: sizeLarge),
        const CollageItem(id: 'f', ratio: 1, size: sizeSmall),
      ], area);
      for (final page in pages) {
        for (var i = 0; i < page.length; i++) {
          for (var j = i + 1; j < page.length; j++) {
            expect(
              page[i].rect.deflate(0.5).overlaps(page[j].rect.deflate(0.5)),
              isFalse,
            );
          }
        }
      }
    });

    test(
      'keeps each image ratio and a large stamp is bigger than a small one',
      () {
        final page = layoutCollage([
          const CollageItem(id: 's', ratio: 1.5, size: sizeSmall),
          const CollageItem(id: 'l', ratio: 1.5, size: sizeLarge),
        ], area).first;
        final small = page.firstWhere((p) => p.id == 's').image;
        final large = page.firstWhere((p) => p.id == 'l').image;
        expect(small.width / small.height, closeTo(1.5, 0.01));
        expect(large.width / large.height, closeTo(1.5, 0.01));
        expect(large.width, greaterThan(small.width));
      },
    );

    test('a very wide or very tall stamp still fits the page', () {
      final pages = layoutCollage([
        const CollageItem(id: 'w', ratio: 4, size: sizeLarge),
        const CollageItem(id: 't', ratio: 0.25, size: sizeLarge),
      ], area);
      for (final p in pages.expand((x) => x)) {
        expect(p.rect.width, lessThanOrEqualTo(area.width + 0.01));
        expect(p.rect.height, lessThanOrEqualTo(area.height + 0.01));
      }
    });

    test(
      'more stamps need more pages, none is empty, and an empty list has none',
      () {
        expect(layoutCollage(const [], area), isEmpty);
        final few = layoutCollage(items(3), area);
        final many = layoutCollage(items(40), area);
        expect(few.length, 1);
        expect(many.length, greaterThan(few.length));
        expect(many.every((p) => p.isNotEmpty), isTrue);
      },
    );

    test('a small stamp tucks into the notch of an L-shaped one', () {
      final cells = Uint8List(64);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          cells[y * 8 + x] = x >= 4 && y < 4 ? 0 : 1;
        }
      }
      final l = CutoutMask(width: 8, height: 8, filled: cells);
      final full = CutoutMask(
        width: 2,
        height: 2,
        filled: Uint8List(4)..fillRange(0, 4, 1),
      );
      final page = layoutCollage([
        CollageItem(id: 'l', ratio: 1, size: sizeLarge, mask: l),
        CollageItem(id: 's', ratio: 0.8, size: sizeSmall, mask: full),
      ], const Size(240, 520)).single;
      final big = page.firstWhere((p) => p.id == 'l').rect;
      final small = page.firstWhere((p) => p.id == 's').rect;
      expect(small.top, lessThan(big.bottom - 20));
      expect(small.left, greaterThan(big.left + big.width / 2 - 10));
    });

    test('a shorter page repaginates into more pages', () {
      final short = layoutCollage(items(12), const Size(340, 300));
      final tall = layoutCollage(items(12), const Size(340, 800));
      expect(short.length, greaterThan(tall.length));
    });
  });

  group('stamp image', () {
    Uint8List png(int w, int h) {
      final b = ByteData(24);
      const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      for (var i = 0; i < 8; i++) {
        b.setUint8(i, sig[i]);
      }
      b.setUint32(16, w);
      b.setUint32(20, h);
      return b.buffer.asUint8List();
    }

    test('reads the size from a PNG header', () {
      expect(pngSize(png(300, 200)), const Size(300, 200));
      expect(pngSize(Uint8List(10)), isNull);
      expect(pngSize(png(0, 5)), isNull);
      final jpg = Uint8List(30)..[0] = 0xFF;
      expect(pngSize(jpg), isNull);
    });

    test('the ratio of a file falls back to square', () {
      final dir = Directory.systemTemp.createTempSync('ratio_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final good = File('${dir.path}/a.png')..writeAsBytesSync(png(300, 200));
      final bad = File('${dir.path}/b.png')..writeAsBytesSync([1, 2, 3]);
      expect(aspectRatioOf(good), closeTo(1.5, 0.001));
      expect(aspectRatioOf(bad), 1.0);
      expect(aspectRatioOf(File('${dir.path}/missing.png')), 1.0);
    });

    test(
      'a picture with a transparent background is trimmed to its subject',
      () {
        final rgba = Uint8List(60 * 40 * 4);
        for (var y = 10; y < 30; y++) {
          for (var x = 20; x < 50; x++) {
            rgba[(y * 60 + x) * 4 + 3] = 255;
          }
        }
        final r = trimToSubject(rgba, 60, 40)!;
        expect((r.width, r.height), (30, 20));
        expect(trimToSubject(Uint8List(60 * 40 * 4), 60, 40), isNull);
      },
    );

    test('the outline mask marks the stamp, not the corners', () {
      final rgba = Uint8List(100 * 100 * 4);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          if ((x - 50) * (x - 50) + (y - 50) * (y - 50) < 35 * 35) {
            rgba[(y * 100 + x) * 4 + 3] = 255;
          }
        }
      }
      final r = trimToSubject(rgba, 100, 100)!;
      final mask = maskOf(r.rgba, r.width, r.height);
      expect(mask.at(0.5, 0.5), isTrue);
      expect(mask.at(0.02, 0.02), isFalse);
      expect(mask.at(0.98, 0.98), isFalse);
    });
  });

  group('the phone finds the item', () {
    late SubjectSegmenter saved;
    setUp(() => saved = subjectSegmenter);
    tearDown(() => subjectSegmenter = saved);

    Future<File> png(int w, int h, void Function(Canvas) paint) async {
      final rec = ui.PictureRecorder();
      paint(Canvas(rec));
      final img = await rec.endRecording().toImage(w, h);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return File(
        '${Directory.systemTemp.createTempSync('subject_').path}/s.png',
      )..writeAsBytesSync(data!.buffer.asUint8List());
    }

    test('its cut-out is trimmed and cached', () async {
      final photo = await png(
        120,
        100,
        (c) => c.drawRect(
          const Rect.fromLTWH(0, 0, 120, 100),
          Paint()..color = const Color(0xFFCCCCCC),
        ),
      );
      final subject = await png(
        120,
        100,
        (c) => c.drawRect(
          const Rect.fromLTWH(30, 20, 60, 60),
          Paint()..color = const Color(0xFF123456),
        ),
      );
      subjectSegmenter = _Fixed(subject);
      final cut = await cutoutOf(photo);
      expect(cut, isNotNull);
      expect(cut!.ratio, closeTo(1.0, 0.05));
      expect(cachedCutout(photo), same(cut));
    });

    test('a failure of the AI itself is not remembered', () async {
      final photo = await png(
        40,
        40,
        (c) => c.drawRect(
          const Rect.fromLTWH(0, 0, 40, 40),
          Paint()..color = const Color(0xFFCCCCCC),
        ),
      );
      subjectSegmenter = _Fixed(null, error: 'still downloading');
      expect(await cutoutOf(photo), isNull);
      expect(hasCutout(photo), isFalse);
    });

    test('no subject found means no cut-out', () async {
      final photo = await png(
        40,
        40,
        (c) => c.drawRect(
          const Rect.fromLTWH(0, 0, 40, 40),
          Paint()..color = const Color(0xFFCCCCCC),
        ),
      );
      subjectSegmenter = _Fixed(null);
      expect(await cutoutOf(photo), isNull);
      expect(hasCutout(photo), isTrue);
    });
  });
}

class _Fixed implements SubjectSegmenter {
  _Fixed(this.result, {this.error});

  final File? result;
  final String? error;

  @override
  String? get lastError => error;

  @override
  Future<List<Rect>?> detect(File image) async => null;

  @override
  Future<File?> segment(File image) async => result;
}
