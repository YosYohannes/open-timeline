import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:open_filex/open_filex.dart';

import '../../models/entry.dart';
import '../../store/journal_store.dart';
import '../app/store_scope.dart';
import '../widgets/author.dart';
import '../widgets/format.dart';
import '../widgets/media_tile.dart';
import '../widgets/snack.dart';
import 'location_map.dart';
import 'photo_viewer.dart';

class PostPage extends StatefulWidget {
  const PostPage({super.key, required this.entry, this.isNew = false});

  final Entry entry;
  final bool isNew;

  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  late final JournalStore _store;
  late final Entry _original;
  final _picker = ImagePicker();
  late final _geocoding = Geocoding(); // lazy: tests have no platform plugin

  // Local wall-clock fields; converted to time + offset only when the user edits them.
  late DateTime _wall;
  bool _timeChanged = false;

  double? _lat;
  double? _lon;
  late final TextEditingController _text;
  late final TextEditingController _place;
  final _tagInput = TextEditingController();
  final _tagFocus = FocusNode();
  final _tagFieldKey = GlobalKey();
  late List<String> _tags;
  late List<String> _media;
  late bool _starred;

  final List<String> _imported = [];

  LatLng? _mapFallback;

  bool _locBusy = false;
  bool _mediaBusy = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _store = StoreScope.read(context);
    final e = _original = widget.entry;
    final w = e.wallTime;
    _wall = DateTime(w.year, w.month, w.day, w.hour, w.minute);
    _lat = e.lat;
    _lon = e.lon;
    _text = TextEditingController(text: e.text)..addListener(_changed);
    _place = TextEditingController(text: e.place ?? '')..addListener(_changed);
    _tagInput.addListener(_changed);
    _tags = [...e.tags];
    _media = [...e.media];
    _starred = e.starred;
    final lastLocated = _store.entries.where((x) => x.hasLocation).firstOrNull;
    if (lastLocated != null) {
      _mapFallback = LatLng(lastLocated.lat!, lastLocated.lon!);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _place.dispose();
    _tagInput.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _hasLocation => _lat != null && _lon != null;

  bool get _dirty {
    final o = _original;
    return _timeChanged ||
        _text.text != o.text ||
        _place.text.trim() != (o.place ?? '').trim() ||
        _lat != o.lat ||
        _lon != o.lon ||
        _starred != o.starred ||
        _tagInput.text.trim().isNotEmpty ||
        !listEquals(_tags, o.tags) ||
        !listEquals(_media, o.media);
  }

  Entry _compose() {
    final place = _place.text.trim();
    var e = _original.copyWith(
      text: _text.text,
      tags: List.of(_tags),
      media: List.of(_media),
      starred: _starred,
      lat: _lat,
      lon: _lon,
      place: place.isEmpty ? null : place,
    );
    if (_timeChanged) {
      final local = DateTime(
        _wall.year,
        _wall.month,
        _wall.day,
        _wall.hour,
        _wall.minute,
      );
      e = e.copyWith(
        time: local.toUtc(),
        utcOffsetMinutes: local.timeZoneOffset.inMinutes,
      );
    }
    return e;
  }

  Future<void> _save() async {
    if (_saving) return;
    _commitTagInput();
    final e = _compose();
    if (e.text.trim().isEmpty &&
        e.media.isEmpty &&
        !e.hasLocation &&
        e.tags.isEmpty) {
      showSnack(context, 'Write something or add a photo first');
      return;
    }
    setState(() => _saving = true);
    try {
      await _store.save(e);
      _deleteFiles(_imported.where((n) => !_media.contains(n)));
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Could not save: $err');
      }
    }
  }

  Future<void> _onBack() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes to this post.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true) {
      _deleteFiles(_imported.where((n) => !_original.media.contains(n)));
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _deleteFiles(Iterable<String> names) {
    for (final n in names.toList()) {
      try {
        final f = _store.mediaFile(_original, n);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _delete() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text(
          'The post and its photos and videos will be removed from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _store.delete(_original.id);
    } catch (e) {
      _snack('Could not delete: $e');
      return;
    }
    _deleteFiles(_imported.where((n) => !_original.media.contains(n)));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _wall,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      _wall = DateTime(d.year, d.month, d.day, _wall.hour, _wall.minute);
      _timeChanged = true;
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _wall.hour, minute: _wall.minute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    setState(() {
      _wall = DateTime(_wall.year, _wall.month, _wall.day, t.hour, t.minute);
      _timeChanged = true;
    });
  }

  void _setLocation(double lat, double lon) {
    setState(() {
      _lat = lat;
      _lon = lon;
    });
  }

  void _clearLocation() {
    setState(() {
      _lat = null;
      _lon = null;
      _place.clear();
    });
  }

  Future<void> _useCurrentLocation() async {
    if (_locBusy) return;
    setState(() => _locBusy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Location services are turned off');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _snack('Location permission was denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      ).timeout(const Duration(seconds: 25));
      if (!mounted) return;
      _setLocation(pos.latitude, pos.longitude);
      final label = await _reverseGeocode(pos.latitude, pos.longitude);
      if (mounted && label != null) _place.text = label;
    } catch (e) {
      _snack("Couldn't get your location: ${_short(e)}");
    } finally {
      if (mounted) setState(() => _locBusy = false);
    }
  }

  Future<void> _searchPlace() async {
    final query = await showDialog<String>(
      context: context,
      builder: (_) => const _SearchPlaceDialog(),
    );
    if (query == null || query.trim().isEmpty || !mounted) return;
    setState(() => _locBusy = true);
    try {
      final results = await _geocoding
          .locationFromAddress(query.trim())
          .timeout(const Duration(seconds: 15));
      if (results.isEmpty) {
        _snack('No place found for "${query.trim()}"');
        return;
      }
      if (!mounted) return;
      _setLocation(results.first.latitude, results.first.longitude);
      _place.text = query.trim();
    } catch (e) {
      _snack("Couldn't find that place (${_short(e)})");
    } finally {
      if (mounted) setState(() => _locBusy = false);
    }
  }

  Future<void> _onMapTap(LatLng p) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _setLocation(p.latitude, p.longitude);
    if (_place.text.trim().isNotEmpty) return;
    final label = await _reverseGeocode(p.latitude, p.longitude);
    if (mounted &&
        label != null &&
        _place.text.trim().isEmpty &&
        _lat == p.latitude &&
        _lon == p.longitude) {
      _place.text = label;
    }
  }

  /// Null when no geocoder is available.
  Future<String?> _reverseGeocode(double lat, double lon) async {
    try {
      final marks = await _geocoding
          .placemarkFromCoordinates(lat, lon)
          .timeout(const Duration(seconds: 8));
      if (marks.isEmpty) return null;
      final p = marks.first;
      final parts = <String>[];
      for (final s in [p.street, p.locality]) {
        final t = s?.trim() ?? '';
        if (t.isNotEmpty &&
            !parts.any((x) => x.toLowerCase().contains(t.toLowerCase()))) {
          parts.add(t);
        }
      }
      if (parts.isEmpty) {
        for (final s in [
          p.name,
          p.subLocality,
          p.administrativeArea,
          p.country,
        ]) {
          final t = s?.trim() ?? '';
          if (t.isNotEmpty) {
            parts.add(t);
            break;
          }
        }
      }
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null;
    }
  }

  static String? _normalizeTag(String raw) {
    var t = raw
        .trim()
        .replaceAll(RegExp(r'^#+'), '')
        .replaceAll(RegExp(r'\s+'), '-');
    t = t.replaceAll(RegExp(r'[,\[\]{}"]'), '');
    return t.isEmpty ? null : t;
  }

  void _addTag(String raw) {
    final t = _normalizeTag(raw);
    if (t == null) return;
    if (_tags.any((x) => x.toLowerCase() == t.toLowerCase())) return;
    setState(() => _tags = [..._tags, t]);
  }

  void _commitTagInput() {
    final pending = _tagInput.text;
    if (pending.trim().isEmpty) return;
    _tagInput.clear();
    for (final part in pending.split(',')) {
      _addTag(part);
    }
  }

  /// Chips grow the form above the field; keep the field on screen.
  void _revealTagField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tagFieldKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 150),
          alignment: 0.5,
        );
      }
    });
  }

  void _onTagInputChanged(String v) {
    if (!v.contains(',')) return;
    _revealTagField();
    final parts = v.split(',');
    final rest = parts.removeLast();
    for (final p in parts) {
      _addTag(p);
    }
    _tagInput.value = TextEditingValue(
      text: rest,
      selection: TextSelection.collapsed(offset: rest.length),
    );
  }

  static const _maxSide = 2560.0;

  Future<void> _addPhoto() => _pickAndImport(() async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: 85,
    );
    return [?x];
  });

  Future<void> _addVideo() => _pickAndImport(() async {
    final x = await _picker.pickVideo(source: ImageSource.camera);
    return [?x];
  });

  Future<void> _addFromGallery() => _pickAndImport(
    () => _picker.pickMultipleMedia(
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: 85,
    ),
  );

  Future<void> _pickAndImport(Future<List<XFile>> Function() pick) async {
    if (_mediaBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _mediaBusy = true);
    try {
      final files = await pick();
      for (final f in files) {
        final name = await _store.importMedia(_original, File(f.path));
        _imported.add(name);
        if (mounted) setState(() => _media = [..._media, name]);
      }
    } catch (e) {
      _snack("Couldn't add media: ${_short(e)}");
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  void _openMedia(String name) {
    final file = _store.mediaFile(_original, name);
    if (isImage(name)) {
      final images = [
        for (final m in _media)
          if (isImage(m)) m,
      ];
      showPhotoViewer(context, [
        for (final m in images) _store.mediaFile(_original, m),
      ], initialIndex: images.indexOf(name));
    } else {
      _openVideo(file);
    }
  }

  Future<void> _openVideo(File file) async {
    if (!file.existsSync()) {
      _snack('This video file is missing');
      return;
    }
    try {
      final res = await OpenFilex.open(file.path);
      if (res.type != ResultType.done) {
        _snack(
          res.message.isEmpty ? 'No app can play this video' : res.message,
        );
      }
    } catch (e) {
      _snack('Could not open video: ${_short(e)}');
    }
  }

  void _snack(String message) {
    if (mounted) showSnack(context, message);
  }

  static String _short(Object e) {
    var s = e.toString();
    s = s.replaceFirst('Exception: ', '');
    return s.length > 90 ? '${s.substring(0, 90)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final placeText = _place.text.trim();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? 'New post' : 'Post'),
          actions: [
            IconButton(
              tooltip: _starred ? 'Remove star' : 'Star this post',
              icon: Icon(
                _starred ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _starred ? const Color(0xFFF2B01E) : null,
              ),
              onPressed: () => setState(() => _starred = !_starred),
            ),
            FilledButton(
              onPressed: _saving || !_dirty ? null : _save,
              child: const Text('Save'),
            ),
            if (widget.isNew)
              const SizedBox(width: 16)
            else
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'delete') _delete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, color: scheme.error),
                      title: const Text('Delete'),
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_original.conflict) ...[
                _conflictBanner(theme),
                const SizedBox(height: 16),
              ],
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    AuthorDot(author: _original.author, size: 12),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _original.author,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(DateFormat('EEE d MMM yyyy').format(_wall)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(DateFormat('HH:mm').format(_wall)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _text,
                minLines: 6,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'What happened?',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),

              _sectionTitle(theme, 'Location'),
              if (_hasLocation || placeText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.place, size: 20, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            if (placeText.isNotEmpty) placeText,
                            if (_hasLocation) '(${formatCoords(_lat!, _lon!)})',
                          ].join(' '),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: _place,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Place label',
                  hintText: 'e.g. Scheveningen beach',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 0,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.my_location, size: 18),
                    label: const Text('Current location'),
                    onPressed: _locBusy ? null : _useCurrentLocation,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.search, size: 18),
                    label: const Text('Search place'),
                    onPressed: _locBusy ? null : _searchPlace,
                  ),
                  if (_hasLocation || placeText.isNotEmpty)
                    ActionChip(
                      avatar: const Icon(Icons.location_off_outlined, size: 18),
                      label: const Text('Clear'),
                      onPressed: _clearLocation,
                    ),
                ],
              ),
              if (_locBusy)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 12),
              LocationMap(
                point: _hasLocation ? LatLng(_lat!, _lon!) : null,
                author: _original.author,
                fallbackCenter: _mapFallback,
                onTap: _onMapTap,
              ),
              const SizedBox(height: 20),

              _sectionTitle(theme, 'Tags'),
              if (_tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final t in _tags)
                        InputChip(
                          label: Text('#$t'),
                          onDeleted: () =>
                              setState(() => _tags = [..._tags]..remove(t)),
                        ),
                    ],
                  ),
                ),
              TextField(
                key: _tagFieldKey,
                controller: _tagInput,
                focusNode: _tagFocus,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Add a tag',
                  hintText: 'Type, then press enter or comma',
                  prefixIcon: Icon(Icons.sell_outlined),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _onTagInputChanged,
                onSubmitted: (_) {
                  _commitTagInput();
                  _tagFocus.requestFocus();
                  _revealTagField();
                },
              ),
              _tagSuggestions(),
              const SizedBox(height: 20),

              _sectionTitle(theme, 'Photos & videos'),
              Wrap(
                spacing: 8,
                runSpacing: 0,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Camera photo'),
                    onPressed: _mediaBusy ? null : _addPhoto,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.videocam_outlined, size: 18),
                    label: const Text('Camera video'),
                    onPressed: _mediaBusy ? null : _addVideo,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                    onPressed: _mediaBusy ? null : _addFromGallery,
                  ),
                ],
              ),
              if (_mediaBusy)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
              if (_media.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in _media)
                      SizedBox(
                        width: 104,
                        height: 104,
                        child: Stack(
                          children: [
                            MediaTile(
                              file: _store.mediaFile(_original, m),
                              name: m,
                              size: 104,
                              radius: 10,
                              onTap: () => _openMedia(m),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Material(
                                color: Colors.black54,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => setState(
                                    () => _media = [..._media]..remove(m),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
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
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _conflictBanner(ThemeData theme) {
    final fg = theme.colorScheme.onErrorContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Two edits of this post clashed after a sync. Both versions are '
              'kept in the text below. Tidy it up and save - saving clears '
              'this warning.',
              style: TextStyle(color: fg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _tagSuggestions() {
    final typed = _tagInput.text
        .trim()
        .replaceAll(RegExp(r'^#+'), '')
        .toLowerCase();
    final chosen = _tags.map((t) => t.toLowerCase()).toSet();
    final suggestions = _store.allTags
        .where((t) => !chosen.contains(t.toLowerCase()))
        .where((t) => typed.isEmpty || t.toLowerCase().contains(typed))
        .take(10)
        .toList();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 0,
        children: [
          for (final t in suggestions)
            ActionChip(
              label: Text('#$t'),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                _tagInput.clear();
                _addTag(t);
              },
            ),
        ],
      ),
    );
  }
}

class _SearchPlaceDialog extends StatefulWidget {
  const _SearchPlaceDialog();

  @override
  State<_SearchPlaceDialog> createState() => _SearchPlaceDialogState();
}

class _SearchPlaceDialogState extends State<_SearchPlaceDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search place'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Address or place name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Search'),
        ),
      ],
    );
  }
}
