import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_timeline/ui/post/video_prep.dart';

class FakeVideoTools implements VideoTools {
  FakeVideoTools(
    this.info_, {
    this.shrinkResult = 'ok',
    this.shrinkThrows = false,
  });

  final VideoInfo? info_;
  final String? shrinkResult;
  final bool shrinkThrows;
  int shrinkCalls = 0;

  @override
  Future<VideoInfo?> info(String path) async => info_;

  @override
  Future<String?> shrink(
    String src,
    String dest, {
    void Function(double progress)? onProgress,
  }) async {
    shrinkCalls++;
    if (shrinkThrows) throw Exception('boom');
    if (shrinkResult == null) return null;
    File(dest).writeAsBytesSync(List.filled(1000, 1));
    return dest;
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  test('only videos above 1080p on the short side are shrunk', () {
    expect(needsShrink(const VideoInfo(3840, 2160)), isTrue);
    expect(needsShrink(const VideoInfo(2160, 3840)), isTrue);
    expect(needsShrink(const VideoInfo(1920, 1080)), isFalse);
    expect(needsShrink(const VideoInfo(1080, 1920)), isFalse);
    expect(needsShrink(const VideoInfo(1280, 720)), isFalse);
  });

  test('sizes read naturally', () {
    expect(formatBytes(500 * 1024), '500 KB');
    expect(formatBytes(120 * 1024 * 1024), '120 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
  });

  group('prepareVideo', () {
    late Directory dir;
    late File source;
    PreparedVideo? result;
    var finished = false;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('video_prep_');
      source = File('${dir.path}/clip.mp4')..writeAsBytesSync([1, 2, 3]);
      result = null;
      finished = false;
    });

    Future<void> start(WidgetTester tester, VideoTools tools) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await prepareVideo(
                    context,
                    source,
                    tools: tools,
                    tempDir: dir,
                  );
                  finished = true;
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 100 && !finished; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.text('Large video').evaluate().isNotEmpty) break;
      }
    }

    testWidgets('a small 1080p video is used as it is', (tester) async {
      final tools = FakeVideoTools(const VideoInfo(1920, 1080));
      await start(tester, tools);
      await settle(tester);
      expect(finished, isTrue);
      expect(result!.file.path, source.path);
      expect(result!.isTemp, isFalse);
      expect(tools.shrinkCalls, 0);
    });

    testWidgets('a 4K video is shrunk to a temp file', (tester) async {
      final tools = FakeVideoTools(const VideoInfo(3840, 2160));
      await start(tester, tools);
      await settle(tester);
      expect(finished, isTrue);
      expect(tools.shrinkCalls, 1);
      expect(result!.isTemp, isTrue);
      expect(result!.file.path, startsWith('${dir.path}/shrunk_'));
    });

    testWidgets('cancelling the shrink adds nothing', (tester) async {
      final tools = FakeVideoTools(
        const VideoInfo(3840, 2160),
        shrinkResult: null,
      );
      await start(tester, tools);
      await settle(tester);
      expect(finished, isTrue);
      expect(result, isNull);
    });

    testWidgets('a failed shrink falls back to the original', (tester) async {
      final tools = FakeVideoTools(
        const VideoInfo(3840, 2160),
        shrinkThrows: true,
      );
      await start(tester, tools);
      await settle(tester);
      expect(finished, isTrue);
      expect(result!.file.path, source.path);
      expect(find.textContaining('Could not shrink'), findsOneWidget);
    });

    testWidgets('a large video asks first, and Cancel adds nothing', (
      tester,
    ) async {
      final raf = source.openSync(mode: FileMode.write)
        ..truncateSync(kVideoWarnBytes + 1024);
      raf.closeSync();
      await start(tester, FakeVideoTools(const VideoInfo(1280, 720)));
      await settle(tester);
      expect(find.text('Large video'), findsOneWidget);
      expect(find.textContaining('MB'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await settle(tester);
      expect(finished, isTrue);
      expect(result, isNull);
    });

    testWidgets('a large video is added after Add anyway', (tester) async {
      final raf = source.openSync(mode: FileMode.write)
        ..truncateSync(kVideoWarnBytes + 1024);
      raf.closeSync();
      await start(tester, FakeVideoTools(const VideoInfo(1280, 720)));
      await settle(tester);
      await tester.tap(find.text('Add anyway'));
      await tester.pump();
      await settle(tester);
      expect(finished, isTrue);
      expect(result!.file.path, source.path);
    });
  });
}
