// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Ledgerly';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get saving => 'Saving';

  @override
  String get savingEllipsis => 'Saving…';

  @override
  String get retry => 'Retry';

  @override
  String get create => 'Create';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get unknown => 'Unknown';

  @override
  String get show => 'Show';

  @override
  String get hide => 'Hide';

  @override
  String get processing => 'Working…';

  @override
  String get navFeed => 'Feed';

  @override
  String get navAssets => 'Assets';

  @override
  String get navReports => 'Reports';

  @override
  String get navMe => 'Me';

  @override
  String get addTransaction => 'Add';

  @override
  String monthPickerLabel(int year, int month) {
    return '$year-$month';
  }

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String feedDayLabel(int month, int day, String weekday) {
    return '$weekday, $month/$day';
  }

  @override
  String fullDateLabel(int year, int month, int day) {
    return '$year-$month-$day';
  }

  @override
  String insightDailyDate(int year, int month, int day) {
    return '$year-$month-$day';
  }

  @override
  String insightMonthlyDate(int year, int month) {
    return '$year-$month';
  }

  @override
  String trendChartLabel(int year, int month) {
    return 'Daily income and expense trend for $year-$month';
  }

  @override
  String get uncategorized => 'Uncategorized';

  @override
  String get accountCash => 'Cash';

  @override
  String get accountBank => 'Bank';

  @override
  String get accountTransfer => 'Transfer';

  @override
  String get accountOther => 'Other';

  @override
  String get categoryFood => 'Food';

  @override
  String get categoryMeals => 'Meals';

  @override
  String get categoryDrinksSnacks => 'Drinks & snacks';

  @override
  String get categoryTransport => 'Transport';

  @override
  String get categoryPublicTransport => 'Public transport';

  @override
  String get categoryTaxi => 'Taxi';

  @override
  String get categoryCarExpenses => 'Car';

  @override
  String get categoryShopping => 'Shopping';

  @override
  String get categoryDailyEssentials => 'Essentials';

  @override
  String get categoryClothing => 'Clothing';

  @override
  String get categoryElectronics => 'Electronics';

  @override
  String get categoryHousing => 'Housing';

  @override
  String get categoryRentMortgage => 'Rent & mortgage';

  @override
  String get categoryUtilities => 'Utilities';

  @override
  String get categoryPropertyServices => 'Property';

  @override
  String get categoryLeisure => 'Leisure';

  @override
  String get categoryEntertainment => 'Entertainment';

  @override
  String get categoryFitness => 'Fitness';

  @override
  String get categoryTravel => 'Travel';

  @override
  String get categoryHealthcare => 'Healthcare';

  @override
  String get categoryMedicalCare => 'Medical care';

  @override
  String get categoryMedicine => 'Medicine';

  @override
  String get categoryEducation => 'Education';

  @override
  String get categoryBooks => 'Books';

  @override
  String get categoryCourses => 'Courses';

  @override
  String get categoryOtherExpense => 'Other expense';

  @override
  String get categorySalary => 'Salary';

  @override
  String get categoryBaseSalary => 'Base salary';

  @override
  String get categoryBonus => 'Bonus';

  @override
  String get categorySideIncome => 'Side income';

  @override
  String get categoryFreelance => 'Freelance';

  @override
  String get categoryBusinessIncome => 'Business';

  @override
  String get categoryInvestmentIncome => 'Investments';

  @override
  String get categoryInterest => 'Interest';

  @override
  String get categoryDividends => 'Dividends';

  @override
  String get categoryOtherIncome => 'Other income';

  @override
  String get assetAccounts => 'Asset accounts';

  @override
  String accountsSubtitle(int count) {
    return '$count accounts · CNY';
  }

  @override
  String get newAccount => 'New account';

  @override
  String get standardLedger => 'Standard book';

  @override
  String get newBook => 'New book';

  @override
  String get bookName => 'Book name';

  @override
  String get switchBook => 'Switch book';

  @override
  String get netWorth => 'Net worth';

  @override
  String get accountDetails => 'Accounts';

  @override
  String totalWithAmount(String amount) {
    return 'Total $amount';
  }

  @override
  String get noAssetAccounts => 'No asset accounts yet';

  @override
  String get noAssetAccountsHint => 'Add cash, bank, or other asset accounts.';

  @override
  String accountsLoadFailed(String error) {
    return 'Could not load accounts: $error';
  }

  @override
  String get newAccountName => 'New account';

  @override
  String get newAssetAccount => 'New asset account';

  @override
  String get accountName => 'Account name';

  @override
  String get liabilityAccount => 'Liability';

  @override
  String get assetAccount => 'Asset';

  @override
  String get allTransactions => 'All activity';

  @override
  String get monthlyFeedStats => 'This month';

  @override
  String feedLoadFailed(String error) {
    return 'Could not load activity: $error';
  }

  @override
  String insightLoadFailed(String error) {
    return 'Could not load insight: $error';
  }

  @override
  String get emptyMonthTitle => 'No activity this month';

  @override
  String get emptyMonthMessage => 'Tap + to add the first entry.';

  @override
  String get dayNet => 'Day net';

  @override
  String get deleteTransaction => 'Delete';

  @override
  String get monthlyInsightEntryTitle => 'Monthly insight';

  @override
  String get monthlyInsightEntrySubtitle =>
      'Open Reports to see this month’s AI summary';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get reportsSummarySection => 'This month';

  @override
  String get reportsTrendSection => 'Last 6 months';

  @override
  String get reportsBudgetSection => 'Budgets';

  @override
  String get reportsBudgetEmptyTitle => 'No budgets for this period';

  @override
  String get reportsBudgetEmptyAction => 'Set a budget';

  @override
  String get reportsHeroIncome => 'Income';

  @override
  String get reportsHeroExpense => 'Expense';

  @override
  String get reportsHeroNet => 'Net';

  @override
  String get reportsHeroBudgetLeft => 'Budget left';

  @override
  String get reportsHeroBudgetUnset => 'Not set';

  @override
  String get budgetCreated => 'Budget created';

  @override
  String get budgetDeleted => 'Budget deleted';

  @override
  String get reportsIncome => 'Income';

  @override
  String get reportsExpense => 'Expense';

  @override
  String get reportsNet => 'Net';

  @override
  String get reportsBaseCurrency => 'Base';

  @override
  String reportsUpdatedAgo(Object time) {
    return 'Updated $time ago';
  }

  @override
  String get reportsUpdatedJustNow => 'Updated just now';

  @override
  String get reportsCategories => 'Top categories';

  @override
  String get reportsNoBudgets => 'No budgets configured yet.';

  @override
  String get reportsPrevMonth => 'Previous month';

  @override
  String get reportsNextMonth => 'Next month';

  @override
  String get reportsRefresh => 'Refresh';

  @override
  String get aiInsightCardTitle => 'AI summary';

  @override
  String get aiInsightHighlights => 'Highlights';

  @override
  String get aiInsightAdvice => 'Suggestions';

  @override
  String get aiInsightRegenerate => 'Regenerate';

  @override
  String get aiInsightStale => 'Stale — regenerate';

  @override
  String get aiInsightUnconfigured =>
      'Connect an AI provider to see a monthly summary.';

  @override
  String get aiInsightUnconfiguredDesc =>
      'We\'ll analyze your income, expenses, and categories each month.';

  @override
  String get aiInsightConfigure => 'Configure AI';

  @override
  String get aiInsightEmpty => 'Nothing to summarize yet.';

  @override
  String get aiInsightEmptyDesc =>
      'Once you log a few transactions this month, your summary will appear here.';

  @override
  String get aiInsightPeriodMenu => 'Period';

  @override
  String get aiInsightPeriodMonth => 'This month';

  @override
  String reportsAllCategories(Object count) {
    return 'All categories ($count)';
  }

  @override
  String get reportsNoCategories => 'No matching categories.';

  @override
  String get reportsSearchHint => 'Search categories';

  @override
  String get reportsRangeTitle => 'Time range';

  @override
  String get reportsRangeMonth => 'This month';

  @override
  String get reportsRangeLast3 => 'Last 3 months';

  @override
  String get reportsRangeLast6 => 'Last 6 months';

  @override
  String get reportsRangeLast7 => 'Last 7 days';

  @override
  String get reportsRangeLast30 => 'Last 30 days';

  @override
  String get reportsRangeLast90 => 'Last 90 days';

  @override
  String get reportsRangeYear => 'This year';

  @override
  String get reportsRangeCustom => 'Custom range';

  @override
  String get reportsRangeStart => 'Start';

  @override
  String get reportsRangeEnd => 'End';

  @override
  String get reportsExport => 'Export & Share';

  @override
  String get reportsExportCsv => 'Export CSV';

  @override
  String get reportsShare => 'Share Summary';

  @override
  String get reportsExportNoData => 'No data to export.';

  @override
  String get reportsExportCsvDone => 'CSV exported successfully.';

  @override
  String get reportsExportCsvError => 'Export failed';

  @override
  String get reportsTrendJumpToMonth => 'Go to this month';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonRetry => 'Retry';

  @override
  String get localShort => 'Local';

  @override
  String get syncedShort => 'Synced';

  @override
  String get refreshRemoteSummary => 'Refresh server summary';

  @override
  String get monthlyFlowStats => 'This month';

  @override
  String get incomeSources => 'Income';

  @override
  String get noIncomeThisMonth => 'No income this month';

  @override
  String get expenseBreakdown => 'Expenses';

  @override
  String get noExpenseThisMonth => 'No expenses this month';

  @override
  String get monthlyTrend => 'Trend';

  @override
  String transactionCountLabel(int count) {
    return '$count entries';
  }

  @override
  String rankingTrailing(int count, String amount) {
    return '$count · $amount';
  }

  @override
  String get cloudCheck => 'Cloud check';

  @override
  String remoteNet(String net, String currency) {
    return 'Server net $net · $currency';
  }

  @override
  String reportsLoadFailed(String error) {
    return 'Could not load reports: $error';
  }

  @override
  String get thisMonthBalance => 'Balance';

  @override
  String incomeAmount(String amount) {
    return 'In $amount';
  }

  @override
  String expenseAmount(String amount) {
    return 'Out $amount';
  }

  @override
  String get income => 'Income';

  @override
  String get expense => 'Expense';

  @override
  String get transfer => 'Transfer';

  @override
  String get insightKindDaily => 'Daily';

  @override
  String get insightKindMonthly => 'Monthly';

  @override
  String aiInsightTitleWithPeriod(String kind, String period) {
    return 'AI $kind · $period';
  }

  @override
  String aiInsightTitleKindOnly(String kind) {
    return 'AI $kind';
  }

  @override
  String get goConfigure => 'Set up';

  @override
  String get insightExpand => 'Show insight';

  @override
  String get insightCollapse => 'Hide insight';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get generate => 'Generate';

  @override
  String get insightUnconfiguredDaily =>
      'After you add a provider and API key, daily spend summaries appear in each day’s activity. Today and yesterday fill in automatically; older days wait until you tap Generate. The current text models cannot transcribe speech.';

  @override
  String get insightUnconfiguredMonthly =>
      'After you add a provider and API key, a monthly spend report is generated for the selected month, and last month is filled in when a new month starts. The current text models cannot transcribe speech.';

  @override
  String get insightNotGenerated => 'Insight not generated yet';

  @override
  String get insightGenerating => 'Generating insight…';

  @override
  String get insightEmptyDaily => 'No spending today';

  @override
  String get insightEmptyMonthly => 'No spending this month';

  @override
  String get insightEmptyNoModel => 'No activity, so the model was not called.';

  @override
  String get insightFailed => 'Insight failed';

  @override
  String get insightStale => 'Entries changed. You can regenerate.';

  @override
  String get insightFallbackHeadline => 'Spend summary';

  @override
  String tokenUsage(String model, String prompt, String completion) {
    return '$model · in $prompt / out $completion tokens';
  }

  @override
  String get aiSettingsTitle => 'Insights';

  @override
  String get modelService => 'Model';

  @override
  String get provider => 'Provider';

  @override
  String get aiProviderCustom => 'Compatible API';

  @override
  String get model => 'Model';

  @override
  String get custom => 'Custom';

  @override
  String get customModelId => 'Custom model ID';

  @override
  String get autoGenerateInsights => 'Generate automatically';

  @override
  String get autoGenerateInsightsSubtitle =>
      'Fill in today, yesterday, and last month when you open the app. Older days wait until you tap Generate.';

  @override
  String get aiPromptPreset => 'System prompt';

  @override
  String get aiPromptPresetBalanced => 'Balanced summary';

  @override
  String get aiPromptPresetFrugal => 'Frugal coach';

  @override
  String get aiPromptPresetReview => 'Review assistant';

  @override
  String get aiPromptPresetConcise => 'Concise take';

  @override
  String get aiPromptPresetCustom => 'Custom';

  @override
  String get aiPromptPresetBalancedSubtitle =>
      'Summarize the mix, flag large amounts, and give one next action.';

  @override
  String get aiPromptPresetFrugalSubtitle =>
      'Look first for spending you can cut or postpone.';

  @override
  String get aiPromptPresetReviewSubtitle =>
      'Facts first, then judgment. Call out the biggest and oddest item.';

  @override
  String get aiPromptPresetConciseSubtitle =>
      'Shorter headline, three facts, one suggestion.';

  @override
  String get aiPromptPresetCustomSubtitle =>
      'Use your own system prompt. The model still has to return JSON.';

  @override
  String get aiCustomSystemPrompt => 'Custom system prompt';

  @override
  String get aiCustomSystemPromptHint =>
      'For example: summarize spending in a casual tone and say whether the day looks off-pace.';

  @override
  String get testingConnection => 'Testing…';

  @override
  String get testConnection => 'Test connection';

  @override
  String get capabilitiesAndUsage => 'Capabilities and usage';

  @override
  String get aiSavedLocally =>
      'Saved. The key stays on this device and is not synced with the ledger service.';

  @override
  String saveFailed(String error) {
    return 'Could not save: $error';
  }

  @override
  String get enterApiKeyFirst => 'Enter an API key first.';

  @override
  String get connectionSuccess => 'Connected.';

  @override
  String get aiCapabilityProtocol =>
      'Requests use OpenAI-compatible Chat Completions. Insight models cannot transcribe speech. Category, amount, and notes are sent to the endpoint you configure.';

  @override
  String get aiCapabilityOpencode =>
      'OpenCode uses the Zen Go gateway https://opencode.ai/zen/go/v1. Browsers block cross-origin requests, so Test connection fails on web; save the key and use the app. Presets only include Chat Completions models. GPT / Claude are out of scope for now.';

  @override
  String aiCapabilityUsage(String hint) {
    return 'There is no cumulative usage dashboard in this release. ${hint}The insight card shows tokens from the latest call.';
  }

  @override
  String get aiUsageHintDeepseek =>
      'Check your balance in the DeepSeek console. ';

  @override
  String get aiUsageHintOpencode =>
      'Check your key and balance in the OpenCode console. Browsers cannot call this API (no CORS); use the app. ';

  @override
  String get aiUsageHintCustom => 'Check usage in your provider console. ';

  @override
  String get invalidHttpUrl => 'Enter an http(s) URL';

  @override
  String get urlMustNotIncludeCredentials =>
      'The URL must not include credentials';

  @override
  String get cannotSaveApiKey => 'Could not save the API key.';

  @override
  String get cannotSaveModelSettings => 'Could not save model settings.';

  @override
  String get modelReturnedEmpty => 'The model returned no usable content.';

  @override
  String get invalidApiKey => 'The API key is invalid. Check Settings.';

  @override
  String get modelBalanceLow => 'The model account is out of credit.';

  @override
  String get tooManyRequests => 'Too many requests. Try again later.';

  @override
  String get corsBlockedOpencode =>
      'The browser blocked a cross-origin request. The official OpenCode API does not allow web calls. Save the key and use the app, or switch to a CORS-enabled compatible gateway.';

  @override
  String get cannotReachModelWeb =>
      'Could not reach the model service. The browser may be blocking the request; use the app or a compatible endpoint.';

  @override
  String get cannotReachModel =>
      'Could not reach the model service. Check the network and Base URL.';

  @override
  String get modelTimeout => 'The model service timed out. Try again later.';

  @override
  String get modelCallFailed => 'The model call failed.';

  @override
  String modelCallFailedWithStatus(int status) {
    return 'The model call failed ($status).';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSubtitleLocal => 'Local mode · data stays on this device';

  @override
  String get settingsSubtitleRemote =>
      'Connected · the book syncs automatically';

  @override
  String get dataAndSync => 'Data and sync';

  @override
  String get apiService => 'API';

  @override
  String get syncCenter => 'Sync';

  @override
  String get syncCenterSubtitle => 'Pending changes and recent status';

  @override
  String get syncStatusReady => 'Synced';

  @override
  String get syncStatusPending => 'Syncing…';

  @override
  String get syncStatusError => 'Error';

  @override
  String get syncRemoteBook => 'Remote book';

  @override
  String get syncCursorLabel => 'Cursor';

  @override
  String get syncPendingLabel => 'Pending changes';

  @override
  String syncPendingCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes pending',
      one: '1 change pending',
      zero: 'Nothing pending',
    );
    return '$_temp0';
  }

  @override
  String get syncLastError => 'Last error';

  @override
  String get syncInProgress => 'Syncing…';

  @override
  String get conflicts => 'Conflicts';

  @override
  String get conflictEntityHint => 'Transaction';

  @override
  String get conflictResolveRemoteHint =>
      'Discard local edits, take the version on the server';

  @override
  String get conflictResolveLocalHint =>
      'Keep local edits and push them back to the server';

  @override
  String get conflictResolved => 'Conflict resolved';

  @override
  String conflictRemoteVersion(Object version) {
    return 'Remote version $version';
  }

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get exportCsvSubtitle => 'Back up this book';

  @override
  String get ledgerSection => 'Book';

  @override
  String get categoryManagement => 'Categories';

  @override
  String get categoryManagementSubtitle => 'Expense and income categories';

  @override
  String get budgetTargets => 'Budgets';

  @override
  String get budgetTargetsSubtitle => 'Monthly spending limits';

  @override
  String get smartInsights => 'Insights';

  @override
  String get aiSpendInsights => 'AI spend insights';

  @override
  String get aiSpendInsightsSubtitle =>
      'Provider, key, model, prompt, and auto-generate';

  @override
  String get accountSection => 'Account';

  @override
  String get logOut => 'Log out';

  @override
  String get switchToLocalTitle => 'Switch to local-only storage?';

  @override
  String get connectApiTitle => 'Connect to the API?';

  @override
  String get switchApiTitle => 'Switch API?';

  @override
  String get switchToLocalBody =>
      'You will be signed out of the remote account. Local book data is kept.';

  @override
  String get connectApiBody =>
      'You will need to sign in. Local book data is kept.';

  @override
  String get localOnlyStorage => 'Local only';

  @override
  String get localOnlyHelp => 'Connect to a server to enable sync';

  @override
  String get confirmConnect => 'Connect';

  @override
  String get apiSettingsSaveFailed =>
      'Could not save API settings. The current storage mode is unchanged.';

  @override
  String get confirmLogoutTitle => 'Log out?';

  @override
  String get confirmLogoutBody =>
      'Local book data is kept. You can continue after you sign in again.';

  @override
  String get endpointUnsetLocal => 'Not set (local only)';

  @override
  String get login => 'Sign in';

  @override
  String get register => 'Register';

  @override
  String get email => 'Email';

  @override
  String get emailTooLong => 'Email must be at most 254 characters';

  @override
  String get invalidEmail => 'Enter a valid email';

  @override
  String get displayName => 'Name';

  @override
  String get enterDisplayName => 'Enter a name';

  @override
  String get displayNameTooLong => 'Name must be at most 80 characters';

  @override
  String get password => 'Password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String get passwordTooLong => 'Password must be at most 128 characters';

  @override
  String get registerAndContinue => 'Register and continue';

  @override
  String get changeApiService => 'Change API';

  @override
  String get apiAddressSaveFailed =>
      'Could not save the API address. Try again later.';

  @override
  String get restoreSessionFailed => 'Could not restore the session.';

  @override
  String get restoreSessionFailedRetry =>
      'Could not restore the session. Try again later.';

  @override
  String get loginFailedRetry => 'Could not sign in. Try again later.';

  @override
  String get registerFailedRetry => 'Could not register. Try again later.';

  @override
  String get logoutRemoteRevokeFailed =>
      'Signed out on this device, but the server session could not be revoked.';

  @override
  String get sessionExpired => 'Your session expired. Sign in again.';

  @override
  String get invalidCredentials => 'Email or password is incorrect.';

  @override
  String get emailTaken => 'That email is already registered.';

  @override
  String get weakPassword => 'Password must be 8–128 characters.';

  @override
  String get cannotReachServer =>
      'Could not reach the server. Check the network and try again.';

  @override
  String get cannotReadSavedApi =>
      'Could not read the saved API address. Set it again.';

  @override
  String get apiEndpointSetupTitle => 'API setup';

  @override
  String get apiEndpointSetupSubtitle =>
      'Optional. Leave empty to stay local-only.';

  @override
  String get apiAddressOptional => 'API address (optional)';

  @override
  String get apiAddressHelper =>
      'Native apps accept LAN IPs. Leave empty for local-only storage.';

  @override
  String get saveSettings => 'Save';

  @override
  String get requireHttpsLanOk =>
      'Use HTTPS. Native clients also accept LAN IP addresses.';

  @override
  String get webReleaseHttps443 =>
      'The web release only supports the default HTTPS port (443).';

  @override
  String get apiOriginOnly =>
      'Enter an API origin without path, query, or credentials.';

  @override
  String get enterApiAddress => 'Enter an API address';

  @override
  String get invalidHttpApiAddress => 'Enter a valid HTTP(S) API address';

  @override
  String get newCategory => 'New category';

  @override
  String categoryTypeHeading(String type) {
    return '$type categories';
  }

  @override
  String categoryLevelCounts(int roots, int seconds) {
    return '$roots top-level · $seconds second-level';
  }

  @override
  String noCategoriesOfType(String type) {
    return 'No $type categories yet';
  }

  @override
  String get noCategoriesHint =>
      'Add a top-level category, then add second-level ones.';

  @override
  String get categoriesLoadFailed => 'Could not load categories';

  @override
  String get noSecondLevelCategories => 'No second-level categories';

  @override
  String secondLevelCount(int count) {
    return '$count second-level categories';
  }

  @override
  String addChildCategoryUnder(String name) {
    return 'Add a second-level category under $name';
  }

  @override
  String editNamedCategory(String name) {
    return 'Edit $name';
  }

  @override
  String get secondLevelCategory => 'Second level';

  @override
  String get firstLevelCategory => 'Top level';

  @override
  String get needParentCategoryFirst =>
      'Create a top-level category of this type first';

  @override
  String get categorySaveFailed =>
      'Could not save the category. Try again later.';

  @override
  String get editCategory => 'Edit category';

  @override
  String get categoryInfo => 'Category';

  @override
  String get categoryName => 'Name';

  @override
  String get flowType => 'Type';

  @override
  String get categoryLevel => 'Level';

  @override
  String get parentCategory => 'Parent';

  @override
  String get categoryHasChildrenKeepRoot =>
      'This category has children, so it stays top-level.';

  @override
  String get categoryNotFound => 'Category not found';

  @override
  String get cannotNestRootWithChildren =>
      'A top-level category with children cannot become second-level';

  @override
  String get enterCategoryName => 'Enter a category name';

  @override
  String get categoryNameTooLong =>
      'Category name must be at most 24 characters';

  @override
  String get invalidCategoryType => 'Invalid category type';

  @override
  String get categoryCannotBeOwnParent => 'A category cannot be its own parent';

  @override
  String get chooseSameTypeParent =>
      'Choose a top-level category of the same type';

  @override
  String get categoryMaxTwoLevels => 'Categories can only have two levels';

  @override
  String get duplicateCategoryName =>
      'A category with this name already exists';

  @override
  String get editTransaction => 'Edit entry';

  @override
  String get date => 'Date';

  @override
  String get category => 'Category';

  @override
  String get fromAccount => 'From';

  @override
  String get account => 'Account';

  @override
  String get toAccount => 'To';

  @override
  String get noteOptional => 'Add a note (optional)';

  @override
  String get expenseAmountLabel => 'Expense';

  @override
  String get incomeAmountLabel => 'Income';

  @override
  String get transferAmountLabel => 'Transfer';

  @override
  String get updateExpense => 'Update expense';

  @override
  String get saveExpense => 'Save expense';

  @override
  String get updateIncome => 'Update income';

  @override
  String get saveIncome => 'Save income';

  @override
  String get updateTransfer => 'Update transfer';

  @override
  String get saveTransfer => 'Save transfer';

  @override
  String get pickIncomeCategory => 'Choose income category';

  @override
  String get pickExpenseCategory => 'Choose expense category';

  @override
  String get pickDate => 'Choose date';

  @override
  String get ok => 'OK';

  @override
  String get pickFromAccount => 'Choose source account';

  @override
  String get pickAccount => 'Choose account';

  @override
  String get pickToAccount => 'Choose destination account';

  @override
  String get enterPositiveAmount => 'Enter an amount greater than 0';

  @override
  String get missingCategoryOrAccount =>
      'This book has no usable category or account';

  @override
  String get transferAccountsMustDiffer =>
      'Source and destination must be different';

  @override
  String get finishEditing => 'Done';

  @override
  String get editCategoryAction => 'Edit categories';

  @override
  String get noCategories => 'No categories';

  @override
  String get noAccounts => 'No accounts';

  @override
  String get addCategory => 'Add category';

  @override
  String parentSecondLevel(String parent) {
    return '$parent · second level';
  }

  @override
  String editNamed(String name) {
    return 'Edit $name';
  }

  @override
  String selectNamed(String name) {
    return 'Select $name';
  }

  @override
  String get backspace => 'Backspace';

  @override
  String get decimalPoint => 'Decimal';

  @override
  String get notSignedInBudgets => 'Sign in to load budgets';

  @override
  String get createExpenseCategoryFirst =>
      'Create an expense category before setting a budget';

  @override
  String get notSignedInCreateBudget => 'Sign in to create a budget';

  @override
  String get allExpenses => 'All expenses';

  @override
  String get expenseCategory => 'Expense category';

  @override
  String get cannotReachService =>
      'Could not reach the service. Check the network and try again.';

  @override
  String get budgetsLoadFailed => 'Could not load budgets. Try again later.';

  @override
  String get refreshBudgets => 'Refresh budgets';

  @override
  String get addBudget => 'Add budget';

  @override
  String get noBudgets => 'No budgets yet';

  @override
  String get noBudgetsHint => 'Set a monthly cap for an expense category.';

  @override
  String get setFirstBudget => 'Set the first budget';

  @override
  String get thisMonthTargets => 'This month';

  @override
  String itemCount(int count) {
    return '$count items';
  }

  @override
  String budgetDefaultName(String name) {
    return '$name this month';
  }

  @override
  String get enterPositiveDecimalAmount =>
      'Enter an amount greater than 0 with up to 2 decimals';

  @override
  String get setBudgetTarget => 'Set budget';

  @override
  String get thisMonth => 'This month';

  @override
  String get targetName => 'Name';

  @override
  String get monthlyAmount => 'Monthly amount';

  @override
  String get saveTarget => 'Save';

  @override
  String get monthTotalTarget => 'Monthly total';

  @override
  String get overBudget => 'Over';

  @override
  String get budgetTarget => 'Budget';

  @override
  String monthlyWithCategory(String category) {
    return 'Monthly · $category';
  }

  @override
  String spentAmount(String amount) {
    return 'Spent $amount';
  }

  @override
  String overByAmount(String amount) {
    return 'Over by $amount';
  }

  @override
  String remainingAmount(String amount) {
    return 'Left $amount';
  }

  @override
  String get notSignedInSync => 'Not signed in';

  @override
  String get attachmentsUpload => 'Attachments';

  @override
  String get attachmentsHelp =>
      'HMAC signed upload to local object storage: create session → PUT → complete.';

  @override
  String get uploading => 'Uploading…';

  @override
  String get uploadDemoFile => 'Upload demo file';

  @override
  String get noConflicts => 'No conflicts';

  @override
  String conflictSubtitle(String reason, String version) {
    return '$reason · remote version $version';
  }

  @override
  String get useRemote => 'Use remote';

  @override
  String get keepLocal => 'Keep local';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get copyCsv => 'Copy CSV';

  @override
  String get notSignedInInvites => 'Sign in to load invites';

  @override
  String get familySharing => 'Family';

  @override
  String get inviteEmail => 'Invite email';

  @override
  String get sendInvite => 'Send invite';

  @override
  String get sentInvites => 'Sent invites';

  @override
  String inviteRoleToken(String role, String token) {
    return 'Role $role · token $token';
  }

  @override
  String get fxRates => 'FX rates';

  @override
  String get quoteCurrencyVsCny => 'Quote currency (vs CNY)';

  @override
  String get exchangeRate => 'Rate';

  @override
  String get monthlyRent => 'Monthly rent';

  @override
  String get createdWillPostSoon =>
      'Created. The worker should post it within about a minute.';

  @override
  String get createdWillPostTomorrow =>
      'Created. The worker will post it from tomorrow.';

  @override
  String get recurring => 'Recurring';

  @override
  String get ruleName => 'Rule name';

  @override
  String get amountInvalid => 'Enter a valid amount';

  @override
  String get amountRequired => 'Amount is required';

  @override
  String get amountMustBePositive => 'Amount must be greater than zero';

  @override
  String get merchantOptional => 'Merchant (optional)';

  @override
  String get note => 'Note';

  @override
  String get runNow => 'Run now';

  @override
  String get createRule => 'Create rule';

  @override
  String get upgraded => 'Upgraded';

  @override
  String get subscription => 'Subscription';

  @override
  String get currentPlan => 'Current plan';

  @override
  String get devUpgradePlus =>
      'Dev upgrade Plus (attachments / advanced reports)';

  @override
  String get devUpgradeFamily => 'Dev upgrade Family (invites)';

  @override
  String get downgradeFree => 'Downgrade to Free';

  @override
  String statusLabel(String label) {
    return 'Status: $label';
  }

  @override
  String cursorLabel(int cursor) {
    return 'Cursor: $cursor';
  }

  @override
  String pendingLabel(int count) {
    return 'Pending: $count';
  }

  @override
  String remoteBookLabel(String id) {
    return 'Remote book: $id';
  }

  @override
  String errorLabel(String error) {
    return 'Error: $error';
  }

  @override
  String syncSuccess(int cursor) {
    return 'Synced, cursor=$cursor';
  }

  @override
  String syncFailed(String message) {
    return 'Sync failed: $message';
  }

  @override
  String get syncNow => 'Sync now';

  @override
  String get noRemoteBook => 'No remote book';

  @override
  String get revisionHistory => 'History';

  @override
  String get syncReady => 'Ready';

  @override
  String get syncError => 'Error';

  @override
  String get bookBoundToOtherAccount =>
      'This local book is bound to another account. Sync stopped.';

  @override
  String get searchTransactionsHint =>
      'Search notes, categories, accounts, or amounts';

  @override
  String get noSearchResults => 'No matching activity';

  @override
  String get noSearchResultsMessage =>
      'Try another keyword, or clear the search';

  @override
  String get feedSourceFilterAll => 'All';

  @override
  String get feedSourceFilterAuto => 'Auto';

  @override
  String get feedSourceFilterManual => 'Manual';

  @override
  String get feedSourceFilterAutoTooltip =>
      'Posted by auto-capture from WeChat / Alipay notifications';

  @override
  String get feedSourceBadgeTooltip =>
      'Auto-captured from a payment notification';

  @override
  String get feedMonthlySummaryAll => 'All transactions';

  @override
  String get feedMonthlySummaryAuto => 'Auto-captured only';

  @override
  String get feedMonthlySummaryManual => 'Manually entered only';

  @override
  String get securitySection => 'Security';

  @override
  String get appLock => 'App lock';

  @override
  String get appLockSubtitle =>
      'Protect opening the app with a PIN or biometrics';

  @override
  String get appLockBody =>
      'When enabled, unlock is required after a cold start and when returning to the app. PIN always works; biometrics are optional.';

  @override
  String get enableAppLock => 'Enable app lock';

  @override
  String get disableAppLock => 'Turn off app lock';

  @override
  String get appLockPin => 'PIN';

  @override
  String get appLockPinConfirm => 'Confirm PIN';

  @override
  String get appLockPinHint => '4 to 8 digits';

  @override
  String get unlock => 'Unlock';

  @override
  String get wrongPin => 'Incorrect PIN';

  @override
  String get pinMismatch => 'The PINs do not match';

  @override
  String get invalidPin => 'Enter 4 to 8 digits';

  @override
  String get appLockedTitle => 'Locked';

  @override
  String get unlockWithBiometrics => 'Unlock with biometrics';

  @override
  String get useBiometrics => 'Unlock with biometrics';

  @override
  String get useBiometricsSubtitle =>
      'Try fingerprint or face first; PIN remains the fallback';

  @override
  String get biometricsUnavailable =>
      'Biometrics are not available on this device';

  @override
  String get importSelectAll => 'Select all';

  @override
  String get importSelectNone => 'Select none';

  @override
  String get importDuplicateHint =>
      'Already in the ledger for the same day, amount, and note. Unchecked.';

  @override
  String get importHelp =>
      'Supports Alipay and WeChat CSV exports (UTF-8 or GBK). Refunds and closed rows are skipped. Rows are posted only after you confirm.';

  @override
  String get importCsv => 'Import bills';

  @override
  String get importCsvSubtitle =>
      'Import from Alipay, WeChat, or an exported CSV';

  @override
  String get importCsvTitle => 'Import bills';

  @override
  String get pickCsv => 'Choose a CSV file';

  @override
  String get importConfirm => 'Confirm import';

  @override
  String importSelectedCount(int count) {
    return 'Import $count rows';
  }

  @override
  String importedCount(int count) {
    return 'Imported $count rows';
  }

  @override
  String get importNothing => 'Nothing to import';

  @override
  String get saveCsvFile => 'Save / share';

  @override
  String get csvSaved => 'File exported';

  @override
  String get allExpensesBudgetName => 'All expenses budget';

  @override
  String get dayOfMonth => 'Day of month';

  @override
  String nextRunDate(String date) {
    return 'Next posting $date';
  }

  @override
  String get recurringLocalHelp =>
      'Posts on day 1–31 each month; if that date does not exist, it posts on the last day. Stored only on this device. Duplicates are skipped.';

  @override
  String get recurringSubtitle => 'Automatic monthly posting';

  @override
  String get attachmentsLocalHelp =>
      'Attachments stay on this device and are not synced.';

  @override
  String get attachmentsSubtitle => 'Stored on this device only';

  @override
  String get addAttachment => 'Add file';

  @override
  String get addImage => 'Add photo';

  @override
  String get noAttachments => 'No attachments yet';

  @override
  String get monthBudgetProgress => 'This month\'s budgets';

  @override
  String get lastDayOfMonthHint =>
      'If the month has fewer days, post on the last day';

  @override
  String get deleteBudget => 'Delete budget';

  @override
  String get pauseRule => 'Pause';

  @override
  String get resumeRule => 'Resume';

  @override
  String get deleteRule => 'Delete rule';

  @override
  String get kindLabel => 'Type';

  @override
  String get kindExpense => 'Expense';

  @override
  String get kindIncome => 'Income';

  @override
  String get fundingAccount => 'Funding account';

  @override
  String get autoLedgerSection => 'Auto ledger';

  @override
  String get autoLedgerTitle => 'Auto-capture payments';

  @override
  String get autoLedgerSubtitle =>
      'Read WeChat and Alipay notifications, post as expenses or income';

  @override
  String get autoLedgerEnable => 'Enable auto ledger';

  @override
  String get autoLedgerDisable => 'Disable auto ledger';

  @override
  String get autoLedgerGranted => 'Notification access granted';

  @override
  String get autoLedgerNotGranted => 'Notification access required';

  @override
  String get autoLedgerOpenSettings => 'Open notification settings';

  @override
  String get autoLedgerSyncNow => 'Sync pending now';

  @override
  String autoLedgerSyncSummary(int posted, int duplicates, int skipped) {
    return 'Posted $posted, duplicates $duplicates, skipped $skipped';
  }

  @override
  String get autoLedgerEmpty => 'No pending notifications';

  @override
  String get autoLedgerFailed => 'Could not read notification access state';

  @override
  String get amountYuan => 'Amount (yuan)';

  @override
  String autoLedgerPendingCount(int count) {
    return '$count pending';
  }

  @override
  String get autoLedgerPlatformWechat => 'WeChat Pay';

  @override
  String get autoLedgerPlatformAlipay => 'Alipay';

  @override
  String get autoLedgerPlatformUnknown => 'Unknown platform';

  @override
  String get autoLedgerRescueTitle => 'Rescue this notification';

  @override
  String autoLedgerRescueReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get autoLedgerRescuePlatform => 'Platform';

  @override
  String get autoLedgerRescueTime => 'Time';

  @override
  String get autoLedgerRescueRawLabel => 'Original text';

  @override
  String get autoLedgerRescueSubmit => 'Save to ledger';

  @override
  String get autoLedgerRescueAlreadySaved => 'Already saved to the ledger.';

  @override
  String get autoLedgerRescueCategoryLabel => 'Category';

  @override
  String get autoLedgerRescueLearnRule => 'Remember this merchant → category';

  @override
  String get autoLedgerRescueLearnRuleHint =>
      'Future notifications from this merchant will be auto-posted here.';

  @override
  String get autoLedgerRescueLearnRuleToast =>
      'Rule saved. Future payments at this merchant will be auto-posted.';

  @override
  String get all => 'All';

  @override
  String get autoLedgerUnparsedEmpty => 'No unrecognised notifications';

  @override
  String get autoLedgerUnparsedEmptyHint =>
      'Notifications that don\'t look like a payment will appear here.';

  @override
  String autoLedgerUnparsedCount(int count) {
    return '$count unrecognised';
  }

  @override
  String get autoLedgerUnparsedDismiss => 'Clear all';

  @override
  String get autoLedgerUnparsedCopy => 'Copy raw text';

  @override
  String get autoLedgerUnparsedCopied => 'Raw text copied';

  @override
  String autoLedgerBulkRescueTitle(int count) {
    return 'Bulk rescue ($count)';
  }

  @override
  String autoLedgerBulkRescueSummary(int count) {
    return 'About to post $count entries using the same amount and category.';
  }

  @override
  String autoLedgerBulkRescueAmountHint(int count) {
    return 'Shared amount for all $count entries.';
  }

  @override
  String autoLedgerBulkRescueConfirm(int count) {
    return 'Post $count entries';
  }

  @override
  String autoLedgerBulkSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get autoLedgerBulkClear => 'Clear';

  @override
  String autoLedgerBulkRescue(int count) {
    return 'Rescue ($count)';
  }

  @override
  String autoLedgerBulkRescueSuccess(int count) {
    return 'Rescued $count entries.';
  }

  @override
  String autoLedgerBulkRescuePartial(int rescued, int failed) {
    return 'Rescued $rescued, failed $failed.';
  }

  @override
  String autoLedgerBulkRescueTotalPreview(
      int count, String unit, String total) {
    return '$count entries × ¥$unit = ¥$total';
  }

  @override
  String autoLedgerBacklogTitle(int count) {
    return '$count unrecognised notifications waiting';
  }

  @override
  String autoLedgerBacklogDominantHint(String reason, int count) {
    return 'Most are tagged $reason ($count entries). Consider adding a merchant rule to cover this case.';
  }

  @override
  String get autoLedgerBacklogAction => 'Review';

  @override
  String get selectAll => 'Select all';

  @override
  String get autoLedgerRulesTitle => 'Merchant classification rules';

  @override
  String get autoLedgerRulesSubtitle =>
      'Tell Ledgerly which category a merchant belongs to. Custom rules win over the built-in defaults.';

  @override
  String get autoLedgerRulesEmpty => 'No custom rules yet';

  @override
  String get autoLedgerRulesEmptyHint =>
      'Add one when a notification is miscategorized. Rules persist on this device only.';

  @override
  String get autoLedgerRuleAddTitle => 'New classification rule';

  @override
  String get autoLedgerRuleEditTitle => 'Edit classification rule';

  @override
  String get autoLedgerRuleAdd => 'Add rule';

  @override
  String get autoLedgerRuleNeedlesLabel => 'Match phrases';

  @override
  String get autoLedgerRuleNeedlesHelper =>
      'Separate multiple phrases with commas. Any match wins.';

  @override
  String get autoLedgerRuleCategoryLabel => 'Default category';

  @override
  String get autoLedgerRuleChooseCategory => 'Pick a category first.';

  @override
  String get autoLedgerRuleNeedNeedle => 'Add at least one match phrase.';

  @override
  String get autoLedgerRuleDeleteTitle => 'Delete this rule?';

  @override
  String get autoLedgerRuleDeleteBody =>
      'Future notifications that match this rule will fall back to the built-in defaults.';

  @override
  String get systemSection => 'System';

  @override
  String get keyboardShortcutsTitle => 'Keyboard shortcuts';

  @override
  String get keyboardShortcutsSubtitle =>
      'Discover the shortcuts available across Ledgerly.';

  @override
  String get keyboardShortcutsGeneral => 'General';

  @override
  String get keyboardShortcutsBookkeeping => 'Bookkeeping';

  @override
  String get keyboardShortcutsSync => 'Sync';

  @override
  String get keyboardShortcutsOpenPalette => 'Open command palette';

  @override
  String get keyboardShortcutsOpenPaletteDescription =>
      'Fuzzy search across all pages and actions.';

  @override
  String get keyboardShortcutsCloseDialog => 'Close dialog';

  @override
  String get keyboardShortcutsCloseDialogDescription =>
      'Dismiss any open sheet or dialog.';

  @override
  String get keyboardShortcutsNewTransaction => 'New transaction';

  @override
  String get keyboardShortcutsNewTransactionDescription =>
      'Open the quick entry editor.';

  @override
  String get keyboardShortcutsTriggerSync => 'Sync now';

  @override
  String get keyboardShortcutsTriggerSyncDescription =>
      'Trigger an immediate sync from the command palette.';

  @override
  String get commandPaletteTitle => 'Command palette';

  @override
  String get commandPaletteHint => 'Type a command or search…';

  @override
  String get commandPaletteNoResults => 'No matching commands';

  @override
  String get commandPaletteStatus => 'Esc close · ↑↓ select · ↵ run';

  @override
  String get dataGovernanceTitle => 'Data governance';

  @override
  String get dataGovernanceSubtitle =>
      'Backup, restore, or wipe everything on this device';

  @override
  String get dataGovernanceBackup => 'Backup';

  @override
  String get dataGovernanceBackupSubtitle =>
      'Save a full snapshot of every book, account, budget, and rule.';

  @override
  String get dataGovernanceBackupAction => 'Export full snapshot';

  @override
  String get dataGovernanceBackupInProgress => 'Exporting…';

  @override
  String dataGovernanceBackupSuccess(String path) {
    return 'Backup saved to $path';
  }

  @override
  String get dataGovernanceBackupShare => 'Share / save elsewhere';

  @override
  String get dataGovernanceRestore => 'Restore';

  @override
  String get dataGovernanceRestoreSubtitle =>
      'Pick a backup file, preview it, then replace or merge it into this device.';

  @override
  String get dataGovernanceRestoreAction => 'Pick a backup file';

  @override
  String get dataGovernanceRestoreInProgress => 'Restoring…';

  @override
  String get dataGovernanceRestorePreview => 'Preview';

  @override
  String dataGovernanceRestorePreviewSummary(
      int books,
      int accounts,
      int transactions,
      int entries,
      int rules,
      int budgets,
      int attachments,
      int merchantRules) {
    return '$books books · $accounts accounts · $transactions transactions · $entries entries · $rules recurring · $budgets budgets · $attachments attachments · $merchantRules merchant rules';
  }

  @override
  String get dataGovernanceRestorePreviewEmpty =>
      'This backup contains no data. Restoring will leave the device empty.';

  @override
  String get dataGovernanceRestoreModeReplace => 'Replace local data';

  @override
  String get dataGovernanceRestoreModeMerge => 'Merge new books';

  @override
  String get dataGovernanceRestoreMergeHint =>
      'Books with the same ID and existing data are skipped. Only empty placeholder books can be replaced.';

  @override
  String get dataGovernanceRestoreReplaceAction => 'Replace local data';

  @override
  String get dataGovernanceRestoreMergeAction => 'Merge into device';

  @override
  String get dataGovernanceRestoreConfirmTitle => 'Replace local data?';

  @override
  String dataGovernanceRestoreConfirmBody(String path) {
    return 'Restore will overwrite every book on this device. A safety copy was written to $path so you can roll back if anything looks wrong.';
  }

  @override
  String get dataGovernanceRestoreConfirmMergeTitle =>
      'Merge into this device?';

  @override
  String dataGovernanceRestoreConfirmMergeBody(String path) {
    return 'Only new books and empty placeholder books will be merged. Books with the same ID and existing data are skipped. A safety copy was written to $path.';
  }

  @override
  String dataGovernanceRestoreMergeSuccess(
      int added, int replaced, int skipped) {
    return 'Merged $added new books, replaced $replaced empty books, skipped $skipped existing books.';
  }

  @override
  String get dataGovernanceRestoreMergeNoChanges =>
      'Nothing new to merge. Existing books were kept unchanged.';

  @override
  String get dataGovernanceRestoreSuccess => 'Restore complete. Reloading…';

  @override
  String dataGovernanceRestoreHistory(int count) {
    return 'Restore history · $count';
  }

  @override
  String get dataGovernanceRestoreAuditSuccess => 'Succeeded';

  @override
  String get dataGovernanceRestoreAuditFailed => 'Failed';

  @override
  String dataGovernanceRestoreAuditBackup(String backupId) {
    return 'Source backup: $backupId';
  }

  @override
  String dataGovernanceRestoreAuditSafety(String path) {
    return 'Safety backup: $path';
  }

  @override
  String dataGovernanceRestoreAuditError(String error) {
    return 'Error: $error';
  }

  @override
  String get dataGovernanceRestoreAuditDelete =>
      'Delete entry and safety backup';

  @override
  String get dataGovernanceRestoreAuditDeleteConfirmTitle =>
      'Delete restore entry?';

  @override
  String dataGovernanceRestoreAuditDeleteConfirmBody(String path) {
    return 'This also deletes the linked safety backup: $path';
  }

  @override
  String get dataGovernanceRestoreAuditDeleteHistoryOnly =>
      'This entry has no linked safety backup, so only the history entry will be deleted.';

  @override
  String dataGovernanceRestoreAuditDeleteSuccess(String size) {
    return 'Restore entry deleted, freeing $size.';
  }

  @override
  String dataGovernanceRestoreAuditDeleteFailed(String error) {
    return 'Could not delete restore entry: $error';
  }

  @override
  String get dataGovernanceWipe => 'Wipe local data';

  @override
  String get dataGovernanceWipeSubtitle =>
      'Delete every transaction, budget, rule, and attachment. There is no undo.';

  @override
  String get dataGovernanceWipeAction => 'Wipe everything';

  @override
  String get dataGovernanceWipeInProgress => 'Wiping…';

  @override
  String get dataGovernanceWipeConfirmTitle => 'Wipe every byte of local data?';

  @override
  String get dataGovernanceWipeConfirmBody =>
      'This will remove every transaction, account, budget, and rule on this device. The action cannot be undone. Type DELETE to confirm.';

  @override
  String get dataGovernanceWipeConfirmHint => 'Type DELETE';

  @override
  String get dataGovernanceWipeConfirmError =>
      'Type DELETE in capital letters to confirm.';

  @override
  String get dataGovernanceWipeSuccess => 'Local data wiped. Restarting…';

  @override
  String dataGovernanceImportFailed(String error) {
    return 'Could not read the backup: $error';
  }

  @override
  String dataGovernanceBackupFailed(String error) {
    return 'Could not export the backup: $error';
  }

  @override
  String dataGovernanceWipeFailed(String error) {
    return 'Could not wipe local data: $error';
  }

  @override
  String dataGovernanceRestoreFailed(String error) {
    return 'Could not restore: $error';
  }

  @override
  String get dataGovernanceSectionBackup => 'Backup & restore';

  @override
  String get dataGovernanceSectionDanger => 'Danger zone';

  @override
  String get dataGovernanceStatusTitle => 'Last backup';

  @override
  String get dataGovernanceStatusNever => 'Never backed up';

  @override
  String dataGovernanceStatusRecent(String ago) {
    return '$ago ago';
  }

  @override
  String dataGovernanceStatusAt(String date, String time) {
    return '$date $time';
  }

  @override
  String dataGovernanceStaleBannerTitle(int days) {
    return 'Last backup is $days days old';
  }

  @override
  String get dataGovernanceStaleBannerAction => 'Back up now';

  @override
  String get dataGovernanceSelectBooks => 'Select books';

  @override
  String get dataGovernanceSelectBooksHint =>
      'Leave empty to export every book';

  @override
  String dataGovernanceExportAll(int n) {
    return 'Export all books ($n)';
  }

  @override
  String dataGovernanceExportSelected(int n) {
    return 'Export $n books';
  }

  @override
  String dataGovernanceStatusAttachments(int n, String size) {
    return '$n attachments · $size';
  }

  @override
  String dataGovernanceAttachmentSizeBytes(String size) {
    return '$size MB';
  }

  @override
  String dataGovernanceRestoreAttachmentsV2(int n) {
    return 'This restore also imports $n attachment(s).';
  }

  @override
  String get dataGovernanceRestoreNoAttachmentsV1 =>
      'This backup is schema v1 — no attachment binaries.';

  @override
  String get dataGovernanceEncryptWithPassword => 'Encrypt with password';

  @override
  String get dataGovernancePasswordHint =>
      'At least 8 characters; losing it makes the backup unrecoverable';

  @override
  String get dataGovernancePasswordConfirmHint => 'Re-enter password';

  @override
  String get dataGovernancePasswordMismatch => 'Passwords do not match';

  @override
  String get dataGovernancePasswordTooShort =>
      'Password must be at least 8 characters';

  @override
  String dataGovernanceExportEncryptedAll(int n) {
    return 'Export encrypted all books ($n)';
  }

  @override
  String dataGovernanceExportEncryptedSelected(int n) {
    return 'Export encrypted $n books';
  }

  @override
  String get dataGovernanceUnlockPrompt => 'Enter backup password';

  @override
  String get dataGovernanceUnlockWrongPassword => 'Wrong password, try again';

  @override
  String dataGovernanceUnlockLockedFor(int seconds) {
    return 'Locked, retry in ${seconds}s';
  }

  @override
  String get dataGovernanceRestoreLegacyUnencrypted =>
      'This backup is not encrypted (schema v2)';

  @override
  String get dataGovernanceRestoreLegacyUnencryptedDetail =>
      'Consider using a password-encrypted backup for sensitive financial data';

  @override
  String get dataGovernanceStatusEncrypted => 'Password protected';

  @override
  String get dataGovernanceEncryptLostPasswordWarning =>
      'If you lose the password the backup cannot be recovered';

  @override
  String get dataGovernanceIncrementalBackup => 'Incremental backup';

  @override
  String get dataGovernanceIncrementalBackupHint =>
      'Writes changes since the local base backup; keep that base file to restore';

  @override
  String get dataGovernanceIncrementalEncryptedDisabled =>
      'Incremental backups are not encrypted; encrypted export writes a full backup';

  @override
  String get dataGovernanceStatusIncremental =>
      'Incremental backup · local base required';

  @override
  String dataGovernanceLocalBackups(int count, String size) {
    return '$count local backups · $size';
  }

  @override
  String get dataGovernanceCleanupBackups => 'Clean old backups';

  @override
  String get dataGovernanceCleanupSubtitle =>
      'Manual, base, and latest backups are protected; keep the newest 3 automatic backups.';

  @override
  String get dataGovernanceArtifactListTitle => 'Backup files';

  @override
  String get dataGovernanceArtifactActions => 'Backup actions';

  @override
  String get dataGovernanceArtifactKindFull => 'Full';

  @override
  String get dataGovernanceArtifactKindIncremental => 'Incremental';

  @override
  String get dataGovernanceArtifactKindEncrypted => 'Encrypted';

  @override
  String get dataGovernanceArtifactSourceManual => 'Manual';

  @override
  String get dataGovernanceArtifactSourceAutomatic => 'Automatic';

  @override
  String get dataGovernanceArtifactSourceSafety => 'Pre-restore';

  @override
  String get dataGovernanceArtifactCurrentBase => 'Current base';

  @override
  String get dataGovernanceArtifactLatest => 'Latest';

  @override
  String get dataGovernanceArtifactShare => 'Share';

  @override
  String get dataGovernanceArtifactDrill => 'Recovery drill';

  @override
  String get dataGovernanceArtifactRotate => 'Change password';

  @override
  String get dataGovernanceArtifactRestore => 'Load into restore preview';

  @override
  String get dataGovernanceArtifactDelete => 'Delete this backup';

  @override
  String get dataGovernanceArtifactUnlockPrompt =>
      'Enter this backup\'s password';

  @override
  String get dataGovernanceArtifactRotateTitle => 'Change backup password';

  @override
  String get dataGovernanceArtifactRotateOldPassword => 'Old password';

  @override
  String get dataGovernanceArtifactRotateNewPassword => 'New password';

  @override
  String get dataGovernanceArtifactRotateConfirmPassword =>
      'Confirm new password';

  @override
  String dataGovernanceArtifactRotateSuccess(String path, String size) {
    return 'New encrypted backup created while keeping the original: $path ($size)';
  }

  @override
  String get dataGovernanceArtifactRestoreLoaded =>
      'Loaded into the restore preview. Scroll down to choose a restore mode.';

  @override
  String dataGovernanceArtifactLoadFailed(String error) {
    return 'Could not load backup: $error';
  }

  @override
  String get dataGovernanceArtifactDeleteConfirmTitle => 'Delete backup file?';

  @override
  String dataGovernanceArtifactDeleteConfirmBody(String path) {
    return 'This will delete from this device: $path';
  }

  @override
  String dataGovernanceArtifactDeleteSuccess(String size) {
    return 'Backup deleted, freeing $size.';
  }

  @override
  String dataGovernanceArtifactDeleteFailed(String error) {
    return 'Could not delete backup: $error';
  }

  @override
  String get dataGovernanceCleanupConfirmTitle =>
      'Clean old automatic backups?';

  @override
  String get dataGovernanceCleanupConfirmBody =>
      'Manual exports and the base required by incremental backups will not be deleted.';

  @override
  String dataGovernanceCleanupSuccess(int count, String size) {
    return 'Deleted $count backups and freed $size.';
  }

  @override
  String dataGovernanceCleanupPartial(int count, String size, int failed) {
    return 'Deleted $count backups and freed $size; $failed could not be deleted.';
  }

  @override
  String get dataGovernanceCleanupNoChanges =>
      'No old backups needed cleaning.';

  @override
  String dataGovernanceCleanupFailed(String error) {
    return 'Could not clean backups: $error';
  }

  @override
  String get dataGovernanceConsolidateBackup => 'Create portable full backup';

  @override
  String get dataGovernanceConsolidatePasswordTitle =>
      'Set a portable backup password';

  @override
  String get dataGovernanceConsolidatePasswordBody =>
      'You can set a password; leave it blank for an unencrypted backup.';

  @override
  String get dataGovernanceConsolidatePasswordLabel =>
      'Backup password (optional)';

  @override
  String get dataGovernanceConsolidatePasswordConfirm =>
      'Confirm backup password';

  @override
  String dataGovernanceConsolidateSuccess(String path, String size) {
    return 'Portable backup created: $path ($size)';
  }

  @override
  String get dataGovernanceConsolidateNoChanges =>
      'The latest backup is already a standalone full backup.';

  @override
  String dataGovernanceConsolidateFailed(String error) {
    return 'Could not create portable backup: $error';
  }

  @override
  String get dataGovernanceVerifyBackups => 'Check integrity';

  @override
  String get dataGovernanceVerifyNoBackups =>
      'There are no cataloged backups to verify.';

  @override
  String dataGovernanceVerifyAllHealthy(int count) {
    return 'Verified $count healthy backups.';
  }

  @override
  String get dataGovernanceVerifyIssuesTitle => 'Backup integrity issues';

  @override
  String dataGovernanceVerifyIssueSummary(
      int healthy, int missing, int corrupted) {
    return '$healthy healthy · $missing missing · $corrupted corrupted';
  }

  @override
  String get dataGovernanceVerifyMissing => 'File is missing';

  @override
  String get dataGovernanceVerifyCorrupted => 'File is corrupted';

  @override
  String dataGovernanceVerifyFailed(String error) {
    return 'Could not verify backups: $error';
  }

  @override
  String get dataGovernanceRecoveryDrill => 'Recovery drill';

  @override
  String get dataGovernanceRecoveryDrillPasswordTitle =>
      'Enter the password for the recovery drill';

  @override
  String get dataGovernanceRecoveryDrillSuccessTitle => 'Recovery drill passed';

  @override
  String dataGovernanceRecoveryDrillSuccess(
      int books, int transactions, int attachments) {
    return 'Successfully materialized or decrypted the backup: $books books, $transactions transactions, and $attachments attachments.';
  }

  @override
  String get dataGovernanceRecoveryDrillSuccessBody =>
      'The drill only reads the backup and does not modify local data.';

  @override
  String dataGovernanceRecoveryDrillPath(String path) {
    return 'Backup path: $path';
  }

  @override
  String dataGovernanceRecoveryDrillFailed(String error) {
    return 'Recovery drill failed: $error';
  }

  @override
  String get dataGovernanceHealthTitle => 'Backup policy health';

  @override
  String get dataGovernanceHealthChecking => 'Checking…';

  @override
  String get dataGovernanceHealthHealthy => 'Healthy';

  @override
  String get dataGovernanceHealthWarning => 'Needs attention';

  @override
  String get dataGovernanceHealthCritical => 'At risk';

  @override
  String get dataGovernanceHealthNoIssues =>
      'The backup policy is currently healthy.';

  @override
  String get dataGovernanceHealthRefresh => 'Check again';

  @override
  String dataGovernanceHealthSummary(int count, String nextDue) {
    return '$count local backups · Next run $nextDue';
  }

  @override
  String get dataGovernanceHealthNotScheduled => 'Not scheduled';

  @override
  String get dataGovernanceHealthIssueNoBackup =>
      'There is no local backup yet.';

  @override
  String dataGovernanceHealthIssueStale(int days) {
    return 'The latest backup is $days days old.';
  }

  @override
  String get dataGovernanceHealthIssueAutoDisabled =>
      'Automatic backup is disabled.';

  @override
  String get dataGovernanceHealthIssuePasswordMissing =>
      'Encrypted automatic backup has no usable password.';

  @override
  String get dataGovernanceHealthIssueSecureStorage =>
      'System secure storage is unavailable.';

  @override
  String get dataGovernanceHealthIssueVerificationFailed =>
      'The backup catalog integrity check failed.';

  @override
  String dataGovernanceHealthIssueMissing(int count) {
    return '$count backup files are missing.';
  }

  @override
  String dataGovernanceHealthIssueCorrupted(int count) {
    return '$count backup files are corrupted.';
  }

  @override
  String get dataGovernanceHealthIssueNotCataloged =>
      'The latest backup is not registered in the local catalog.';

  @override
  String get dataGovernanceHealthIssueLatestIncremental =>
      'The latest backup is a local-only incremental file.';

  @override
  String get dataGovernanceHealthIssueBaseMissing =>
      'The incremental base is missing from the backup catalog.';

  @override
  String get dataGovernanceHealthIssueRestoreFailed =>
      'The latest restore attempt failed; review restore history.';

  @override
  String get dataGovernanceHealthIssueExternalUnavailable =>
      'The external backup directory is unavailable.';

  @override
  String get dataGovernanceHealthIssueMirrorFailed =>
      'The latest backup has not been mirrored successfully.';

  @override
  String dataGovernanceHealthIssueMirrorMissing(int count) {
    return '$count external mirror files are missing.';
  }

  @override
  String dataGovernanceHealthIssueMirrorCorrupted(int count) {
    return '$count external mirror files are corrupted.';
  }

  @override
  String dataGovernanceHealthIssueMirrorExtra(int count) {
    return 'The external directory has $count unregistered backups.';
  }

  @override
  String get dataGovernanceHealthActionBackup => 'Back up now';

  @override
  String get dataGovernanceHealthActionEnableAuto => 'Enable automatic backup';

  @override
  String get dataGovernanceHealthActionPassword =>
      'Set automatic backup password';

  @override
  String get dataGovernanceHealthActionInspect => 'Inspect backup files';

  @override
  String get dataGovernanceHealthActionExternalDirectory =>
      'Check external backup directory';

  @override
  String get dataGovernanceHealthExportReport => 'Export governance report';

  @override
  String get dataGovernanceHealthReportJson => 'Full JSON report';

  @override
  String get dataGovernanceHealthReportCsv => 'CSV summary';

  @override
  String dataGovernanceHealthReportExported(String path) {
    return 'Governance report created: $path';
  }

  @override
  String dataGovernanceHealthReportFailed(String error) {
    return 'Could not export governance report: $error';
  }

  @override
  String get dataGovernanceAutoBackup => 'Automatic backup';

  @override
  String get dataGovernanceAutoBackupSubtitle =>
      'Checked when you open the app; writes a local snapshot when due';

  @override
  String get dataGovernanceAutoBackupWarning =>
      'Automatic backups are not encrypted. Use a password export for sensitive books.';

  @override
  String get dataGovernanceAutoEncrypt => 'Encrypt automatic backups';

  @override
  String get dataGovernanceAutoEncryptEnabled =>
      'Password stays in system secure storage; each run writes an independent encrypted full backup';

  @override
  String get dataGovernanceAutoEncryptDisabled =>
      'When off, automatic backups continue as plaintext incrementals';

  @override
  String get dataGovernanceAutoEncryptWarning =>
      'The password stays in system secure storage; losing it makes automatic backups unrecoverable.';

  @override
  String get dataGovernanceAutoEncryptPasswordTitle =>
      'Set automatic backup password';

  @override
  String get dataGovernanceAutoEncryptPasswordBody =>
      'The password is stored in system secure storage and used only for automatic backup encryption.';

  @override
  String get dataGovernanceAutoEncryptPasswordLabel =>
      'Automatic backup password';

  @override
  String get dataGovernanceAutoEncryptPasswordConfirm =>
      'Confirm automatic backup password';

  @override
  String get dataGovernanceAutoEncryptNeedsPassword =>
      'The encrypted automatic backup password is missing, so no backup was written.';

  @override
  String get dataGovernanceAutoEncryptUnavailable =>
      'System secure storage is unavailable, so no backup was written.';

  @override
  String dataGovernanceAutoEncryptFailed(String error) {
    return 'Could not save the automatic backup password: $error';
  }

  @override
  String get dataGovernanceExternalBackupDirectory =>
      'External backup directory';

  @override
  String get dataGovernanceExternalBackupNotConfigured =>
      'Not configured; backups stay only in the app directory';

  @override
  String get dataGovernanceExternalBackupChoose => 'Choose directory';

  @override
  String get dataGovernanceExternalBackupClear => 'Remove external directory';

  @override
  String get dataGovernanceExternalBackupMirrorNow => 'Mirror now';

  @override
  String get dataGovernanceExternalBackupVerify => 'Check mirror';

  @override
  String dataGovernanceExternalBackupVerifyHealthy(int count) {
    return '$count external mirror files are healthy.';
  }

  @override
  String get dataGovernanceExternalBackupVerifyIssuesTitle =>
      'External mirror issues';

  @override
  String dataGovernanceExternalBackupVerifyIssueSummary(
      int healthy, int missing, int corrupted, int extra) {
    return '$healthy healthy · $missing missing · $corrupted corrupted · $extra extra';
  }

  @override
  String get dataGovernanceExternalBackupVerifyMissing =>
      'External copy is missing';

  @override
  String get dataGovernanceExternalBackupVerifyCorrupted =>
      'External copy size or SHA-256 differs';

  @override
  String get dataGovernanceExternalBackupVerifyExtra =>
      'External file is not registered locally';

  @override
  String dataGovernanceExternalBackupVerifyFailed(String error) {
    return 'Could not verify external mirror: $error';
  }

  @override
  String get dataGovernanceExternalBackupImport => 'Import locally';

  @override
  String dataGovernanceExternalBackupImported(String backupId) {
    return 'Imported external backup: $backupId';
  }

  @override
  String dataGovernanceExternalBackupImportFailed(String error) {
    return 'Could not import external backup: $error';
  }

  @override
  String dataGovernanceExternalBackupSelected(int mirrored, int failed) {
    return 'Directory set: $mirrored mirrored, $failed failed.';
  }

  @override
  String dataGovernanceExternalBackupMirrorResult(int mirrored, int failed) {
    return 'External mirror complete: $mirrored succeeded, $failed failed.';
  }

  @override
  String dataGovernanceExternalBackupMirrorFailed(String error) {
    return 'External mirror failed: $error';
  }

  @override
  String get dataGovernanceArtifactMirrored => 'Mirrored';

  @override
  String get dataGovernanceArtifactMirrorFailed => 'Mirror failed';

  @override
  String dataGovernanceAutoIntervalDays(int n) {
    return '$n days';
  }
}
