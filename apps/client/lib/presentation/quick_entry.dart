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
    builder: (context) {
      final height = MediaQuery.sizeOf(context).height;
      return FractionallySizedBox(
        heightFactor: height < 600
            ? 1
            : height < 720
                ? 0.94
                : 0.76,
        child: const QuickEntrySheet(),
      );
    },
  );
}
