import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';

/// Renders the keyboard shortcut reference page reachable from
/// `Settings → Keyboard`.
///
/// We deliberately use plain `ListTile` widgets so the page composes well
/// inside both the narrow mobile settings tree and the wide desktop
/// settings pane without any extra layout branching.
class KeyboardShortcutsPage extends StatelessWidget {
  const KeyboardShortcutsPage({super.key, this.onTrigger});

  /// Optional callback used by callers (typically tests) to wire a row's
  /// `onTap` to a real action. When `null`, row taps are no-ops except for
  /// the built-in copy-to-clipboard affordance.
  final void Function(KeyboardShortcutAction action)? onTrigger;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final groups = _groupedActions(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.keyboardShortcutsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                group.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: LedgerlyColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final action in group.actions)
              ListTile(
                key: Key('shortcut-row-${action.id}'),
                leading: Icon(action.icon, color: LedgerlyColors.brand),
                title: Text(action.label),
                subtitle: action.description == null
                    ? null
                    : Text(action.description!),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    for (final token in action.keys)
                      _KeyChip(label: token),
                  ],
                ),
                onTap: () => onTrigger?.call(action),
              ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<_ShortcutGroup> _groupedActions(BuildContext context) {
    final l10n = l10nOf(context);
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final newTx = isMac ? '⌘ N' : 'Ctrl N';
    final palette = isMac ? '⌘ K' : 'Ctrl K';
    final close = 'Esc';

    return [
      _ShortcutGroup(
        title: l10n.keyboardShortcutsGeneral,
        actions: [
          KeyboardShortcutAction(
            id: 'open-palette',
            icon: Icons.search,
            label: l10n.keyboardShortcutsOpenPalette,
            description: l10n.keyboardShortcutsOpenPaletteDescription,
            keys: [palette],
          ),
          KeyboardShortcutAction(
            id: 'close-dialog',
            icon: Icons.close,
            label: l10n.keyboardShortcutsCloseDialog,
            description: l10n.keyboardShortcutsCloseDialogDescription,
            keys: [close],
          ),
        ],
      ),
      _ShortcutGroup(
        title: l10n.keyboardShortcutsBookkeeping,
        actions: [
          KeyboardShortcutAction(
            id: 'new-transaction',
            icon: Icons.add_circle_outline,
            label: l10n.keyboardShortcutsNewTransaction,
            description: l10n.keyboardShortcutsNewTransactionDescription,
            keys: [newTx],
          ),
        ],
      ),
      _ShortcutGroup(
        title: l10n.keyboardShortcutsSync,
        actions: [
          KeyboardShortcutAction(
            id: 'sync-now',
            icon: Icons.sync,
            label: l10n.keyboardShortcutsTriggerSync,
            description: l10n.keyboardShortcutsTriggerSyncDescription,
            keys: [palette],
          ),
        ],
      ),
    ];
  }
}

class KeyboardShortcutAction {
  const KeyboardShortcutAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.keys,
    this.description,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? description;
  final List<String> keys;
}

class _ShortcutGroup {
  const _ShortcutGroup({required this.title, required this.actions});

  final String title;
  final List<KeyboardShortcutAction> actions;
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: LedgerlyColors.divider,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: LedgerlyColors.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}