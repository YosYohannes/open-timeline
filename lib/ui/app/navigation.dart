import 'package:flutter/material.dart';

import '../../models/entry.dart';
import '../post/post_page.dart';
import '../widgets/snack.dart';
import 'store_scope.dart';

void openEntry(BuildContext context, String id) {
  final entry = StoreScope.read(context).byId(id);
  if (entry == null) return;
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => PostPage(entry: entry)));
}

void newEntry(BuildContext context) {
  final store = StoreScope.read(context);
  final me = store.settings.me.trim();
  if (me.isEmpty) {
    showSnack(context, 'Set "Your email" in Settings first');
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PostPage(
        entry: Entry.create(author: me).copyWith(color: store.settings.myColor),
        isNew: true,
      ),
      fullscreenDialog: true,
    ),
  );
}
