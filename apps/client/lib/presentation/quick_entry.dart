import 'package:flutter/material.dart';

import '../data/ledger_repository.dart';
import 'design/ledgerly_theme.dart';
import 'quick_entry_sheet.dart';
import 'utils/adaptive.dart';

/// Opens the Quick Entry editor in a layout-appropriate container.
///
/// - On **wide** layouts (>= [kWideBreakpoint] logical pixels, e.g. desktop /
///   web browser windows) the editor is presented as a centered
///   `Dialog`, capped at 560 logical pixels wide.
/// - On **narrow** layouts (mobile, small window resizes) the editor is
///   presented as a `showModalBottomSheet` that fills 76-100% of the viewport
///   height depending on available space.
Future<void> openQuickEntry(
  BuildContext context, {
  TransactionSummary? transaction,
}) {
  if (isWideLayout(context)) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: LedgerlyColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 560,
              maxHeight: 720,
            ),
            child: QuickEntrySheet(transaction: transaction),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 560),
    clipBehavior: Clip.antiAlias,
    builder: (context) {
      final height = MediaQuery.sizeOf(context).height;
      return FractionallySizedBox(
        heightFactor: height < 600
            ? 1
            : height < 720
                ? 0.94
                : 0.76,
        child: Material(
          color: LedgerlyColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: QuickEntrySheet(transaction: transaction),
          ),
        ),
      );
    },
  );
}