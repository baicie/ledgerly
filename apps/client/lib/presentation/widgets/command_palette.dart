import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';

/// Single command palette entry.
///
/// The action is intentionally a `VoidCallback` rather than a future-returning
/// function so that the palette stays responsive even if the action does
/// heavy work — long-running operations should be kicked off and observed
/// elsewhere (e.g. through a `ref.read(...).syncNow()` call from the caller).
class CommandPaletteAction {
  const CommandPaletteAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onActivate,
    this.searchTerms = const <String>[],
    this.shortcut,
  });

  final String id;
  final String label;

  /// Icon shown on the leading edge of the result row.
  final IconData icon;

  /// Triggered when the row is activated by tap or `Enter`.
  final VoidCallback onActivate;

  /// Extra strings to match against the query in addition to [label].
  /// Use this for synonyms, alternate language forms, or route names.
  final List<String> searchTerms;

  /// Optional key binding displayed on the trailing edge, e.g. `⌘N`.
  final String? shortcut;
}

/// Opens the command palette as a modal dialog and returns once it closes.
///
/// The dialog adapts to layout width via [Dialog] so it works on both narrow
/// and wide screens. Callers provide the list of [actions] to surface.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<CommandPaletteAction> actions,
}) {
  final l10n = l10nOf(context);
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 32,
        ),
        backgroundColor: LedgerlyColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: _CommandPaletteDialog(
            actions: actions,
            title: l10n.commandPaletteTitle,
            hint: l10n.commandPaletteHint,
            emptyLabel: l10n.commandPaletteNoResults,
            statusLabel: l10n.commandPaletteStatus,
          ),
        ),
      );
    },
  );
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({
    required this.actions,
    required this.title,
    required this.hint,
    required this.emptyLabel,
    required this.statusLabel,
  });

  final List<CommandPaletteAction> actions;
  final String title;
  final String hint;
  final String emptyLabel;
  final String statusLabel;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _listScroll = ScrollController();
  int _highlighted = 0;

  @override
  void initState() {
    super.initState();
    // Drop keyboard focus into the search field on first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  List<CommandPaletteAction> get _filtered {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return widget.actions;
    return widget.actions.where((action) {
      if (action.label.toLowerCase().contains(query)) return true;
      for (final term in action.searchTerms) {
        if (term.toLowerCase().contains(query)) return true;
      }
      return false;
    }).toList();
  }

  void _moveHighlight(int delta) {
    final filtered = _filtered;
    if (filtered.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta) % filtered.length;
      if (_highlighted < 0) _highlighted += filtered.length;
    });
    _scrollHighlightIntoView();
  }

  void _scrollHighlightIntoView() {
    if (!_listScroll.hasClients) return;
    const itemHeight = 56.0;
    final target = (_highlighted * itemHeight).clamp(
      0.0,
      _listScroll.position.maxScrollExtent,
    );
    _listScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _activate(CommandPaletteAction action) {
    Navigator.of(context).pop();
    action.onActivate();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    if (_highlighted >= filtered.length) {
      _highlighted = 0;
    }
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveHighlight(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveHighlight(-1),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (filtered.isNotEmpty) _activate(filtered[_highlighted]);
        },
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.search, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('command-palette-input'),
                    controller: _controller,
                    focusNode: _inputFocus,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: theme.textTheme.titleMedium,
                    onChanged: (_) {
                      setState(() => _highlighted = 0);
                    },
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Text(
                      widget.emptyLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: LedgerlyColors.muted,
                      ),
                    ),
                  )
                : ListView.builder(
                    key: const Key('command-palette-results'),
                    controller: _listScroll,
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final action = filtered[index];
                      final selected = index == _highlighted;
                      return _CommandPaletteRow(
                        key: Key('command-palette-row-${action.id}'),
                        action: action,
                        selected: selected,
                        onTap: () => _activate(action),
                        onHover: () => setState(() => _highlighted = index),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.statusLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: LedgerlyColors.muted,
                    ),
                  ),
                ),
                const _KeyHint(label: 'Esc'),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: LedgerlyColors.muted,
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

class _CommandPaletteRow extends StatelessWidget {
  const _CommandPaletteRow({
    super.key,
    required this.action,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final CommandPaletteAction action;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? LedgerlyColors.brand.withValues(alpha: 0.12)
        : Colors.transparent;
    return InkWell(
      onTap: onTap,
      onHover: (_) => onHover(),
      child: Container(
        key: Key('command-palette-tile-${action.id}'),
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(action.icon, size: 20, color: LedgerlyColors.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                action.label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (action.shortcut != null) ...[
              const SizedBox(width: 8),
              _KeyHint(label: action.shortcut!),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: LedgerlyColors.divider,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: LedgerlyColors.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}