import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/models/booklet.dart';
import 'package:open_timeline/models/entry.dart';
import 'package:open_timeline/ui/booklet/collage_layout.dart';
import 'package:open_timeline/ui/booklet/stamp_image.dart';

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

    Uint8List fill(int w, int h, List<int> paper, {List<int>? ink}) {
      final out = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final centre =
              x > w ~/ 4 && x < w * 3 ~/ 4 && y > h ~/ 4 && y < h * 3 ~/ 4;
          final c = centre && ink != null ? ink : paper;
          final i = (y * w + x) * 4;
          out[i] = c[0];
          out[i + 1] = c[1];
          out[i + 2] = c[2];
          out[i + 3] = 255;
        }
      }
      return out;
    }

    test('the paper colour comes from the edge, not from the ink', () {
      final paper = estimatePaper(
        fill(40, 40, [241, 230, 200], ink: [30, 78, 154]),
        40,
        40,
      )!;
      expect(
        [
          (paper.r * 255).round(),
          (paper.g * 255).round(),
          (paper.b * 255).round(),
        ],
        [241, 230, 200],
      );
    });

    test('light paper blends and dark or strongly coloured paper does not', () {
      bool light(List<int> c) =>
          isLightPaper(Color.fromARGB(255, c[0], c[1], c[2]));
      expect(light([255, 255, 255]), isTrue);
      expect(light([241, 230, 200]), isTrue);
      expect(light([201, 207, 214]), isTrue);
      expect(light([245, 217, 75]), isFalse);
      expect(light([31, 61, 43]), isFalse);
    });

    test('the blend matrix turns the paper colour into the page colour', () {
      const paper = Color(0xFFF1E6C8);
      final m = blendMatrix(paper, kPaperColor);
      expect((paper.r * m[0] - kPaperColor.r).abs(), lessThan(0.001));
      expect((paper.g * m[6] - kPaperColor.g).abs(), lessThan(0.001));
      expect((paper.b * m[12] - kPaperColor.b).abs(), lessThan(0.001));
      expect(m.length, 20);
      expect(m.every((v) => v.isFinite), isTrue);
      expect(math.max(m[0], math.max(m[6], m[12])), lessThanOrEqualTo(4.0));
    });
  });
}
