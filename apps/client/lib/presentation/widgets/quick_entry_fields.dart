import 'package:flutter/material.dart';

import '../design/ledgerly_theme.dart';
import '../providers.dart';
import 'ledgerly_finance.dart';

class QuickEntrySelectionField extends StatelessWidget {
  const QuickEntrySelectionField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: LedgerlyIconBadge(icon: icon, color: color, size: 38),
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}

Future<String?> showQuickEntryPicker({
  required BuildContext context,
  required String title,
  required List<AccountBalanceRow> rows,
  required String? selectedId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _QuickEntryPicker(
      title: title,
      rows: rows,
      selectedId: selectedId,
    ),
  );
}

class _QuickEntryPicker extends StatelessWidget {
  const _QuickEntryPicker({
    required this.title,
    required this.rows,
    required this.selectedId,
  });

  final String title;
  final List<AccountBalanceRow> rows;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            itemCount: rows.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisExtent: 104,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final row = rows[index];
              final selected = row.id == selectedId;
              final color = ledgerColorFor(row.name);
              return Material(
                color: selected
                    ? LedgerlyColors.actionSurface
                    : LedgerlyColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: selected
                        ? LedgerlyColors.actionStrong
                        : LedgerlyColors.divider,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(context, row.id),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LedgerlyIconBadge(
                          icon: ledgerIconFor(row.name),
                          color: color,
                          size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          localizedLedgerName(row.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
