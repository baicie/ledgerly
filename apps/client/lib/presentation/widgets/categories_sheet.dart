import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../providers.dart';

/// Modal sheet that lists every category in the current month summary.
/// Filters by [searchQuery] (case-insensitive). Tap a row to dismiss.
class CategoriesSheet extends StatefulWidget {
  const CategoriesSheet({super.key, required this.categories});

  final List<ReportCategory> categories;

  static Future<void> show(
    BuildContext context, {
    required List<ReportCategory> categories,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CategoriesSheet(categories: categories),
    );
  }

  @override
  State<CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends State<CategoriesSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lower = _query.trim().toLowerCase();
    final filtered = lower.isEmpty
        ? widget.categories
        : widget.categories
            .where((c) => c.name.toLowerCase().contains(lower))
            .toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  hintText: L10n.current.reportsSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (filtered.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    L10n.current.reportsNoCategories,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final category = filtered[index];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 8,
                        backgroundColor: _dotColor(category.name),
                      ),
                      title: Text(category.name),
                      trailing: Text(
                        '${formatMinor(category.amountMinor)} ${category.currency}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color _dotColor(String label) {
    final hash = label.codeUnits.fold<int>(0, (a, b) => (a + b) & 0xffffff);
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.55, 0.55).toColor();
  }
}
