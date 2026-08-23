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
  String get conflicts => 'Conflicts';

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
  String get amountYuan => 'Amount (yuan)';

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
}
