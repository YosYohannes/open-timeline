import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

const kPaperColor = ui.Color(0xFFF3ECDD);

ui.Size? pngSize(Uint8List head) {
  if (head.length < 24) return null;
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    if (head[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(head);
  final w = data.getUint32(16);
  final h = data.getUint32(20);
  if (w == 0 || h == 0) return null;
  return ui.Size(w.toDouble(), h.toDouble());
}

final _ratios = <String, double>{};

double aspectRatioOf(File file) {
  return _ratios.putIfAbsent(file.path, () {
    try {
      final raf = file.openSync();
      try {
        final size = pngSize(raf.readSync(24));
        return size == null ? 1.0 : size.width / size.height;
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return 1.0;
    }
  });
}
