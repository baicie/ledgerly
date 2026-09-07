import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/feed_search.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/l10n/l10n.dart';

TransactionSummary _summary({String? source}) => TransactionSummary(
      id: 'tx-${source ?? "none"}',
      occurredAt: DateTime.utc(2024, 4, 1),
      description: null,
      entryCount: 2,
      kind: TransactionSummaryKind.expense,
      amountMinor: BigInt.from(100),
      source: source,
    );

void main() {
  // The filter only inspects the `source` field, so the l10n parameter
  // is irrelevant for these cases. We use a tiny stubbed instance whose
  // localization helpers return their input unchanged.
  final l10n = _L10nStub();

  group('FeedSourceFilter', () {
    test('fromTag returns all for unknown values', () {
      expect(FeedSourceFilter.fromTag(null), FeedSourceFilter.all);
      expect(FeedSourceFilter.fromTag('mystery'), FeedSourceFilter.all);
    });

    test('fromTag matches enum tag strings', () {
      expect(FeedSourceFilter.fromTag('all'), FeedSourceFilter.all);
      expect(FeedSourceFilter.fromTag('auto_ledger'), FeedSourceFilter.autoLedger);
      expect(FeedSourceFilter.fromTag('manual'), FeedSourceFilter.manual);
    });
  });

  group('matchesFeedSource', () {
    test('all accepts every transaction regardless of source', () {
      final tx = _summary(source: 'auto_ledger');
      expect(matchesFeedSource(tx, FeedSourceFilter.all), isTrue);
    });

    test('autoLedger only accepts auto_ledger-tagged rows', () {
      expect(
        matchesFeedSource(_summary(source: 'auto_ledger'), FeedSourceFilter.autoLedger),
        isTrue,
      );
      expect(
        matchesFeedSource(_summary(), FeedSourceFilter.autoLedger),
        isFalse,
      );
      expect(
        matchesFeedSource(_summary(source: 'manual'), FeedSourceFilter.autoLedger),
        isFalse,
      );
    });

    test('manual accepts rows without a source tag and explicit manual tags', () {
      expect(
        matchesFeedSource(_summary(), FeedSourceFilter.manual),
        isTrue,
      );
      expect(
        matchesFeedSource(_summary(source: 'manual'), FeedSourceFilter.manual),
        isTrue,
      );
      expect(
        matchesFeedSource(_summary(source: 'auto_ledger'), FeedSourceFilter.manual),
        isFalse,
      );
    });
  });

  group('filterFeedTransactions', () {
    final all = [
      _summary(source: 'auto_ledger'),
      _summary(source: 'manual'),
      _summary(),
    ];

    test('default behaviour matches every transaction (all filter)', () {
      final result = filterFeedTransactions(all, '', l10n);
      expect(result, hasLength(3));
    });

    test('sourceFilter restricts the result set', () {
      final autoOnly = filterFeedTransactions(
        all,
        '',
        l10n,
        sourceFilter: FeedSourceFilter.autoLedger,
      );
      expect(autoOnly, hasLength(1));
      expect(autoOnly.single.source, 'auto_ledger');

      final manualOnly = filterFeedTransactions(
        all,
        '',
        l10n,
        sourceFilter: FeedSourceFilter.manual,
      );
      expect(manualOnly, hasLength(2));
      expect(manualOnly.every((tx) => tx.source != 'auto_ledger'), isTrue);
    });

    test('combines with text query', () {
      final result = filterFeedTransactions(
        all,
        'auto',
        l10n,
        sourceFilter: FeedSourceFilter.manual,
      );
      // None of the manual rows mention "auto" in description/category.
      expect(result, isEmpty);
    });
  });
}

class _L10nStub implements AppLocalizations {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final memberName = invocation.memberName;
    if (memberName == #searchTransactionsHint ||
        memberName == #noSearchResults ||
        memberName == #noSearchResultsMessage) {
      return '';
    }
    // Default fallback: stringify positional args if any, else empty string.
    final args = invocation.positionalArguments;
    return args.isEmpty ? '' : args.first.toString();
  }
}
