import 'package:flutter/material.dart';

import 'quick_entry_sheet.dart';

Future<void> openQuickEntry(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 560),
    clipBehavior: Clip.antiAlias,
    builder: (context) => const FractionallySizedBox(
      heightFactor: 0.94,
      child: QuickEntrySheet(),
    ),
  );
}
