import 'package:flutter/widgets.dart';

import '../../store/journal_store.dart';

class StoreScope extends InheritedNotifier<JournalStore> {
  const StoreScope({
    super.key,
    required JournalStore store,
    required super.child,
  }) : super(notifier: store);

  /// Rebuilds the caller on store changes; use [read] to avoid that.
  static JournalStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, 'No StoreScope above this context');
    return scope!.notifier!;
  }

  static JournalStore read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, 'No StoreScope above this context');
    return scope!.notifier!;
  }
}
