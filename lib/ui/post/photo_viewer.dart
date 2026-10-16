import 'dart:io';

import 'package:flutter/material.dart';

Future<void> showPhotoViewer(
  BuildContext context,
  List<File> files, {
  int initialIndex = 0,
}) {
  if (files.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: _PhotoViewer(files: files, initialIndex: initialIndex),
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.files, required this.initialIndex});

  final List<File> files;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.files.length - 1);
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pages,
          itemCount: widget.files.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) {
            final file = widget.files[i];
            if (!file.existsSync()) return const _Missing('File missing');
            return InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const _Missing('Cannot show this image'),
                ),
              ),
            );
          },
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    color: Colors.white,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (widget.files.length > 1)
                    Text(
                      '${_index + 1} / ${widget.files.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.image_not_supported_outlined,
            color: Colors.white54,
            size: 64,
          ),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
