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
import '../../models/entry_format.dart';
import '../../models/tag.dart';
import '../../store/journal_store.dart';
import '../../sync/merge.dart';
import '../app/store_scope.dart';
import '../app/theme.dart';
import '../stamp/stamp_scan.dart';
import '../widgets/action_row.dart';
import '../widgets/author.dart';
import '../widgets/format.dart';
import '../widgets/media_tile.dart';
import '../widgets/snack.dart';
import 'location_map.dart';
import 'photo_viewer.dart';
import 'video_prep.dart';

class PostPage extends StatefulWidget {
  const PostPage({
    super.key,
    required this.entry,
    this.isNew = false,
    this.scanner,
  });

  final Entry entry;
  final bool isNew;
  final StampScanner? scanner;

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
  late final TextEditingController _title;
  late final TextEditingController _text;
  late final TextEditingController _place;
  late final TextEditingController _series;
  late final TextEditingController _country;
  final _tagInput = TextEditingController();
  final _tagFocus = FocusNode();
  final _tagFieldKey = GlobalKey();
  late List<String> _tags;
  late List<String> _media;

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
    _title = TextEditingController(text: e.title)..addListener(_changed);
    _text = TextEditingController(text: e.text)..addListener(_changed);
    _place = TextEditingController(text: e.place ?? '')..addListener(_changed);
    _series = TextEditingController(text: e.series)..addListener(_changed);
    _country = TextEditingController(text: e.country ?? '')
      ..addListener(_changed);
    _tagInput.addListener(_changed);
    _tags = [...e.tags];
    _media = [...e.media];
    if (widget.isNew && _isStamp) _imported.addAll(e.media);
    final lastLocated = _store.entries.where((x) => x.hasLocation).firstOrNull;
    if (lastLocated != null) {
      _mapFallback = LatLng(lastLocated.lat!, lastLocated.lon!);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _place.dispose();
    _series.dispose();
    _country.dispose();
    _title.dispose();
    _tagInput.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _hasLocation => _lat != null && _lon != null;

  bool get _isStamp => _original.isStamp;

  bool get _dirty {
    final o = _original;
    return _timeChanged ||
        _text.text != o.text ||
        _title.text.trim() != o.title.trim() ||
        _place.text.trim() != (o.place ?? '').trim() ||
        _series.text.trim() != o.series ||
        _countryCode != o.country ||
        _lat != o.lat ||
        _lon != o.lon ||
        _tagInput.text.trim().isNotEmpty ||
        !listEquals(_tags, o.tags) ||
        !listEquals(_media, o.media);
  }

  String? get _countryCode {
    final c = _country.text.trim().toUpperCase();
    return c.isEmpty ? null : c;
  }

  bool get _isMine =>
      _original.author.toLowerCase() == _store.settings.me.trim().toLowerCase();

  Entry _compose() {
    final place = _place.text.trim();
    var e = _original.copyWith(
      title: _title.text.trim(),
      text: _text.text,
      tags: List.of(_tags),
      media: List.of(_media),
      lat: _lat,
      lon: _lon,
      place: place.isEmpty ? null : place,
      series: _series.text.trim(),
      country: _countryCode,
      color: _isMine ? _store.settings.myColor : null,
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
      final current = widget.isNew ? null : _store.anyById(_original.id);
      final raced =
          current != null &&
          entryToMarkdown(current) != entryToMarkdown(_original);
      if (raced) {
        final merged = mergeEntry(
          base: _original,
          local: e,
          remote: current,
          localUser: _store.settings.me,
        );
        await _store.writeSynced(merged, dirty: true);
      } else {
        await _store.save(e);
      }
      _deleteFiles(_imported.where((n) => !_media.contains(n)));
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (raced) {
        showSnack(context, 'Merged with changes synced while you were editing');
      }
      navigator.pop();
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
      _deleteFiles(
        _imported.where((n) => widget.isNew || !_original.media.contains(n)),
      );
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
        title: Text(_isStamp ? 'Delete this stamp?' : 'Delete this post?'),
        content: Text(
          _isStamp
              ? 'The stamp and its image will be removed from this phone.'
              : 'The post and its photos and videos will be removed from this phone.',
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
    if (_isStamp) _fillCountry(lat, lon);
  }

  Future<void> _fillCountry(double lat, double lon) async {
    if (_country.text.trim().isNotEmpty) return;
    try {
      final marks = await _geocoding
          .placemarkFromCoordinates(lat, lon)
          .timeout(const Duration(seconds: 8));
      final code = marks.firstOrNull?.isoCountryCode;
      if (mounted && code != null && _country.text.trim().isEmpty) {
        _country.text = code;
      }
    } catch (_) {}
  }

  Future<void> _rescan() async {
    if (_mediaBusy) return;
    setState(() => _mediaBusy = true);
    try {
      final file = await scanWithMessage(
        context,
        widget.scanner ?? PlatformStampScanner(),
      );
      if (file == null) return;
      try {
        final name = await _store.importMedia(_original, file);
        final old = _media.toList();
        _imported.add(name);
        if (mounted) setState(() => _media = [name]);
        _deleteFiles(old.where(_imported.contains));
      } finally {
        try {
          await file.delete();
        } catch (_) {}
      }
    } catch (e) {
      _snack("Couldn't scan: ${_short(e)}");
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
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

  void _addTag(String raw) {
    final t = normalizeTag(raw);
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
        var source = File(f.path);
        var isTemp = false;
        if (isVideo(f.path)) {
          if (!mounted) return;
          final prepared = await prepareVideo(context, source);
          if (prepared == null) continue;
          source = prepared.file;
          isTemp = prepared.isTemp;
        }
        try {
          final name = await _store.importMedia(_original, source);
          _imported.add(name);
          if (mounted) setState(() => _media = [..._media, name]);
        } finally {
          if (isTemp) await source.delete();
        }
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
          title: Text(
            _isStamp
                ? (widget.isNew ? 'New stamp' : 'Stamp')
                : (widget.isNew ? 'New post' : 'Post'),
          ),
          actions: [
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
              if (_isStamp) ...[
                _stampPreview(theme),
                const SizedBox(height: 16),
              ],
              ActionRow(
                items: [
                  ActionItem(
                    icon: Icons.calendar_today_outlined,
                    label: DateFormat('EEE d MMM yyyy').format(_wall),
                    flex: 3,
                    onPressed: _pickDate,
                  ),
                  ActionItem(
                    icon: Icons.schedule,
                    label: DateFormat('HH:mm').format(_wall),
                    flex: 2,
                    onPressed: _pickTime,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: _isStamp ? 'Stamp name' : 'Title (optional)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              if (_isStamp) ...[
                TextField(
                  controller: _series,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Series',
                    hintText: 'e.g. JR West eki stamps',
                    prefixIcon: Icon(Icons.collections_bookmark_outlined),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                _seriesSuggestions(),
                const SizedBox(height: 12),
                TextField(
                  controller: _country,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 2,
                  decoration: const InputDecoration(
                    labelText: 'Country code',
                    hintText: 'JP, TW … filled in from the location',
                    prefixIcon: Icon(Icons.public),
                    border: OutlineInputBorder(),
                    isDense: true,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
              ],

              TextField(
                controller: _text,
                minLines: _isStamp ? 3 : 6,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _isStamp ? 'Notes (optional)' : 'What happened?',
                  border: const OutlineInputBorder(),
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
              ActionRow(
                items: [
                  ActionItem(
                    icon: Icons.my_location,
                    label: 'Current',
                    onPressed: _locBusy ? null : _useCurrentLocation,
                  ),
                  ActionItem(
                    icon: Icons.search,
                    label: 'Search',
                    onPressed: _locBusy ? null : _searchPlace,
                  ),
                  if (_hasLocation || placeText.isNotEmpty)
                    ActionItem(
                      icon: Icons.location_off_outlined,
                      label: 'Clear',
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

              if (!_isStamp) ...[
                _sectionTitle(theme, 'Photos & videos'),
                ActionRow(
                  items: [
                    ActionItem(
                      icon: Icons.photo_camera_outlined,
                      label: 'Photo',
                      onPressed: _mediaBusy ? null : _addPhoto,
                    ),
                    ActionItem(
                      icon: Icons.videocam_outlined,
                      label: 'Video',
                      onPressed: _mediaBusy ? null : _addVideo,
                    ),
                    ActionItem(
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
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
                                radius: kRadius,
                                onTap: () => _openMedia(m),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Material(
                                  color: Colors.black54,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: kBorderRadius,
                                  ),
                                  child: InkWell(
                                    customBorder: RoundedRectangleBorder(
                                      borderRadius: kBorderRadius,
                                    ),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _stampPreview(ThemeData theme) {
    final name = _media.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: kBorderRadius,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: name == null
              ? null
              : InkWell(
                  onTap: () => _openMedia(name),
                  child: Image.file(
                    _store.mediaFile(_original, name),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        ActionRow(
          items: [
            ActionItem(
              icon: Icons.document_scanner_outlined,
              label: 'Scan again',
              onPressed: _mediaBusy ? null : _rescan,
            ),
          ],
        ),
        if (_mediaBusy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _seriesSuggestions() {
    final typed = _series.text.trim().toLowerCase();
    final suggestions = _store.allSeries
        .where((t) => t.toLowerCase() != typed)
        .where((t) => typed.isEmpty || t.toLowerCase().contains(typed))
        .take(10)
        .toList();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final t in suggestions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(t),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _series.text = t,
                ),
              ),
          ],
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
        borderRadius: kBorderRadius,
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
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final t in suggestions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text('#$t'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _tagInput.clear();
                    _addTag(t);
                  },
                ),
              ),
          ],
        ),
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
