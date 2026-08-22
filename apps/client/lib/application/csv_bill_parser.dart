import '../data/ledger_repository.dart';

class ImportDraft {
  ImportDraft({
    required this.occurredAt,
    required this.kind,
    required this.amountMinor,
    required this.description,
    this.rawCategory,
    this.selected = true,
  });

  final DateTime occurredAt;
  final TransactionSummaryKind kind;
  final BigInt amountMinor;
  final String description;
  final String? rawCategory;
  bool selected;
}

List<String> splitCsvLine(String line) {
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
    } else if (char == ',') {
      fields.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  fields.add(buffer.toString().trim());
  return fields;
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
      value.toLowerCase() == 'transfer') {
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
    for (var i = 0; i < lines.length; i++) {
      if (_headerMap(splitCsvLine(lines[i])) != null) {
        headerIndex = i;
        break;
      }
    }
    final header = _headerMap(splitCsvLine(lines[headerIndex]));
    if (header == null) return const [];

    final drafts = <ImportDraft>[];
    for (final line in lines.skip(headerIndex + 1)) {
      final cols = splitCsvLine(line);
      if (cols.every((col) => col.isEmpty)) continue;
      String read(String key) {
        final index = header[key];
        if (index == null || index >= cols.length) return '';
        return cols[index];
      }

      final amount = parseImportAmountMinor(read('amount'));
      if (amount == null) continue;
      final kind = parseImportKind(read('direction'), amount.abs());
      if (kind == null) continue;
      final occurredAt = parseImportDate(read('date'));
      if (occurredAt == null) continue;
      final description = read('description');
      drafts.add(
        ImportDraft(
          occurredAt: occurredAt,
          kind: kind,
          amountMinor: amount.abs(),
          description: description.isEmpty ? read('category') : description,
          rawCategory: read('category').isEmpty ? null : read('category'),
        ),
      );
    }
    return drafts;
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
        name.contains('商品') ||
        name.contains('备注') ||
        name.contains('说明') ||
        value == 'description' ||
        value == 'note') {
      return 'description';
    }
    if (name.contains('交易分类') ||
        name.contains('分类') ||
        value == 'category') {
      return 'category';
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
