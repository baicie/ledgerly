import 'package:flutter/material.dart';

import '../../application/reports_range.dart';
import '../../l10n/l10n.dart';

/// Modal sheet that lets the user pick a [ReportsRange]. Used by the
/// Reports page AppBar.
class RangePickerSheet extends StatefulWidget {
  const RangePickerSheet({super.key, required this.current});

  final ReportsRange current;

  static Future<ReportsRange?> show(
    BuildContext context, {
    required ReportsRange current,
  }) {
    return showModalBottomSheet<ReportsRange>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => RangePickerSheet(current: current),
    );
  }

  @override
  State<RangePickerSheet> createState() => _RangePickerSheetState();
}

class _RangePickerSheetState extends State<RangePickerSheet> {
  late ReportsRange _draft;
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _draft = widget.current;
    _customStart = widget.current.customStart;
    _customEnd = widget.current.customEnd;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.current;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.reportsRangeTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              // Quick preset chips
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _PresetChip(
                    label: l10n.reportsRangeMonth,
                    selected: _draft.kind == ReportsRangeKind.month,
                    onTap: () => setState(() => _draft = ReportsRange.month()),
                  ),
                  _PresetChip(
                    label: l10n.reportsRangeLast7,
                    selected: _draft.kind == ReportsRangeKind.last7Days,
                    onTap: () => setState(
                        () => _draft = ReportsRange.lastNDays(7)),
                  ),
                  _PresetChip(
                    label: l10n.reportsRangeLast30,
                    selected: _draft.kind == ReportsRangeKind.last30Days,
                    onTap: () => setState(
                        () => _draft = ReportsRange.lastNDays(30)),
                  ),
                  _PresetChip(
                    label: l10n.reportsRangeLast3,
                    selected: _draft.kind == ReportsRangeKind.last3Months,
                    onTap: () =>
                        setState(() => _draft = ReportsRange.last3Months()),
                  ),
                  _PresetChip(
                    label: l10n.reportsRangeLast90,
                    selected: _draft.kind == ReportsRangeKind.last90Days,
                    onTap: () => setState(
                        () => _draft = ReportsRange.lastNDays(90)),
                  ),
                  _PresetChip(
                    label: l10n.reportsRangeLast6,
                    selected: _draft.kind == ReportsRangeKind.last6Months,
                    onTap: () =>
                        setState(() => _draft = ReportsRange.last6Months()),
                  ),
                  _PresetChip(
                    label: l10n.reportsRangeYear,
                    selected: _draft.kind == ReportsRangeKind.year,
                    onTap: () => setState(() => _draft = ReportsRange.year()),
                  ),
                  _PresetChip(
                    label: l10n.reportsRangeCustom,
                    selected: _draft.kind == ReportsRangeKind.custom,
                    onTap: _pickCustom,
                  ),
                ],
              ),
              if (_draft.kind == ReportsRangeKind.custom) ...[
                const SizedBox(height: 12),
                _CustomRangeRow(
                  start: _customStart,
                  end: _customEnd,
                  onPickStart: () => _pickDate(true),
                  onPickEnd: () => _pickDate(false),
                ),
              ],
              const SizedBox(height: 16),
              // Range preview
              _RangePreview(range: _draft),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _draft.kind == ReportsRangeKind.custom &&
                              (_customStart == null || _customEnd == null)
                          ? null
                          : () => Navigator.of(context).pop(_draft),
                      child: Text(l10n.commonConfirm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCustom() async {
    final initial = _customStart ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _customStart ??= picked;
      _customEnd ??= picked;
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = (isStart ? _customStart : _customEnd) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _customStart = picked;
      } else {
        _customEnd = picked;
      }
      _draft = ReportsRange.custom(_customStart!, _customEnd!);
    });
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _RangePreview extends StatelessWidget {
  const _RangePreview({required this.range});
  final ReportsRange range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_note,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              range.describe(),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomRangeRow extends StatelessWidget {
  const _CustomRangeRow({
    required this.start,
    required this.end,
    required this.onPickStart,
    required this.onPickEnd,
  });
  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.current;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onPickStart,
            child: Text('${l10n.reportsRangeStart}: ${_fmt(start)}'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: onPickEnd,
            child: Text('${l10n.reportsRangeEnd}: ${_fmt(end)}'),
          ),
        ),
      ],
    );
  }
}
