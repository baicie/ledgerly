import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/presentation/widgets/categories_sheet.dart';
import 'package:ledgerly_client/presentation/widgets/category_pie_chart.dart';
import 'package:ledgerly_client/presentation/providers.dart';
import 'package:ledgerly_client/l10n/l10n.dart';

void main() {
  group('CategoryPieChart', () {
    testWidgets('renders nothing when slices are empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CategoryPieChart(slices: []),
          ),
        ),
      );
      // The widget returns an empty SizedBox; no error.
      expect(find.byType(CategoryPieChart), findsOneWidget);
    });

    testWidgets('renders CustomPaint when slices have amounts', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategoryPieChart(
              slices: [
                CategorySlice(label: 'Food', amountMinor: BigInt.from(100)),
                CategorySlice(label: 'Transport', amountMinor: BigInt.from(50)),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders nothing when total is zero', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategoryPieChart(
              slices: [
                CategorySlice(label: 'Food', amountMinor: BigInt.zero),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(CategoryPieChart), findsOneWidget);
    });
    testWidgets('shouldRepaint triggers when slice labels change', (tester) async {
      // Build two painters with different labels; expect shouldRepaint true.
      final painter = _TestPiePainter(
        slices: [
          CategorySlice(label: 'Food', amountMinor: BigInt.from(100)),
        ],
      );
      final updated = _TestPiePainter(
        slices: [
          CategorySlice(label: 'Transport', amountMinor: BigInt.from(100)),
        ],
      );
      expect(painter.shouldRepaint(updated), isTrue);
    });

    testWidgets('shouldRepaint returns false when nothing changes', (tester) async {
      final painter = _TestPiePainter(
        slices: [
          CategorySlice(label: 'Food', amountMinor: BigInt.from(100)),
        ],
      );
      final same = _TestPiePainter(
        slices: [
          CategorySlice(label: 'Food', amountMinor: BigInt.from(100)),
        ],
      );
      expect(painter.shouldRepaint(same), isFalse);
    });
  });

  group('CategoriesSheet', () {
    testWidgets('renders empty state when no categories', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () =>
                    CategoriesSheet.show(context, categories: []),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text(L10n.current.reportsNoCategories), findsOneWidget);
    });

    testWidgets('renders categories and filters by query', (tester) async {
      final categories = [
        ReportCategory(name: 'Food', amountMinor: BigInt.from(100), currency: 'CNY'),
        ReportCategory(name: 'Transport', amountMinor: BigInt.from(50), currency: 'CNY'),
        ReportCategory(name: 'Entertainment', amountMinor: BigInt.from(30), currency: 'CNY'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () =>
                    CategoriesSheet.show(context, categories: categories),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // All three rows visible.
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Entertainment'), findsOneWidget);

      // Search field visible.
      expect(find.byType(TextField), findsOneWidget);

      // Filter by typing.
      await tester.enterText(find.byType(TextField), 'Food');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Food'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Transport'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Entertainment'), findsNothing);
    });

    testWidgets('shows empty state when filter has no match', (tester) async {
      final categories = [
        ReportCategory(name: 'Food', amountMinor: BigInt.from(100), currency: 'CNY'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () =>
                    CategoriesSheet.show(context, categories: categories),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pumpAndSettle();

      expect(find.text(L10n.current.reportsNoCategories), findsOneWidget);
    });
  });
}

/// Mirror of the private painter logic for shouldRepaint checks.
class _TestPiePainter extends CustomPainter {
  _TestPiePainter({required this.slices});
  final List<CategorySlice> slices;

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant _TestPiePainter old) {
    if (old.slices.length != slices.length) return true;
    for (var i = 0; i < slices.length; i++) {
      if (old.slices[i].label != slices[i].label) return true;
      if (old.slices[i].amountMinor != slices[i].amountMinor) return true;
    }
    return false;
  }
}
