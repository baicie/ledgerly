import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/application/ledger_app_service.dart';
import 'package:ledgerly_client/data/database.dart';
import 'package:ledgerly_client/data/ledger_repository.dart';
import 'package:ledgerly_client/domain/ids.dart';
import 'package:ledgerly_client/presentation/design/ledgerly_theme.dart';
import 'package:ledgerly_client/presentation/pages/category_editor_page.dart';
import 'package:ledgerly_client/presentation/pages/categories_page.dart';
import 'package:ledgerly_client/presentation/providers.dart';

void main() {
  late AppDatabase database;
  late LedgerRepository repository;
  late LedgerAppService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LedgerRepository(
      database,
      deviceIdLoader: () async => 'category-page-device',
    );
    await repository.seedIfEmpty();
    service = LedgerAppService(repository);
  });

  tearDown(() => database.close());

  testWidgets('adds and edits an expense category on a narrow screen',
      (tester) async {
    await _pumpCategoryPage(tester, repository, service);

    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('交通'), findsOneWidget);
    expect(find.text('日常用餐'), findsOneWidget);
    expect(find.text('公交地铁'), findsOneWidget);

    await tester.tap(find.byKey(const Key('category-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-name-input')),
      '  日常用品  ',
    );
    await tester.tap(find.byKey(const Key('category-save')));
    await _pumpUntil(
      tester,
      () =>
          find.byType(CategoryEditorPage).evaluate().isEmpty &&
          _categoryListText('日常用品').evaluate().isNotEmpty,
    );

    expect(find.text('日常用品'), findsOneWidget);
    final created = (await repository.listCategories(defaultBookId, 'expense'))
        .singleWhere((category) => category.name == '日常用品');

    final editButton = find.byKey(Key('edit-category-${created.id}'));
    await tester.ensureVisible(editButton);
    await tester.pump();
    await tester.tap(editButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-name-input')),
      '居家用品',
    );
    await tester.tap(find.byKey(const Key('category-save')));
    await _pumpUntil(
      tester,
      () =>
          find.byType(CategoryEditorPage).evaluate().isEmpty &&
          _categoryListText('居家用品').evaluate().isNotEmpty &&
          _categoryListText('日常用品').evaluate().isEmpty,
    );

    expect(find.text('居家用品'), findsOneWidget);
    expect(find.text('日常用品'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds a second-level category from its parent group',
      (tester) async {
    await _pumpCategoryPage(tester, repository, service);
    final foodId = accountKeyFood(defaultBookId);

    await tester.tap(find.byKey(Key('category-add-child-$foodId')));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryEditorPage), findsOneWidget);
    expect(find.text('二级分类'), findsWidgets);
    expect(find.text('餐饮'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('category-name-input')),
      '工作午餐',
    );
    await tester.tap(find.byKey(const Key('category-save')));
    await _pumpUntil(
      tester,
      () =>
          find.byType(CategoryEditorPage).evaluate().isEmpty &&
          _categoryListText('工作午餐').evaluate().isNotEmpty,
    );

    final created = (await repository.listCategories(defaultBookId, 'expense'))
        .singleWhere((category) => category.name == '工作午餐');
    expect(created.parentAccountId, foodId);
    expect(find.byType(CategoryEditorPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches between expense and income categories', (tester) async {
    await _pumpCategoryPage(tester, repository, service);

    await tester.tap(find.byKey(const Key('category-type-income')));
    await _pumpUntil(
      tester,
      () => find.text('工资收入').evaluate().isNotEmpty,
    );

    expect(find.text('工资收入'), findsOneWidget);
    expect(find.text('餐饮'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps duplicate-name validation inside the editor',
      (tester) async {
    await _pumpCategoryPage(tester, repository, service);

    await tester.tap(find.byKey(const Key('category-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-name-input')),
      'Food',
    );
    await tester.tap(find.byKey(const Key('category-save')));
    await _pumpUntil(
      tester,
      () => find.text('同类型下已存在该分类').evaluate().isNotEmpty,
    );

    expect(find.text('同类型下已存在该分类'), findsOneWidget);
    expect(find.byType(CategoryEditorPage), findsOneWidget);
  });
}

Finder _categoryListText(String text) => find.descendant(
      of: find.byType(CategoriesPage),
      matching: find.text(text),
    );

Future<void> _pumpCategoryPage(
  WidgetTester tester,
  LedgerRepository repository,
  LedgerAppService service,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ledgerRepositoryProvider.overrideWithValue(repository),
        ledgerAppServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        theme: ledgerlyTheme(),
        home: const CategoriesPage(),
      ),
    ),
  );
  await _settleDatabase(tester);
}

Future<void> _settleDatabase(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pump();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) return;
  }
  fail('Timed out waiting for widget state');
}
