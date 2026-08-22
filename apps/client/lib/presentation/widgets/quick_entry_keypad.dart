import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';

class QuickEntryKeypad extends StatelessWidget {
  const QuickEntryKeypad({
    super.key,
    this.compact = false,
    required this.onDigit,
    required this.onBackspace,
  });

  final bool compact;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', 'backspace'],
    ];
    return Container(
      height: compact ? 128 : 168,
      decoration: const BoxDecoration(
        color: LedgerlyColors.surface,
        border: Border(top: BorderSide(color: LedgerlyColors.divider)),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Expanded(
              child: Row(
                children: [
                  for (final value in row)
                    Expanded(
                      child: _KeyButton(
                        value: value,
                        onPressed: value == 'backspace'
                            ? onBackspace
                            : () => onDigit(value),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.value, required this.onPressed});

  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final backspace = value == 'backspace';
    final l10n = l10nOf(context);
    return Semantics(
      label: backspace
          ? l10n.backspace
          : value == '.'
              ? l10n.decimalPoint
              : value,
      button: true,
      child: InkWell(
        key: Key(backspace
            ? 'quick-key-backspace'
            : value == '.'
                ? 'quick-key-decimal'
                : 'quick-key-$value'),
        onTap: onPressed,
        child: Container(
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: LedgerlyColors.divider),
              bottom: BorderSide(color: LedgerlyColors.divider),
            ),
          ),
          child: backspace
              ? const Icon(Icons.backspace_outlined, size: 22)
              : Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
        ),
      ),
    );
  }
}
