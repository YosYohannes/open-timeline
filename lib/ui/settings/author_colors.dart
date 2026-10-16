import 'package:flutter/material.dart';

import '../app/store_scope.dart';
import '../app/theme.dart';
import '../widgets/author.dart';

class MyColorPicker extends StatelessWidget {
  const MyColorPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final me = store.settings.me.trim();
    if (me.isEmpty) {
      return Text(
        'Set your email to choose a colour.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final current = authorColorOf(context, me).toARGB32();
    return Row(
      children: [
        for (final c in kAuthorPalette)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: kBorderRadius,
                onTap: () => store.setMyColor(c.toARGB32()),
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: kBorderRadius,
                    border: c.toARGB32() == current
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                  child: c.toARGB32() == current
                      ? const Icon(Icons.check, size: 18, color: Colors.black)
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
