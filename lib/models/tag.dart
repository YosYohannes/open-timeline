String? normalizeTag(String raw) {
  final t = raw
      .trim()
      .replaceAll(RegExp(r'^#+'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[,\[\]{}"]'), '');
  return t.isEmpty ? null : t;
}
