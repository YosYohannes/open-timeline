import 'package:flutter/material.dart';

import '../app/theme.dart';

class ActionItem {
  const ActionItem({
    required this.icon,
    required this.label,
    this.onPressed,
    this.active = false,
    this.flex = 1,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final int flex;
}

class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.items});

  final List<ActionItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: kBorderRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(
                flex: items[i].flex,
                child: _ActionButton(item: items[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.item});

  final ActionItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: item.onPressed,
      icon: Icon(item.icon, size: 18),
      label: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: item.active ? scheme.primary : scheme.onSurface,
        backgroundColor: item.active ? scheme.surfaceContainerHighest : null,
      ),
    );
  }
}
