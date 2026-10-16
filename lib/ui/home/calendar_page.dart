import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/entry.dart';
import '../app/store_scope.dart';
import '../app/theme.dart';
import '../widgets/author.dart';
import '../widgets/format.dart';
import 'filters.dart';
import 'timeline_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.filter});

  final EntryFilter filter;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = dayOf(DateTime.now());
    _month = DateTime(_selected.year, _selected.month);
  }

  void _shiftMonth(int delta) {
    final month = DateTime(_month.year, _month.month + delta);
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    setState(() {
      _month = month;
      _selected = DateTime(
        month.year,
        month.month,
        _selected.day > lastDay ? lastDay : _selected.day,
      );
    });
  }

  void _goTo(DateTime day) {
    setState(() {
      _selected = dayOf(day);
      _month = DateTime(day.year, day.month);
    });
  }

  Future<void> _jump() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) _goTo(picked);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final today = dayOf(DateTime.now());
    return ListenableBuilder(
      listenable: widget.filter,
      builder: (context, _) {
        final byDay = <DateTime, List<Entry>>{};
        for (final e in widget.filter.apply(store.entries)) {
          byDay.putIfAbsent(dayOf(e.wallTime), () => []).add(e);
        }
        final dayEntries = [...?byDay[_selected]]
          ..sort((a, b) => a.wallTime.compareTo(b.wallTime));

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _shiftMonth(-1),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: _jump,
                      child: Text(DateFormat('MMMM yyyy').format(_month)),
                    ),
                  ),
                  if (_selected != today)
                    IconButton(
                      tooltip: 'Today',
                      icon: const Icon(Icons.today),
                      onPressed: () => _goTo(today),
                    ),
                  IconButton(
                    tooltip: 'Next month',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _shiftMonth(1),
                  ),
                ],
              ),
            ),
            _WeekdayRow(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -200) _shiftMonth(1);
                if (v > 200) _shiftMonth(-1);
              },
              child: _MonthGrid(
                month: _month,
                selected: _selected,
                today: today,
                byDay: byDay,
                onSelect: (d) => setState(() => _selected = d),
              ),
            ),
            const SizedBox(height: 4),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: dayEntries.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        dayEntries.isEmpty
                            ? '${formatDayHeader(_selected)} · no posts'
                            : formatDayHeader(_selected),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  return EntryCard(entry: dayEntries[i - 1]);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(
                  l10n.narrowWeekdays[(l10n.firstDayOfWeekIndex + i) % 7],
                  style: style,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.byDay,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final Map<DateTime, List<Entry>> byDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final firstDow = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = (month.weekday % 7 - firstDow + 7) % 7;
    final rows = ((lead + daysInMonth) / 7).ceil();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _cell(r * 7 + c - lead + 1, daysInMonth)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int dayNumber, int daysInMonth) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 52);
    }
    final day = DateTime(month.year, month.month, dayNumber);
    final authors = {for (final e in byDay[day] ?? const <Entry>[]) e.author};
    return _DayCell(
      day: day,
      isSelected: day == selected,
      isToday: day == today,
      authors: authors.take(3).toList(),
      onTap: () => onSelect(day),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.authors,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final List<String> authors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: kBorderRadius,
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: kBorderRadius,
            color: isSelected ? scheme.surfaceContainerHighest : null,
            border: Border.all(
              color: isSelected
                  ? scheme.primary
                  : isToday
                  ? scheme.outline
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  color: isToday || isSelected ? scheme.primary : null,
                  fontWeight: isToday || isSelected ? FontWeight.w700 : null,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in authors)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: authorColorOf(context, a),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
