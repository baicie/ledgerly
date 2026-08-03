import 'package:flutter/material.dart';

import 'quick_entry_sheet.dart';

Future<void> openQuickEntry(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const QuickEntrySheet(),
  );
}
