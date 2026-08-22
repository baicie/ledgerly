import '../data/ledger_repository.dart';

class ImportDraft {
  ImportDraft({
    required this.occurredAt,
    required this.kind,
    required this.amountMinor,
    required this.description,
    this.rawCategory,
    this.counterparty,
    this.selected = true,
    this.duplicate = false,
  });

  final DateTime occurredAt;
  final TransactionSummaryKind kind;
  final BigInt amountMinor;
  final String description;
  final String? rawCategory;
  final String? counterparty;
  bool selected;
  bool duplicate;
}

List<String> splitCsvLine(String line, {String delimiter = ','}) {
  final fields = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buffer.write(char);
      }
    } else if (char == '"') {
      inQuotes = true;
    } else if (char == delimiter) {
      fields.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  fields.add(buffer.toString().trim());
  return fields;
}

bool isSkippedImportStatus(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return false;
  const needles = [
    '退款',
    'refund',
    '关闭',
    'closed',
    '失败',
    'fail',
    '撤销',
    '已退还',
    '全额退款',
  ];
  return needles.any(value.contains);
}

DateTime? parseImportDate(String raw) {
  final value = raw.trim().replaceAll('/', '-');
  if (value.isEmpty) return null;
  final normalized = value.contains('T')
      ? value
      : value.replaceFirst(' ', 'T');
  final parsed = DateTime.tryParse(normalized);
  if (parsed != null) return parsed;
  final match = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?',
  ).firstMatch(value);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4) ?? '0'),
    int.parse(match.group(5) ?? '0'),
    int.parse(match.group(6) ?? '0'),
  );
}

BigInt? parseImportAmountMinor(String raw) {
  var value = raw.trim().replaceAll(',', '').replaceAll(' ', '');
  value = value.replaceAll('¥', '').replaceAll('￥', '').replaceAll('+', '');
  if (value.startsWith('(') && value.endsWith(')')) {
    value = '-${value.substring(1, value.length - 1)}';
  }
  if (value.isEmpty) return null;
  final negative = value.startsWith('-');
  if (negative) value = value.substring(1);
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final yuan = BigInt.parse(parts[0]);
  final cents = parts.length == 1
      ? BigInt.zero
      : BigInt.parse(parts[1].padRight(2, '0'));
  final amount = yuan * BigInt.from(100) + cents;
  if (amount == BigInt.zero) return null;
  return negative ? -amount : amount;
}

TransactionSummaryKind? parseImportKind(String? raw, BigInt amount) {
  final value = (raw ?? '').trim();
  if (value.contains('不计') ||
      value.contains('转账') ||
      value.contains('其他') ||
      value.toLowerCase() == 'transfer' ||
      value.toLowerCase() == 'other') {
    return null;
  }
  if (value.contains('收入') || value.toLowerCase() == 'income') {
    return TransactionSummaryKind.income;
  }
  if (value.contains('支出') || value.toLowerCase() == 'expense') {
    return TransactionSummaryKind.expense;
  }
  if (amount < BigInt.zero) return TransactionSummaryKind.expense;
  if (amount > BigInt.zero) return TransactionSummaryKind.income;
  return null;
}

String postedRowKey({
  required DateTime occurredAt,
  required BigInt amountMinor,
  required TransactionSummaryKind kind,
  required String description,
}) {
  final local = occurredAt.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day|${kind.name}|$amountMinor|${description.trim()}';
}

bool importDraftMatchesExisting(
  ImportDraft draft,
  TransactionSummary existing,
) {
  return postedRowKey(
        occurredAt: draft.occurredAt,
        amountMinor: draft.amountMinor,
        kind: draft.kind,
        description: draft.description,
      ) ==
      postedRowKey(
        occurredAt: existing.occurredAt,
        amountMinor: existing.amountMinor,
        kind: existing.kind,
        description: existing.description ?? '',
      );
}

void markDuplicateImportDrafts({
  required List<ImportDraft> drafts,
  required Iterable<TransactionSummary> existing,
}) {
  for (final draft in drafts) {
    final duplicate = existing.any(
      (row) => importDraftMatchesExisting(draft, row),
    );
    draft.duplicate = duplicate;
    if (duplicate) draft.selected = false;
  }
}

class CsvBillParser {
  const CsvBillParser();

  List<ImportDraft> parse(String csv) {
    final lines = csv
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];

    var headerIndex = 0;
    String delimiter = ',';
    Map<String, int>? header;
    for (var i = 0; i < lines.length; i++) {
      final detected = _detectHeader(lines[i]);
      if (detected != null) {
        headerIndex = i;
        delimiter = detected.$1;
        header = detected.$2;
        break;
      }
    }
    if (header == null) return const [];

    final drafts = <ImportDraft>[];
    for (final line in lines.skip(headerIndex + 1)) {
      final cols = splitCsvLine(line, delimiter: delimiter);
      if (cols.every((col) => col.isEmpty)) continue;
      String read(String key) {
        final index = header![key];
        if (index == null || index >= cols.length) return '';
        return cols[index];
      }

      if (isSkippedImportStatus(read('status'))) continue;
      final amount = parseImportAmountMinor(read('amount'));
      if (amount == null) continue;
      final kind = parseImportKind(read('direction'), amount.abs());
      if (kind == null) continue;
      final occurredAt = parseImportDate(read('date'));
      if (occurredAt == null) continue;
      final description = [
        read('description'),
        read('counterparty'),
        read('category'),
      ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
      drafts.add(
        ImportDraft(
          occurredAt: occurredAt,
          kind: kind,
          amountMinor: amount.abs(),
          description: description,
          rawCategory: read('category').isEmpty ? null : read('category'),
          counterparty:
              read('counterparty').isEmpty ? null : read('counterparty'),
        ),
      );
    }
    return drafts;
  }

  (String, Map<String, int>)? _detectHeader(String line) {
    for (final delimiter in const [',', '\t', ';']) {
      final map = _headerMap(splitCsvLine(line, delimiter: delimiter));
      if (map != null) return (delimiter, map);
    }
    return null;
  }

  Map<String, int>? _headerMap(List<String> cells) {
    final map = <String, int>{};
    for (var i = 0; i < cells.length; i++) {
      final name = cells[i].replaceAll('\uFEFF', '').trim();
      final key = _headerKey(name);
      if (key != null && !map.containsKey(key)) map[key] = i;
    }
    if (map.containsKey('date') && map.containsKey('amount')) return map;
    return null;
  }

  String? _headerKey(String name) {
    final value = name.toLowerCase();
    if (name.contains('交易时间') ||
        name.contains('交易日期') ||
        name.contains('交易创建时间') ||
        name.contains('付款时间') ||
        name == '日期' ||
        value == 'date' ||
        value == 'occurred_at') {
      return 'date';
    }
    if (name.contains('收/支') ||
        name.contains('收支') ||
        value == 'kind' ||
        value == 'direction' ||
        value == 'type') {
      return 'direction';
    }
    if (name.contains('金额') || value == 'amount') return 'amount';
    if (name.contains('商品说明') ||
        name.contains('商品名称') ||
        name.contains('商品') ||
        name.contains('备注') ||
        name.contains('说明') ||
        value == 'description' ||
        value == 'note') {
      return 'description';
    }
    if (name.contains('交易对方') ||
        value == 'counterparty' ||
        value == 'payee') {
      return 'counterparty';
    }
    if (name.contains('交易分类') ||
        name.contains('分类') ||
        value == 'category') {
      return 'category';
    }
    if (name.contains('交易状态') ||
        name.contains('当前状态') ||
        value == 'status') {
      return 'status';
    }
    return null;
  }
}

class ImportCategory {
  const ImportCategory({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String name;
  final String type;
}

String? matchImportCategoryId({
  required String kind,
  required String? rawCategory,
  required Iterable<ImportCategory> categories,
  required String Function(String name) localize,
}) {
  final ofKind = [
    for (final category in categories)
      if (category.type == kind) category,
  ];
  String? fallbackId;
  for (final category in ofKind) {
    fallbackId ??= category.id;
    if (category.name == 'Other Expense' ||
        category.name == '其他支出' ||
        category.name == 'Other Income' ||
        category.name == '其他收入') {
      fallbackId = category.id;
    }
  }
  final needle = (rawCategory ?? '').trim().toLowerCase();
  if (needle.isEmpty) return fallbackId;
  for (final category in ofKind) {
    final localized = localize(category.name).toLowerCase();
    if (category.name.toLowerCase() == needle || localized == needle) {
      return category.id;
    }
  }
  for (final category in ofKind) {
    final localized = localize(category.name).toLowerCase();
    if (localized.isNotEmpty &&
        (needle.contains(localized) || localized.contains(needle))) {
      return category.id;
    }
  }
  return fallbackId;
}
