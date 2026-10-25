import 'dart:async';
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
import '../../models/countries.dart';
import '../../models/entry_format.dart';
import '../../models/tag.dart';
import '../../store/journal_store.dart';
import '../../sync/merge.dart';
import '../app/store_scope.dart';
import '../app/theme.dart';
import '../booklet/stamp_cutout.dart';
import '../booklet/stamp_image.dart';
import '../booklet/subject_segmenter.dart';
import '../stamp/country_picker.dart';
import '../stamp/stamp_scan.dart';
import '../widgets/action_row.dart';
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
    this.photos,
  });

  final Entry entry;
  final bool isNew;
  final StampPhotos? photos;

  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> with WidgetsBindingObserver {
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
  final _tagInput = TextEditingController();
  final _tagFocus = FocusNode();
  final _seriesFocus = FocusNode();
  final _seriesKey = GlobalKey();
  final _seriesLink = LayerLink();
  OverlayEntry? _seriesEntry;
  Timer? _revealTimer;
  final _tagFieldKey = GlobalKey();
  final _tagsKey = GlobalKey();
  late List<String> _tags;
  late List<String> _media;
  final _rev = ValueNotifier<int>(0);
  String? _countryCode;
  late String _size;
  late bool _blend;
  Future<Cutout?>? _preview;
  String _previewKey = '';

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
    _countryCode = e.country;
    _size = e.size;
    _blend = e.blend;
    _tagInput.addListener(_changed);
    _tagFocus.addListener(() {
      _changed();
      if (_tagFocus.hasFocus) _revealFocused();
    });
    WidgetsBinding.instance.addObserver(this);
    _series.addListener(_syncSeriesList);
    _seriesFocus.addListener(() {
      _changed();
      _syncSeriesList();
      if (_seriesFocus.hasFocus) _revealFocused();
    });
    _tags = [
      for (final t in e.tags)
        if (!_isEvent(t, e)) t,
    ];
    _media = [...e.media];
    if (widget.isNew && _isStamp) _imported.addAll(e.media);
    final lastLocated = _store.entries.where((x) => x.hasLocation).firstOrNull;
    if (lastLocated != null) {
      _mapFallback = LatLng(lastLocated.lat!, lastLocated.lon!);
    }
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rev.value++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _seriesEntry?.remove();
    _seriesEntry?.dispose();
    _rev.dispose();
    _text.dispose();
    _place.dispose();
    _series.dispose();
    _title.dispose();
    _tagInput.dispose();
    _tagFocus.dispose();
    _revealTimer?.cancel();
    _seriesFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _hasLocation => _lat != null && _lon != null;

  bool get _isStamp => _original.isStamp;

  bool _isEvent(String tag, Entry e) =>
      e.isStamp &&
      e.series.isNotEmpty &&
      tag.toLowerCase() == e.series.toLowerCase();

  String get _event => _isStamp ? _series.text.trim() : '';

  /// A stamp's event is also one of its tags, so posts can use it too.
  List<String> get _allTags => [
    if (_event.isNotEmpty) _event,
    for (final t in _tags)
      if (t.toLowerCase() != _event.toLowerCase()) t,
  ];

  bool get _dirty {
    final o = _original;
    return _timeChanged ||
        _text.text != o.text ||
        _title.text.trim() != o.title.trim() ||
        _place.text.trim() != (o.place ?? '').trim() ||
        _series.text.trim() != o.series ||
        _countryCode != o.country ||
        _size != o.size ||
        _blend != o.blend ||
        _lat != o.lat ||
        _lon != o.lon ||
        _tagInput.text.trim().isNotEmpty ||
        !listEquals(_tags, [
          for (final t in o.tags)
            if (!_isEvent(t, o)) t,
        ]) ||
        !listEquals(_media, o.media);
  }

  bool get _isMine =>
      _original.author.toLowerCase() == _store.settings.me.trim().toLowerCase();

  Entry _compose() {
    final place = _place.text.trim();
    var e = _original.copyWith(
      title: _title.text.trim(),
      text: _text.text,
      tags: _allTags,
      media: List.of(_media),
      lat: _lat,
      lon: _lon,
      place: place.isEmpty ? null : place,
      series: _series.text.trim(),
      country: _countryCode,
      size: _size,
      blend: _blend,
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
      navigator.pop(true);
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
  }

  void _applyCountry(({String? label, String? iso})? found) {
    if (!mounted) return;
    final iso = found?.iso;
    if (isKnownCountry(iso)) {
      setState(() => _countryCode = iso);
    } else {
      _snack("Couldn't work out the country. Choose it from the list.");
    }
  }

  Future<void> _pickCountry() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showCountryPicker(
      context,
      selected: _countryCode,
      used: _store.usedCountries,
    );
    if (picked == null || !mounted) return;
    setState(() => _countryCode = picked.code);
  }

  Widget _countryBox() {
    final code = _countryCode;
    return InkWell(
      key: const ValueKey('country-box'),
      borderRadius: kBorderRadius,
      onTap: _pickCountry,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Country',
          border: OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          code == null ? 'Not set' : countryLabel(code),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _rescan() async {
    if (_mediaBusy) return;
    setState(() => _mediaBusy = true);
    try {
      final photo = await askForPhoto(
        context,
        widget.photos ?? PlatformStampPhotos(),
      );
      if (photo == null || !mounted) return;
      final File? crop;
      try {
        crop = await cropOneStamp(context, photo);
      } finally {
        try {
          await photo.delete();
        } catch (_) {}
      }
      if (crop == null) return;
      try {
        final name = await _store.importMedia(_original, crop);
        final old = _media.toList();
        _imported.add(name);
        if (mounted) {
          setState(() {
            _media = [name];
            _blend = true;
          });
        }
        _deleteFiles(old.where(_imported.contains));
      } finally {
        try {
          await crop.delete();
        } catch (_) {}
      }
    } catch (e) {
      _snack("Couldn't use that photo: ${_short(e)}");
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  void _clearLocation() {
    setState(() {
      _lat = null;
      _lon = null;
      _place.clear();
      _countryCode = null;
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
      final found = await _lookup(pos.latitude, pos.longitude);
      if (!mounted) return;
      final label = found?.label;
      if (label != null) _place.text = label;
      _applyCountry(found);
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
      final spot = results.first;
      _setLocation(spot.latitude, spot.longitude);
      _place.text = query.trim();
      _applyCountry(await _lookup(spot.latitude, spot.longitude));
    } catch (e) {
      _snack("Couldn't find that place (${_short(e)})");
    } finally {
      if (mounted) setState(() => _locBusy = false);
    }
  }

  Future<void> _onMapTap(LatLng p) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _setLocation(p.latitude, p.longitude);
    final found = await _lookup(p.latitude, p.longitude);
    if (!mounted || _lat != p.latitude || _lon != p.longitude) return;
    final label = found?.label;
    if (label != null && _place.text.trim().isEmpty) _place.text = label;
    _applyCountry(found);
  }

  /// Null when no geocoder is available.
  Future<({String? label, String? iso})?> _lookup(
    double lat,
    double lon,
  ) async {
    try {
      final marks = await _geocoding
          .placemarkFromCoordinates(lat, lon)
          .timeout(const Duration(seconds: 8));
      if (marks.isEmpty) return null;
      final p = marks.first;
      return (label: _labelOf(p), iso: p.isoCountryCode?.toUpperCase());
    } catch (_) {
      return null;
    }
  }

  static String? _labelOf(Placemark p) {
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
  }

  void _addTag(String raw) {
    final t = normalizeTag(raw);
    if (t == null) return;
    if (t.toLowerCase() == _event.toLowerCase()) return;
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

  @override
  void didChangeMetrics() {
    if (_seriesFocus.hasFocus || _tagFocus.hasFocus) _revealFocused();
  }

  /// Waits for the keyboard to stop moving, then lifts the focused field with what it shows above it.
  void _revealFocused() {
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: 150), () {
      final series = _seriesFocus.hasFocus;
      final ctx = (series ? _seriesKey : _tagsKey).currentContext;
      if (mounted && ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          alignment: series ? 0.02 : 1,
        );
      }
    });
  }

  void _revealTagField() => _revealFocused();

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
              onPressed: _saving || !(_dirty || (widget.isNew && _isStamp))
                  ? null
                  : _save,
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
          keyboardDismissBehavior: _seriesFocus.hasFocus
              ? ScrollViewKeyboardDismissBehavior.manual
              : ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_original.conflict) ...[
                _conflictBanner(theme),
                const SizedBox(height: 16),
              ],
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
              if (_isStamp) ...[
                _eventField(),
              ] else ...[
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Title (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _text,
                  minLines: 5,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'What happened?',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                _mediaStrip(),
              ],
              const SizedBox(height: 12),
              _locationRow(theme),
              const SizedBox(height: 12),
              _tagsBlock(),
              if (_seriesFocus.hasFocus) const SizedBox(height: 200),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventField() {
    return CompositedTransformTarget(
      key: _seriesKey,
      link: _seriesLink,
      child: TextField(
        key: const ValueKey('series-field'),
        controller: _series,
        focusNode: _seriesFocus,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: 'Event',
          hintText: 'e.g. Kyoto trip',
          prefixIcon: const Icon(Icons.collections_bookmark_outlined),
          suffixIcon: _store.seriesUsage.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('series-dropdown'),
                  icon: Icon(
                    _seriesFocus.hasFocus
                        ? Icons.arrow_drop_up
                        : Icons.arrow_drop_down,
                  ),
                  tooltip: 'Recent events',
                  onPressed: () => _seriesFocus.hasFocus
                      ? _seriesFocus.unfocus()
                      : _seriesFocus.requestFocus(),
                ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _mediaStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in _media)
              SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  children: [
                    MediaTile(
                      file: _store.mediaFile(_original, m),
                      name: m,
                      size: 88,
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
                          onTap: () =>
                              setState(() => _media = [..._media]..remove(m)),
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
            SizedBox(
              width: 88,
              height: 88,
              child: OutlinedButton(
                key: const ValueKey('add-media'),
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: _mediaBusy ? null : _showAddMedia,
                child: const Icon(Icons.add_photo_alternate_outlined),
              ),
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

  void _showAddMedia() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _addPhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(ctx);
                _addVideo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _addFromGallery();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _locationRow(ThemeData theme) {
    final place = _place.text.trim();
    final code = _countryCode;
    final label = place.isNotEmpty
        ? place
        : (_hasLocation ? formatCoords(_lat!, _lon!) : '');
    final empty = label.isEmpty && code == null;
    return InkWell(
      key: const ValueKey('location-row'),
      borderRadius: kBorderRadius,
      onTap: _openLocationSheet,
      child: InputDecorator(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.place_outlined),
          suffixIcon: Icon(Icons.chevron_right),
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: empty
            ? Text('Add location', style: TextStyle(color: theme.hintColor))
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      label.isEmpty ? countryName(code!) : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (code != null && label.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('${countryFlag(code)} $code'),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _openLocationSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ListenableBuilder(
        listenable: Listenable.merge([_rev, _place]),
        builder: (ctx, _) => _locationSheet(ctx),
      ),
    );
  }

  Widget _locationSheet(BuildContext ctx) {
    final hasAny =
        _hasLocation || _place.text.trim().isNotEmpty || _countryCode != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _place,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Place label',
                      hintText: 'e.g. Scheveningen beach',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 4, child: _countryBox()),
              ],
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
                if (hasAny)
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
          ],
        ),
      ),
    );
  }

  Widget _tagsBlock() {
    return Column(
      key: _tagsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_event.isNotEmpty)
              Chip(
                key: const ValueKey('event-tag'),
                avatar: const Icon(Icons.collections_bookmark_outlined),
                label: Text('#$_event'),
              ),
            for (final t in _tags)
              InputChip(
                label: Text('#$t'),
                onDeleted: () => setState(() => _tags = [..._tags]..remove(t)),
              ),
            SizedBox(
              width: 150,
              child: Row(
                children: [
                  const Icon(Icons.sell_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: _tagFieldKey,
                      controller: _tagInput,
                      focusNode: _tagFocus,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: '+ tag',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: _onTagInputChanged,
                      onSubmitted: (_) {
                        _commitTagInput();
                        _tagFocus.requestFocus();
                        _revealTagField();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        _tagSuggestions(),
      ],
    );
  }

  Future<Cutout?> _previewCutout(File file) {
    if (file.path != _previewKey) {
      _previewKey = file.path;
      _preview = cutoutOf(file);
    }
    return _preview!;
  }

  Widget _stampPreview(ThemeData theme) {
    final name = _media.firstOrNull;
    final file = name == null ? null : _store.mediaFile(_original, name);
    Widget picture(File shown) => Image.file(
      shown,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: _blend ? kPaperColor : Colors.black,
            borderRadius: kBorderRadius,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: file == null
              ? null
              : InkWell(
                  onTap: () => _openMedia(name!),
                  child: _blend
                      ? FutureBuilder<Cutout?>(
                          future: _previewCutout(file),
                          builder: (context, snap) {
                            final cut = snap.data;
                            final done =
                                snap.connectionState == ConnectionState.done;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                picture(cut?.file ?? file),
                                if (!done)
                                  const Align(
                                    alignment: Alignment.bottomCenter,
                                    child: LinearProgressIndicator(),
                                  ),
                                if (done && cut == null)
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: double.infinity,
                                      color: Colors.black54,
                                      padding: const EdgeInsets.all(6),
                                      child: Text(
                                        "AI removal didn't work: ${subjectSegmenter.lastError ?? 'no item found'}",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        )
                      : picture(file),
                ),
        ),
        const SizedBox(height: 8),
        ActionRow(
          items: [
            ActionItem(
              icon: Icons.photo_camera_outlined,
              label: 'New photo',
              onPressed: _mediaBusy ? null : _rescan,
            ),
          ],
        ),
        if (_mediaBusy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('blend-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Remove background'),
          subtitle: const Text(
            'The phone cuts the stamp out of its picture so it sits on the page',
          ),
          value: _blend,
          onChanged: (v) => setState(() => _blend = v),
        ),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          key: const ValueKey('size-choice'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: sizeSmall, label: Text('Small')),
            ButtonSegment(value: sizeMedium, label: Text('Medium')),
            ButtonSegment(value: sizeLarge, label: Text('Large')),
          ],
          selected: {_size},
          onSelectionChanged: (v) => setState(() => _size = v.first),
        ),
      ],
    );
  }

  List<({String name, int count, DateTime last})> get _seriesOptions {
    final typed = _series.text.trim().toLowerCase();
    final usage = _store.seriesUsage;
    final exact = usage.any((s) => s.name.toLowerCase() == typed);
    return [
      for (final s in usage)
        if (typed.isEmpty || exact || s.name.toLowerCase().contains(typed)) s,
    ];
  }

  void _syncSeriesList() {
    if (!mounted) return;
    final show = _seriesFocus.hasFocus && _seriesOptions.isNotEmpty;
    if (!show) {
      _seriesEntry?.remove();
      _seriesEntry?.dispose();
      _seriesEntry = null;
    } else if (_seriesEntry == null) {
      _seriesEntry = OverlayEntry(builder: (_) => _seriesList());
      Overlay.of(context).insert(_seriesEntry!);
    } else {
      _seriesEntry!.markNeedsBuild();
    }
  }

  Widget _seriesList() {
    final options = _seriesOptions;
    final typed = _series.text.trim().toLowerCase();
    final width = MediaQuery.sizeOf(context).width - 32;
    final theme = Theme.of(context);
    return CompositedTransformFollower(
      link: _seriesLink,
      targetAnchor: Alignment.bottomLeft,
      offset: const Offset(0, 4),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: Material(
            key: const ValueKey('series-list'),
            elevation: 3,
            color: theme.colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: kBorderRadius,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 168),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final s in options)
                    ListTile(
                      key: ValueKey('series-${s.name}'),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        s.name.toLowerCase() == typed
                            ? Icons.check
                            : Icons.history,
                        size: 20,
                      ),
                      title: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        '${s.count} ${s.count == 1 ? 'item' : 'items'} · '
                        '${DateFormat('d MMM yyyy').format(s.last.toLocal())}',
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () {
                        _series.text = s.name;
                        _seriesFocus.unfocus();
                      },
                    ),
                ],
              ),
            ),
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

  Widget _tagSuggestions() {
    final typed = _tagInput.text
        .trim()
        .replaceAll(RegExp(r'^#+'), '')
        .toLowerCase();
    final chosen = _allTags.map((t) => t.toLowerCase()).toSet();
    final suggestions = [
      for (final t in _store.recentTags)
        if (!chosen.contains(t.toLowerCase()) &&
            (typed.isEmpty || t.toLowerCase().contains(typed)))
          t,
    ];
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        key: const ValueKey('tag-strip'),
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
