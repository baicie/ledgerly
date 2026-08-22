import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Ledgerly'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get confirm;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @saving.
  ///
  /// In zh, this message translates to:
  /// **'保存中'**
  String get saving;

  /// No description provided for @savingEllipsis.
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get savingEllipsis;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @create.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get create;

  /// No description provided for @unknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get unknown;

  /// No description provided for @show.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get show;

  /// No description provided for @hide.
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get hide;

  /// No description provided for @processing.
  ///
  /// In zh, this message translates to:
  /// **'处理中…'**
  String get processing;

  /// No description provided for @navFeed.
  ///
  /// In zh, this message translates to:
  /// **'流水'**
  String get navFeed;

  /// No description provided for @navAssets.
  ///
  /// In zh, this message translates to:
  /// **'资产'**
  String get navAssets;

  /// No description provided for @navReports.
  ///
  /// In zh, this message translates to:
  /// **'报表'**
  String get navReports;

  /// No description provided for @navMe.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get navMe;

  /// No description provided for @addTransaction.
  ///
  /// In zh, this message translates to:
  /// **'记一笔'**
  String get addTransaction;

  /// No description provided for @monthPickerLabel.
  ///
  /// In zh, this message translates to:
  /// **'{year}年 {month}月'**
  String monthPickerLabel(int year, int month);

  /// No description provided for @previousMonth.
  ///
  /// In zh, this message translates to:
  /// **'上个月'**
  String get previousMonth;

  /// No description provided for @nextMonth.
  ///
  /// In zh, this message translates to:
  /// **'下个月'**
  String get nextMonth;

  /// No description provided for @weekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'周一'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In zh, this message translates to:
  /// **'周二'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'周三'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In zh, this message translates to:
  /// **'周四'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'周五'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In zh, this message translates to:
  /// **'周六'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In zh, this message translates to:
  /// **'周日'**
  String get weekdaySun;

  /// No description provided for @feedDayLabel.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日 {weekday}'**
  String feedDayLabel(int month, int day, String weekday);

  /// No description provided for @fullDateLabel.
  ///
  /// In zh, this message translates to:
  /// **'{year}年{month}月{day}日'**
  String fullDateLabel(int year, int month, int day);

  /// No description provided for @insightDailyDate.
  ///
  /// In zh, this message translates to:
  /// **'{year}年{month}月{day}日'**
  String insightDailyDate(int year, int month, int day);

  /// No description provided for @insightMonthlyDate.
  ///
  /// In zh, this message translates to:
  /// **'{year}年{month}月'**
  String insightMonthlyDate(int year, int month);

  /// No description provided for @trendChartLabel.
  ///
  /// In zh, this message translates to:
  /// **'{year}年{month}月每日收支趋势图'**
  String trendChartLabel(int year, int month);

  /// No description provided for @uncategorized.
  ///
  /// In zh, this message translates to:
  /// **'未分类'**
  String get uncategorized;

  /// No description provided for @accountCash.
  ///
  /// In zh, this message translates to:
  /// **'现金'**
  String get accountCash;

  /// No description provided for @accountBank.
  ///
  /// In zh, this message translates to:
  /// **'银行卡'**
  String get accountBank;

  /// No description provided for @accountTransfer.
  ///
  /// In zh, this message translates to:
  /// **'账户转账'**
  String get accountTransfer;

  /// No description provided for @accountOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get accountOther;

  /// No description provided for @categoryFood.
  ///
  /// In zh, this message translates to:
  /// **'餐饮'**
  String get categoryFood;

  /// No description provided for @categoryMeals.
  ///
  /// In zh, this message translates to:
  /// **'日常用餐'**
  String get categoryMeals;

  /// No description provided for @categoryDrinksSnacks.
  ///
  /// In zh, this message translates to:
  /// **'饮品零食'**
  String get categoryDrinksSnacks;

  /// No description provided for @categoryTransport.
  ///
  /// In zh, this message translates to:
  /// **'交通'**
  String get categoryTransport;

  /// No description provided for @categoryPublicTransport.
  ///
  /// In zh, this message translates to:
  /// **'公交地铁'**
  String get categoryPublicTransport;

  /// No description provided for @categoryTaxi.
  ///
  /// In zh, this message translates to:
  /// **'网约车'**
  String get categoryTaxi;

  /// No description provided for @categoryCarExpenses.
  ///
  /// In zh, this message translates to:
  /// **'驾车养车'**
  String get categoryCarExpenses;

  /// No description provided for @categoryShopping.
  ///
  /// In zh, this message translates to:
  /// **'购物'**
  String get categoryShopping;

  /// No description provided for @categoryDailyEssentials.
  ///
  /// In zh, this message translates to:
  /// **'日用百货'**
  String get categoryDailyEssentials;

  /// No description provided for @categoryClothing.
  ///
  /// In zh, this message translates to:
  /// **'服饰美妆'**
  String get categoryClothing;

  /// No description provided for @categoryElectronics.
  ///
  /// In zh, this message translates to:
  /// **'数码电器'**
  String get categoryElectronics;

  /// No description provided for @categoryHousing.
  ///
  /// In zh, this message translates to:
  /// **'居住'**
  String get categoryHousing;

  /// No description provided for @categoryRentMortgage.
  ///
  /// In zh, this message translates to:
  /// **'房租房贷'**
  String get categoryRentMortgage;

  /// No description provided for @categoryUtilities.
  ///
  /// In zh, this message translates to:
  /// **'水电燃气'**
  String get categoryUtilities;

  /// No description provided for @categoryPropertyServices.
  ///
  /// In zh, this message translates to:
  /// **'物业家政'**
  String get categoryPropertyServices;

  /// No description provided for @categoryLeisure.
  ///
  /// In zh, this message translates to:
  /// **'休闲'**
  String get categoryLeisure;

  /// No description provided for @categoryEntertainment.
  ///
  /// In zh, this message translates to:
  /// **'娱乐'**
  String get categoryEntertainment;

  /// No description provided for @categoryFitness.
  ///
  /// In zh, this message translates to:
  /// **'运动健身'**
  String get categoryFitness;

  /// No description provided for @categoryTravel.
  ///
  /// In zh, this message translates to:
  /// **'旅行'**
  String get categoryTravel;

  /// No description provided for @categoryHealthcare.
  ///
  /// In zh, this message translates to:
  /// **'医疗健康'**
  String get categoryHealthcare;

  /// No description provided for @categoryMedicalCare.
  ///
  /// In zh, this message translates to:
  /// **'看病就医'**
  String get categoryMedicalCare;

  /// No description provided for @categoryMedicine.
  ///
  /// In zh, this message translates to:
  /// **'药品保健'**
  String get categoryMedicine;

  /// No description provided for @categoryEducation.
  ///
  /// In zh, this message translates to:
  /// **'学习'**
  String get categoryEducation;

  /// No description provided for @categoryBooks.
  ///
  /// In zh, this message translates to:
  /// **'书籍'**
  String get categoryBooks;

  /// No description provided for @categoryCourses.
  ///
  /// In zh, this message translates to:
  /// **'课程培训'**
  String get categoryCourses;

  /// No description provided for @categoryOtherExpense.
  ///
  /// In zh, this message translates to:
  /// **'其他支出'**
  String get categoryOtherExpense;

  /// No description provided for @categorySalary.
  ///
  /// In zh, this message translates to:
  /// **'工资收入'**
  String get categorySalary;

  /// No description provided for @categoryBaseSalary.
  ///
  /// In zh, this message translates to:
  /// **'基本工资'**
  String get categoryBaseSalary;

  /// No description provided for @categoryBonus.
  ///
  /// In zh, this message translates to:
  /// **'奖金'**
  String get categoryBonus;

  /// No description provided for @categorySideIncome.
  ///
  /// In zh, this message translates to:
  /// **'副业收入'**
  String get categorySideIncome;

  /// No description provided for @categoryFreelance.
  ///
  /// In zh, this message translates to:
  /// **'自由职业'**
  String get categoryFreelance;

  /// No description provided for @categoryBusinessIncome.
  ///
  /// In zh, this message translates to:
  /// **'经营收入'**
  String get categoryBusinessIncome;

  /// No description provided for @categoryInvestmentIncome.
  ///
  /// In zh, this message translates to:
  /// **'投资收益'**
  String get categoryInvestmentIncome;

  /// No description provided for @categoryInterest.
  ///
  /// In zh, this message translates to:
  /// **'利息'**
  String get categoryInterest;

  /// No description provided for @categoryDividends.
  ///
  /// In zh, this message translates to:
  /// **'分红'**
  String get categoryDividends;

  /// No description provided for @categoryOtherIncome.
  ///
  /// In zh, this message translates to:
  /// **'其他收入'**
  String get categoryOtherIncome;

  /// No description provided for @assetAccounts.
  ///
  /// In zh, this message translates to:
  /// **'资产账户'**
  String get assetAccounts;

  /// No description provided for @accountsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个账户 · 人民币 CNY'**
  String accountsSubtitle(int count);

  /// No description provided for @newAccount.
  ///
  /// In zh, this message translates to:
  /// **'新建账户'**
  String get newAccount;

  /// No description provided for @standardLedger.
  ///
  /// In zh, this message translates to:
  /// **'标准账本'**
  String get standardLedger;

  /// No description provided for @netWorth.
  ///
  /// In zh, this message translates to:
  /// **'净资产'**
  String get netWorth;

  /// No description provided for @accountDetails.
  ///
  /// In zh, this message translates to:
  /// **'账户明细'**
  String get accountDetails;

  /// No description provided for @totalWithAmount.
  ///
  /// In zh, this message translates to:
  /// **'合计 {amount}'**
  String totalWithAmount(String amount);

  /// No description provided for @noAssetAccounts.
  ///
  /// In zh, this message translates to:
  /// **'还没有资产账户'**
  String get noAssetAccounts;

  /// No description provided for @noAssetAccountsHint.
  ///
  /// In zh, this message translates to:
  /// **'新建现金、银行卡或其他资产账户。'**
  String get noAssetAccountsHint;

  /// No description provided for @accountsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'账户加载失败：{error}'**
  String accountsLoadFailed(String error);

  /// No description provided for @newAccountName.
  ///
  /// In zh, this message translates to:
  /// **'新账户'**
  String get newAccountName;

  /// No description provided for @newAssetAccount.
  ///
  /// In zh, this message translates to:
  /// **'新建资产账户'**
  String get newAssetAccount;

  /// No description provided for @accountName.
  ///
  /// In zh, this message translates to:
  /// **'账户名称'**
  String get accountName;

  /// No description provided for @liabilityAccount.
  ///
  /// In zh, this message translates to:
  /// **'负债账户'**
  String get liabilityAccount;

  /// No description provided for @assetAccount.
  ///
  /// In zh, this message translates to:
  /// **'资产账户'**
  String get assetAccount;

  /// No description provided for @allTransactions.
  ///
  /// In zh, this message translates to:
  /// **'全部流水'**
  String get allTransactions;

  /// No description provided for @monthlyFeedStats.
  ///
  /// In zh, this message translates to:
  /// **'本月流水统计'**
  String get monthlyFeedStats;

  /// No description provided for @feedLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'流水加载失败：{error}'**
  String feedLoadFailed(String error);

  /// No description provided for @insightLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'分析加载失败：{error}'**
  String insightLoadFailed(String error);

  /// No description provided for @emptyMonthTitle.
  ///
  /// In zh, this message translates to:
  /// **'这个月还没有流水'**
  String get emptyMonthTitle;

  /// No description provided for @emptyMonthMessage.
  ///
  /// In zh, this message translates to:
  /// **'点击底部的 +，记下第一笔收支。'**
  String get emptyMonthMessage;

  /// No description provided for @dayNet.
  ///
  /// In zh, this message translates to:
  /// **'当日净额'**
  String get dayNet;

  /// No description provided for @deleteTransaction.
  ///
  /// In zh, this message translates to:
  /// **'删除流水'**
  String get deleteTransaction;

  /// No description provided for @monthlyInsightEntryTitle.
  ///
  /// In zh, this message translates to:
  /// **'每月分析'**
  String get monthlyInsightEntryTitle;

  /// No description provided for @monthlyInsightEntrySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在报表页查看所选月份的 AI 月报'**
  String get monthlyInsightEntrySubtitle;

  /// No description provided for @reportsTitle.
  ///
  /// In zh, this message translates to:
  /// **'报表'**
  String get reportsTitle;

  /// No description provided for @localShort.
  ///
  /// In zh, this message translates to:
  /// **'本地'**
  String get localShort;

  /// No description provided for @syncedShort.
  ///
  /// In zh, this message translates to:
  /// **'已同步'**
  String get syncedShort;

  /// No description provided for @refreshRemoteSummary.
  ///
  /// In zh, this message translates to:
  /// **'刷新服务端汇总'**
  String get refreshRemoteSummary;

  /// No description provided for @monthlyFlowStats.
  ///
  /// In zh, this message translates to:
  /// **'本月收支统计'**
  String get monthlyFlowStats;

  /// No description provided for @incomeSources.
  ///
  /// In zh, this message translates to:
  /// **'收入来源'**
  String get incomeSources;

  /// No description provided for @noIncomeThisMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月暂无收入'**
  String get noIncomeThisMonth;

  /// No description provided for @expenseBreakdown.
  ///
  /// In zh, this message translates to:
  /// **'支出分布'**
  String get expenseBreakdown;

  /// No description provided for @noExpenseThisMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月暂无支出'**
  String get noExpenseThisMonth;

  /// No description provided for @monthlyTrend.
  ///
  /// In zh, this message translates to:
  /// **'月度趋势'**
  String get monthlyTrend;

  /// No description provided for @transactionCountLabel.
  ///
  /// In zh, this message translates to:
  /// **'{count} 笔'**
  String transactionCountLabel(int count);

  /// No description provided for @rankingTrailing.
  ///
  /// In zh, this message translates to:
  /// **'{count} 笔 · {amount}'**
  String rankingTrailing(int count, String amount);

  /// No description provided for @cloudCheck.
  ///
  /// In zh, this message translates to:
  /// **'云端校验'**
  String get cloudCheck;

  /// No description provided for @remoteNet.
  ///
  /// In zh, this message translates to:
  /// **'服务端净额 {net} · {currency}'**
  String remoteNet(String net, String currency);

  /// No description provided for @reportsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'报表加载失败：{error}'**
  String reportsLoadFailed(String error);

  /// No description provided for @thisMonthBalance.
  ///
  /// In zh, this message translates to:
  /// **'本月结余'**
  String get thisMonthBalance;

  /// No description provided for @incomeAmount.
  ///
  /// In zh, this message translates to:
  /// **'收入 {amount}'**
  String incomeAmount(String amount);

  /// No description provided for @expenseAmount.
  ///
  /// In zh, this message translates to:
  /// **'支出 {amount}'**
  String expenseAmount(String amount);

  /// No description provided for @income.
  ///
  /// In zh, this message translates to:
  /// **'收入'**
  String get income;

  /// No description provided for @expense.
  ///
  /// In zh, this message translates to:
  /// **'支出'**
  String get expense;

  /// No description provided for @transfer.
  ///
  /// In zh, this message translates to:
  /// **'转账'**
  String get transfer;

  /// No description provided for @insightKindDaily.
  ///
  /// In zh, this message translates to:
  /// **'日分析'**
  String get insightKindDaily;

  /// No description provided for @insightKindMonthly.
  ///
  /// In zh, this message translates to:
  /// **'月报'**
  String get insightKindMonthly;

  /// No description provided for @aiInsightTitleWithPeriod.
  ///
  /// In zh, this message translates to:
  /// **'AI {kind} · {period}'**
  String aiInsightTitleWithPeriod(String kind, String period);

  /// No description provided for @aiInsightTitleKindOnly.
  ///
  /// In zh, this message translates to:
  /// **'AI {kind}'**
  String aiInsightTitleKindOnly(String kind);

  /// No description provided for @goConfigure.
  ///
  /// In zh, this message translates to:
  /// **'去配置'**
  String get goConfigure;

  /// No description provided for @regenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get regenerate;

  /// No description provided for @generate.
  ///
  /// In zh, this message translates to:
  /// **'生成'**
  String get generate;

  /// No description provided for @insightUnconfiguredDaily.
  ///
  /// In zh, this message translates to:
  /// **'配置模型供应商和 API Key 后，可在当天流水里自动生成每日消费总结。当前接入的文本模型不支持语音转文字。'**
  String get insightUnconfiguredDaily;

  /// No description provided for @insightUnconfiguredMonthly.
  ///
  /// In zh, this message translates to:
  /// **'配置模型供应商和 API Key 后，可自动生成所选月份的消费月报，并在新月补齐上月月报。当前接入的文本模型不支持语音转文字。'**
  String get insightUnconfiguredMonthly;

  /// No description provided for @insightNotGenerated.
  ///
  /// In zh, this message translates to:
  /// **'尚未生成分析'**
  String get insightNotGenerated;

  /// No description provided for @insightEmptyDaily.
  ///
  /// In zh, this message translates to:
  /// **'当日暂无消费'**
  String get insightEmptyDaily;

  /// No description provided for @insightEmptyMonthly.
  ///
  /// In zh, this message translates to:
  /// **'当月暂无消费'**
  String get insightEmptyMonthly;

  /// No description provided for @insightEmptyNoModel.
  ///
  /// In zh, this message translates to:
  /// **'暂无消费，未调用模型。'**
  String get insightEmptyNoModel;

  /// No description provided for @insightFailed.
  ///
  /// In zh, this message translates to:
  /// **'分析失败'**
  String get insightFailed;

  /// No description provided for @insightStale.
  ///
  /// In zh, this message translates to:
  /// **'账目已更新，可重新生成。'**
  String get insightStale;

  /// No description provided for @insightFallbackHeadline.
  ///
  /// In zh, this message translates to:
  /// **'消费总结'**
  String get insightFallbackHeadline;

  /// No description provided for @tokenUsage.
  ///
  /// In zh, this message translates to:
  /// **'{model} · 入 {prompt} / 出 {completion} tokens'**
  String tokenUsage(String model, String prompt, String completion);

  /// No description provided for @aiSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'智能分析'**
  String get aiSettingsTitle;

  /// No description provided for @modelService.
  ///
  /// In zh, this message translates to:
  /// **'模型服务'**
  String get modelService;

  /// No description provided for @provider.
  ///
  /// In zh, this message translates to:
  /// **'供应商'**
  String get provider;

  /// No description provided for @aiProviderCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义兼容接口'**
  String get aiProviderCustom;

  /// No description provided for @model.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get model;

  /// No description provided for @custom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get custom;

  /// No description provided for @customModelId.
  ///
  /// In zh, this message translates to:
  /// **'自定义模型 ID'**
  String get customModelId;

  /// No description provided for @autoGenerateInsights.
  ///
  /// In zh, this message translates to:
  /// **'自动生成分析'**
  String get autoGenerateInsights;

  /// No description provided for @autoGenerateInsightsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'打开应用时补齐今日、昨日和上月总结'**
  String get autoGenerateInsightsSubtitle;

  /// No description provided for @testingConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试中…'**
  String get testingConnection;

  /// No description provided for @testConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get testConnection;

  /// No description provided for @capabilitiesAndUsage.
  ///
  /// In zh, this message translates to:
  /// **'能力与用量'**
  String get capabilitiesAndUsage;

  /// No description provided for @aiSavedLocally.
  ///
  /// In zh, this message translates to:
  /// **'已保存。密钥只留在本机，不会同步到账本服务。'**
  String get aiSavedLocally;

  /// No description provided for @saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String saveFailed(String error);

  /// No description provided for @enterApiKeyFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先填写 API Key。'**
  String get enterApiKeyFirst;

  /// No description provided for @connectionSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接成功。'**
  String get connectionSuccess;

  /// No description provided for @aiCapabilityProtocol.
  ///
  /// In zh, this message translates to:
  /// **'当前走 OpenAI 兼容的 Chat Completions。分析模型不能语音转文字。分析会把分类、金额和备注发送到你配置的端点。'**
  String get aiCapabilityProtocol;

  /// No description provided for @aiCapabilityOpencode.
  ///
  /// In zh, this message translates to:
  /// **'OpenCode 使用 Zen Go 网关 https://opencode.ai/zen/go/v1。网页浏览器会拦截跨域请求，测试连接在网页里会失败；请保存后用 App。预设仅包含 Chat Completions 模型，GPT / Claude 本期不接。'**
  String get aiCapabilityOpencode;

  /// No description provided for @aiCapabilityUsage.
  ///
  /// In zh, this message translates to:
  /// **'第一期不做累计用量看板，{hint}分析卡片会显示最近一次调用的 token。'**
  String aiCapabilityUsage(String hint);

  /// No description provided for @aiUsageHintDeepseek.
  ///
  /// In zh, this message translates to:
  /// **'余额请到 DeepSeek 控制台查看。'**
  String get aiUsageHintDeepseek;

  /// No description provided for @aiUsageHintOpencode.
  ///
  /// In zh, this message translates to:
  /// **'密钥和余额请到 OpenCode 控制台查看。网页浏览器无法直连该接口（无 CORS），请在 App 中使用。'**
  String get aiUsageHintOpencode;

  /// No description provided for @aiUsageHintCustom.
  ///
  /// In zh, this message translates to:
  /// **'用量请到你使用的供应商控制台查看。'**
  String get aiUsageHintCustom;

  /// No description provided for @invalidHttpUrl.
  ///
  /// In zh, this message translates to:
  /// **'请输入 http(s) 地址'**
  String get invalidHttpUrl;

  /// No description provided for @urlMustNotIncludeCredentials.
  ///
  /// In zh, this message translates to:
  /// **'地址不能包含账号密码'**
  String get urlMustNotIncludeCredentials;

  /// No description provided for @cannotSaveApiKey.
  ///
  /// In zh, this message translates to:
  /// **'无法保存 API Key。'**
  String get cannotSaveApiKey;

  /// No description provided for @cannotSaveModelSettings.
  ///
  /// In zh, this message translates to:
  /// **'无法保存模型设置。'**
  String get cannotSaveModelSettings;

  /// No description provided for @modelReturnedEmpty.
  ///
  /// In zh, this message translates to:
  /// **'模型没有返回可用内容。'**
  String get modelReturnedEmpty;

  /// No description provided for @invalidApiKey.
  ///
  /// In zh, this message translates to:
  /// **'API Key 无效，请检查设置。'**
  String get invalidApiKey;

  /// No description provided for @modelBalanceLow.
  ///
  /// In zh, this message translates to:
  /// **'模型账户余额不足。'**
  String get modelBalanceLow;

  /// No description provided for @tooManyRequests.
  ///
  /// In zh, this message translates to:
  /// **'请求过于频繁，请稍后再试。'**
  String get tooManyRequests;

  /// No description provided for @corsBlockedOpencode.
  ///
  /// In zh, this message translates to:
  /// **'浏览器拦截了跨域请求。OpenCode 官方接口不允许网页直连，请保存后在 App 中使用，或改用带 CORS 的兼容网关。'**
  String get corsBlockedOpencode;

  /// No description provided for @cannotReachModelWeb.
  ///
  /// In zh, this message translates to:
  /// **'无法连接模型服务。网页端可能被跨域拦截，请改用 App 或兼容端点。'**
  String get cannotReachModelWeb;

  /// No description provided for @cannotReachModel.
  ///
  /// In zh, this message translates to:
  /// **'无法连接模型服务，请检查网络和 Base URL。'**
  String get cannotReachModel;

  /// No description provided for @modelTimeout.
  ///
  /// In zh, this message translates to:
  /// **'模型服务超时，请稍后重试。'**
  String get modelTimeout;

  /// No description provided for @modelCallFailed.
  ///
  /// In zh, this message translates to:
  /// **'模型调用失败。'**
  String get modelCallFailed;

  /// No description provided for @modelCallFailedWithStatus.
  ///
  /// In zh, this message translates to:
  /// **'模型调用失败（{status}）。'**
  String modelCallFailedWithStatus(int status);

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitleLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地模式 · 数据保存在当前设备'**
  String get settingsSubtitleLocal;

  /// No description provided for @settingsSubtitleRemote.
  ///
  /// In zh, this message translates to:
  /// **'已连接服务 · 自动同步账本数据'**
  String get settingsSubtitleRemote;

  /// No description provided for @dataAndSync.
  ///
  /// In zh, this message translates to:
  /// **'数据与同步'**
  String get dataAndSync;

  /// No description provided for @apiService.
  ///
  /// In zh, this message translates to:
  /// **'API 服务'**
  String get apiService;

  /// No description provided for @syncCenter.
  ///
  /// In zh, this message translates to:
  /// **'同步中心'**
  String get syncCenter;

  /// No description provided for @syncCenterSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看待同步与最近状态'**
  String get syncCenterSubtitle;

  /// No description provided for @conflicts.
  ///
  /// In zh, this message translates to:
  /// **'冲突处理'**
  String get conflicts;

  /// No description provided for @exportCsv.
  ///
  /// In zh, this message translates to:
  /// **'导出 CSV'**
  String get exportCsv;

  /// No description provided for @exportCsvSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'备份当前账本数据'**
  String get exportCsvSubtitle;

  /// No description provided for @ledgerSection.
  ///
  /// In zh, this message translates to:
  /// **'账本'**
  String get ledgerSection;

  /// No description provided for @categoryManagement.
  ///
  /// In zh, this message translates to:
  /// **'分类管理'**
  String get categoryManagement;

  /// No description provided for @categoryManagementSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'维护支出与收入分类'**
  String get categoryManagementSubtitle;

  /// No description provided for @budgetTargets.
  ///
  /// In zh, this message translates to:
  /// **'预算目标'**
  String get budgetTargets;

  /// No description provided for @budgetTargetsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'设置每月支出上限与进度'**
  String get budgetTargetsSubtitle;

  /// No description provided for @smartInsights.
  ///
  /// In zh, this message translates to:
  /// **'智能分析'**
  String get smartInsights;

  /// No description provided for @aiSpendInsights.
  ///
  /// In zh, this message translates to:
  /// **'AI 消费总结'**
  String get aiSpendInsights;

  /// No description provided for @aiSpendInsightsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'供应商、密钥、模型与自动分析'**
  String get aiSpendInsightsSubtitle;

  /// No description provided for @accountSection.
  ///
  /// In zh, this message translates to:
  /// **'账户'**
  String get accountSection;

  /// No description provided for @logOut.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logOut;

  /// No description provided for @switchToLocalTitle.
  ///
  /// In zh, this message translates to:
  /// **'改为仅本地存储？'**
  String get switchToLocalTitle;

  /// No description provided for @connectApiTitle.
  ///
  /// In zh, this message translates to:
  /// **'连接 API 服务？'**
  String get connectApiTitle;

  /// No description provided for @switchApiTitle.
  ///
  /// In zh, this message translates to:
  /// **'切换 API 服务？'**
  String get switchApiTitle;

  /// No description provided for @switchToLocalBody.
  ///
  /// In zh, this message translates to:
  /// **'远端登录会退出，本机账本数据会保留。'**
  String get switchToLocalBody;

  /// No description provided for @connectApiBody.
  ///
  /// In zh, this message translates to:
  /// **'连接后需要登录服务，本机账本数据会保留。'**
  String get connectApiBody;

  /// No description provided for @localOnlyStorage.
  ///
  /// In zh, this message translates to:
  /// **'仅本地存储'**
  String get localOnlyStorage;

  /// No description provided for @confirmConnect.
  ///
  /// In zh, this message translates to:
  /// **'确认连接'**
  String get confirmConnect;

  /// No description provided for @apiSettingsSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'API 设置保存失败，仍保持原存储模式。'**
  String get apiSettingsSaveFailed;

  /// No description provided for @confirmLogoutTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认退出登录？'**
  String get confirmLogoutTitle;

  /// No description provided for @confirmLogoutBody.
  ///
  /// In zh, this message translates to:
  /// **'本机账本数据会保留，下次登录后可继续使用。'**
  String get confirmLogoutBody;

  /// No description provided for @endpointUnsetLocal.
  ///
  /// In zh, this message translates to:
  /// **'未设置（仅本地存储）'**
  String get endpointUnsetLocal;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @register.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get register;

  /// No description provided for @email.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get email;

  /// No description provided for @emailTooLong.
  ///
  /// In zh, this message translates to:
  /// **'邮箱不能超过 254 个字符'**
  String get emailTooLong;

  /// No description provided for @invalidEmail.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效邮箱'**
  String get invalidEmail;

  /// No description provided for @displayName.
  ///
  /// In zh, this message translates to:
  /// **'称呼'**
  String get displayName;

  /// No description provided for @enterDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'请输入称呼'**
  String get enterDisplayName;

  /// No description provided for @displayNameTooLong.
  ///
  /// In zh, this message translates to:
  /// **'称呼不能超过 80 个字符'**
  String get displayNameTooLong;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get password;

  /// No description provided for @showPassword.
  ///
  /// In zh, this message translates to:
  /// **'显示密码'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In zh, this message translates to:
  /// **'隐藏密码'**
  String get hidePassword;

  /// No description provided for @passwordTooShort.
  ///
  /// In zh, this message translates to:
  /// **'密码至少 8 位'**
  String get passwordTooShort;

  /// No description provided for @passwordTooLong.
  ///
  /// In zh, this message translates to:
  /// **'密码不能超过 128 位'**
  String get passwordTooLong;

  /// No description provided for @registerAndContinue.
  ///
  /// In zh, this message translates to:
  /// **'注册并继续'**
  String get registerAndContinue;

  /// No description provided for @changeApiService.
  ///
  /// In zh, this message translates to:
  /// **'更换 API 服务'**
  String get changeApiService;

  /// No description provided for @apiAddressSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'API 地址保存失败，请稍后重试。'**
  String get apiAddressSaveFailed;

  /// No description provided for @restoreSessionFailed.
  ///
  /// In zh, this message translates to:
  /// **'会话恢复失败。'**
  String get restoreSessionFailed;

  /// No description provided for @restoreSessionFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'恢复会话失败，请稍后重试。'**
  String get restoreSessionFailedRetry;

  /// No description provided for @loginFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'登录失败，请稍后重试。'**
  String get loginFailedRetry;

  /// No description provided for @registerFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'注册失败，请稍后重试。'**
  String get registerFailedRetry;

  /// No description provided for @logoutRemoteRevokeFailed.
  ///
  /// In zh, this message translates to:
  /// **'已清除本机登录状态，但服务器会话撤销失败。'**
  String get logoutRemoteRevokeFailed;

  /// No description provided for @sessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录状态已失效，请重新登录。'**
  String get sessionExpired;

  /// No description provided for @invalidCredentials.
  ///
  /// In zh, this message translates to:
  /// **'邮箱或密码错误。'**
  String get invalidCredentials;

  /// No description provided for @emailTaken.
  ///
  /// In zh, this message translates to:
  /// **'该邮箱已注册。'**
  String get emailTaken;

  /// No description provided for @weakPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码需为 8–128 位。'**
  String get weakPassword;

  /// No description provided for @cannotReachServer.
  ///
  /// In zh, this message translates to:
  /// **'无法连接服务器，请检查网络后重试。'**
  String get cannotReachServer;

  /// No description provided for @cannotReadSavedApi.
  ///
  /// In zh, this message translates to:
  /// **'无法读取已保存的 API 地址，请重新设置。'**
  String get cannotReadSavedApi;

  /// No description provided for @apiEndpointSetupTitle.
  ///
  /// In zh, this message translates to:
  /// **'API 服务配置'**
  String get apiEndpointSetupTitle;

  /// No description provided for @apiEndpointSetupSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'地址选填，留空时仅在本机存储'**
  String get apiEndpointSetupSubtitle;

  /// No description provided for @apiAddressOptional.
  ///
  /// In zh, this message translates to:
  /// **'API 地址（选填）'**
  String get apiAddressOptional;

  /// No description provided for @apiAddressHelper.
  ///
  /// In zh, this message translates to:
  /// **'原生端支持局域网 IP；留空则仅本地存储'**
  String get apiAddressHelper;

  /// No description provided for @saveSettings.
  ///
  /// In zh, this message translates to:
  /// **'保存设置'**
  String get saveSettings;

  /// No description provided for @requireHttpsLanOk.
  ///
  /// In zh, this message translates to:
  /// **'请使用 HTTPS；原生客户端也支持局域网 IP 地址'**
  String get requireHttpsLanOk;

  /// No description provided for @webReleaseHttps443.
  ///
  /// In zh, this message translates to:
  /// **'Web 正式版本仅支持 HTTPS 默认端口（443）'**
  String get webReleaseHttps443;

  /// No description provided for @apiOriginOnly.
  ///
  /// In zh, this message translates to:
  /// **'请输入不含路径、查询或凭据的 API 根地址'**
  String get apiOriginOnly;

  /// No description provided for @enterApiAddress.
  ///
  /// In zh, this message translates to:
  /// **'请输入 API 地址'**
  String get enterApiAddress;

  /// No description provided for @invalidHttpApiAddress.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的 HTTP(S) API 地址'**
  String get invalidHttpApiAddress;

  /// No description provided for @newCategory.
  ///
  /// In zh, this message translates to:
  /// **'新建分类'**
  String get newCategory;

  /// No description provided for @categoryTypeHeading.
  ///
  /// In zh, this message translates to:
  /// **'{type}分类'**
  String categoryTypeHeading(String type);

  /// No description provided for @categoryLevelCounts.
  ///
  /// In zh, this message translates to:
  /// **'{roots} 个一级 · {seconds} 个二级'**
  String categoryLevelCounts(int roots, int seconds);

  /// No description provided for @noCategoriesOfType.
  ///
  /// In zh, this message translates to:
  /// **'还没有{type}分类'**
  String noCategoriesOfType(String type);

  /// No description provided for @noCategoriesHint.
  ///
  /// In zh, this message translates to:
  /// **'新建一级分类后即可继续添加二级分类。'**
  String get noCategoriesHint;

  /// No description provided for @categoriesLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'分类加载失败'**
  String get categoriesLoadFailed;

  /// No description provided for @noSecondLevelCategories.
  ///
  /// In zh, this message translates to:
  /// **'暂无二级分类'**
  String get noSecondLevelCategories;

  /// No description provided for @secondLevelCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个二级分类'**
  String secondLevelCount(int count);

  /// No description provided for @addChildCategoryUnder.
  ///
  /// In zh, this message translates to:
  /// **'在{name}下新增二级分类'**
  String addChildCategoryUnder(String name);

  /// No description provided for @editNamedCategory.
  ///
  /// In zh, this message translates to:
  /// **'编辑{name}'**
  String editNamedCategory(String name);

  /// No description provided for @secondLevelCategory.
  ///
  /// In zh, this message translates to:
  /// **'二级分类'**
  String get secondLevelCategory;

  /// No description provided for @firstLevelCategory.
  ///
  /// In zh, this message translates to:
  /// **'一级分类'**
  String get firstLevelCategory;

  /// No description provided for @needParentCategoryFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先新建一个同类型的一级分类'**
  String get needParentCategoryFirst;

  /// No description provided for @categorySaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'分类保存失败，请稍后重试'**
  String get categorySaveFailed;

  /// No description provided for @editCategory.
  ///
  /// In zh, this message translates to:
  /// **'编辑分类'**
  String get editCategory;

  /// No description provided for @categoryInfo.
  ///
  /// In zh, this message translates to:
  /// **'分类信息'**
  String get categoryInfo;

  /// No description provided for @categoryName.
  ///
  /// In zh, this message translates to:
  /// **'分类名称'**
  String get categoryName;

  /// No description provided for @flowType.
  ///
  /// In zh, this message translates to:
  /// **'收支类型'**
  String get flowType;

  /// No description provided for @categoryLevel.
  ///
  /// In zh, this message translates to:
  /// **'分类级别'**
  String get categoryLevel;

  /// No description provided for @parentCategory.
  ///
  /// In zh, this message translates to:
  /// **'上级分类'**
  String get parentCategory;

  /// No description provided for @categoryHasChildrenKeepRoot.
  ///
  /// In zh, this message translates to:
  /// **'该分类包含二级分类，级别保持为一级。'**
  String get categoryHasChildrenKeepRoot;

  /// No description provided for @categoryNotFound.
  ///
  /// In zh, this message translates to:
  /// **'分类不存在'**
  String get categoryNotFound;

  /// No description provided for @cannotNestRootWithChildren.
  ///
  /// In zh, this message translates to:
  /// **'包含二级分类的一级分类不能改为二级'**
  String get cannotNestRootWithChildren;

  /// No description provided for @enterCategoryName.
  ///
  /// In zh, this message translates to:
  /// **'请输入分类名称'**
  String get enterCategoryName;

  /// No description provided for @categoryNameTooLong.
  ///
  /// In zh, this message translates to:
  /// **'分类名称不能超过 24 个字符'**
  String get categoryNameTooLong;

  /// No description provided for @invalidCategoryType.
  ///
  /// In zh, this message translates to:
  /// **'分类类型无效'**
  String get invalidCategoryType;

  /// No description provided for @categoryCannotBeOwnParent.
  ///
  /// In zh, this message translates to:
  /// **'分类不能作为自己的上级分类'**
  String get categoryCannotBeOwnParent;

  /// No description provided for @chooseSameTypeParent.
  ///
  /// In zh, this message translates to:
  /// **'请选择同类型的一级分类'**
  String get chooseSameTypeParent;

  /// No description provided for @categoryMaxTwoLevels.
  ///
  /// In zh, this message translates to:
  /// **'分类最多只能分为两级'**
  String get categoryMaxTwoLevels;

  /// No description provided for @duplicateCategoryName.
  ///
  /// In zh, this message translates to:
  /// **'同类型下已存在该分类'**
  String get duplicateCategoryName;

  /// No description provided for @editTransaction.
  ///
  /// In zh, this message translates to:
  /// **'编辑流水'**
  String get editTransaction;

  /// No description provided for @date.
  ///
  /// In zh, this message translates to:
  /// **'日期'**
  String get date;

  /// No description provided for @category.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get category;

  /// No description provided for @fromAccount.
  ///
  /// In zh, this message translates to:
  /// **'转出账户'**
  String get fromAccount;

  /// No description provided for @account.
  ///
  /// In zh, this message translates to:
  /// **'账户'**
  String get account;

  /// No description provided for @toAccount.
  ///
  /// In zh, this message translates to:
  /// **'转入账户'**
  String get toAccount;

  /// No description provided for @noteOptional.
  ///
  /// In zh, this message translates to:
  /// **'添加备注（可选）'**
  String get noteOptional;

  /// No description provided for @expenseAmountLabel.
  ///
  /// In zh, this message translates to:
  /// **'支出金额'**
  String get expenseAmountLabel;

  /// No description provided for @incomeAmountLabel.
  ///
  /// In zh, this message translates to:
  /// **'收入金额'**
  String get incomeAmountLabel;

  /// No description provided for @transferAmountLabel.
  ///
  /// In zh, this message translates to:
  /// **'转账金额'**
  String get transferAmountLabel;

  /// No description provided for @updateExpense.
  ///
  /// In zh, this message translates to:
  /// **'更新支出'**
  String get updateExpense;

  /// No description provided for @saveExpense.
  ///
  /// In zh, this message translates to:
  /// **'保存支出'**
  String get saveExpense;

  /// No description provided for @updateIncome.
  ///
  /// In zh, this message translates to:
  /// **'更新收入'**
  String get updateIncome;

  /// No description provided for @saveIncome.
  ///
  /// In zh, this message translates to:
  /// **'保存收入'**
  String get saveIncome;

  /// No description provided for @updateTransfer.
  ///
  /// In zh, this message translates to:
  /// **'更新转账'**
  String get updateTransfer;

  /// No description provided for @saveTransfer.
  ///
  /// In zh, this message translates to:
  /// **'保存转账'**
  String get saveTransfer;

  /// No description provided for @pickIncomeCategory.
  ///
  /// In zh, this message translates to:
  /// **'选择收入分类'**
  String get pickIncomeCategory;

  /// No description provided for @pickExpenseCategory.
  ///
  /// In zh, this message translates to:
  /// **'选择支出分类'**
  String get pickExpenseCategory;

  /// No description provided for @pickDate.
  ///
  /// In zh, this message translates to:
  /// **'选择日期'**
  String get pickDate;

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get ok;

  /// No description provided for @pickFromAccount.
  ///
  /// In zh, this message translates to:
  /// **'选择转出账户'**
  String get pickFromAccount;

  /// No description provided for @pickAccount.
  ///
  /// In zh, this message translates to:
  /// **'选择账户'**
  String get pickAccount;

  /// No description provided for @pickToAccount.
  ///
  /// In zh, this message translates to:
  /// **'选择转入账户'**
  String get pickToAccount;

  /// No description provided for @enterPositiveAmount.
  ///
  /// In zh, this message translates to:
  /// **'请输入大于 0 的金额'**
  String get enterPositiveAmount;

  /// No description provided for @missingCategoryOrAccount.
  ///
  /// In zh, this message translates to:
  /// **'当前账本缺少可用的分类或账户'**
  String get missingCategoryOrAccount;

  /// No description provided for @transferAccountsMustDiffer.
  ///
  /// In zh, this message translates to:
  /// **'转出账户和转入账户不能相同'**
  String get transferAccountsMustDiffer;

  /// No description provided for @finishEditing.
  ///
  /// In zh, this message translates to:
  /// **'完成编辑'**
  String get finishEditing;

  /// No description provided for @editCategoryAction.
  ///
  /// In zh, this message translates to:
  /// **'编辑分类'**
  String get editCategoryAction;

  /// No description provided for @noCategories.
  ///
  /// In zh, this message translates to:
  /// **'暂无分类'**
  String get noCategories;

  /// No description provided for @noAccounts.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用账户'**
  String get noAccounts;

  /// No description provided for @addCategory.
  ///
  /// In zh, this message translates to:
  /// **'新增分类'**
  String get addCategory;

  /// No description provided for @parentSecondLevel.
  ///
  /// In zh, this message translates to:
  /// **'{parent} · 二级分类'**
  String parentSecondLevel(String parent);

  /// No description provided for @editNamed.
  ///
  /// In zh, this message translates to:
  /// **'编辑{name}'**
  String editNamed(String name);

  /// No description provided for @selectNamed.
  ///
  /// In zh, this message translates to:
  /// **'选择{name}'**
  String selectNamed(String name);

  /// No description provided for @backspace.
  ///
  /// In zh, this message translates to:
  /// **'退格'**
  String get backspace;

  /// No description provided for @decimalPoint.
  ///
  /// In zh, this message translates to:
  /// **'小数点'**
  String get decimalPoint;

  /// No description provided for @notSignedInBudgets.
  ///
  /// In zh, this message translates to:
  /// **'尚未登录同步，无法加载预算目标'**
  String get notSignedInBudgets;

  /// No description provided for @createExpenseCategoryFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先创建一个支出分类，再设置预算目标'**
  String get createExpenseCategoryFirst;

  /// No description provided for @notSignedInCreateBudget.
  ///
  /// In zh, this message translates to:
  /// **'尚未登录同步，无法创建预算目标'**
  String get notSignedInCreateBudget;

  /// No description provided for @allExpenses.
  ///
  /// In zh, this message translates to:
  /// **'全部支出'**
  String get allExpenses;

  /// No description provided for @expenseCategory.
  ///
  /// In zh, this message translates to:
  /// **'支出分类'**
  String get expenseCategory;

  /// No description provided for @cannotReachService.
  ///
  /// In zh, this message translates to:
  /// **'无法连接服务，请检查网络后重试'**
  String get cannotReachService;

  /// No description provided for @budgetsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'预算目标加载失败，请稍后重试'**
  String get budgetsLoadFailed;

  /// No description provided for @refreshBudgets.
  ///
  /// In zh, this message translates to:
  /// **'刷新预算目标'**
  String get refreshBudgets;

  /// No description provided for @addBudget.
  ///
  /// In zh, this message translates to:
  /// **'新增预算目标'**
  String get addBudget;

  /// No description provided for @noBudgets.
  ///
  /// In zh, this message translates to:
  /// **'还没有预算目标'**
  String get noBudgets;

  /// No description provided for @noBudgetsHint.
  ///
  /// In zh, this message translates to:
  /// **'为支出分类设定每月上限，随时掌握进度。'**
  String get noBudgetsHint;

  /// No description provided for @setFirstBudget.
  ///
  /// In zh, this message translates to:
  /// **'设置第一个目标'**
  String get setFirstBudget;

  /// No description provided for @thisMonthTargets.
  ///
  /// In zh, this message translates to:
  /// **'本月目标'**
  String get thisMonthTargets;

  /// No description provided for @itemCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 项'**
  String itemCount(int count);

  /// No description provided for @budgetDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'本月{name}'**
  String budgetDefaultName(String name);

  /// No description provided for @enterPositiveDecimalAmount.
  ///
  /// In zh, this message translates to:
  /// **'请输入大于 0 且最多两位小数的金额'**
  String get enterPositiveDecimalAmount;

  /// No description provided for @setBudgetTarget.
  ///
  /// In zh, this message translates to:
  /// **'设置预算目标'**
  String get setBudgetTarget;

  /// No description provided for @thisMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月'**
  String get thisMonth;

  /// No description provided for @targetName.
  ///
  /// In zh, this message translates to:
  /// **'目标名称'**
  String get targetName;

  /// No description provided for @monthlyAmount.
  ///
  /// In zh, this message translates to:
  /// **'每月金额'**
  String get monthlyAmount;

  /// No description provided for @saveTarget.
  ///
  /// In zh, this message translates to:
  /// **'保存目标'**
  String get saveTarget;

  /// No description provided for @monthTotalTarget.
  ///
  /// In zh, this message translates to:
  /// **'本月总目标'**
  String get monthTotalTarget;

  /// No description provided for @overBudget.
  ///
  /// In zh, this message translates to:
  /// **'已超出'**
  String get overBudget;

  /// No description provided for @budgetTarget.
  ///
  /// In zh, this message translates to:
  /// **'预算目标'**
  String get budgetTarget;

  /// No description provided for @monthlyWithCategory.
  ///
  /// In zh, this message translates to:
  /// **'每月 · {category}'**
  String monthlyWithCategory(String category);

  /// No description provided for @spentAmount.
  ///
  /// In zh, this message translates to:
  /// **'已用 {amount}'**
  String spentAmount(String amount);

  /// No description provided for @overByAmount.
  ///
  /// In zh, this message translates to:
  /// **'超出 {amount}'**
  String overByAmount(String amount);

  /// No description provided for @remainingAmount.
  ///
  /// In zh, this message translates to:
  /// **'剩余 {amount}'**
  String remainingAmount(String amount);

  /// No description provided for @notSignedInSync.
  ///
  /// In zh, this message translates to:
  /// **'尚未登录同步'**
  String get notSignedInSync;

  /// No description provided for @attachmentsUpload.
  ///
  /// In zh, this message translates to:
  /// **'附件上传'**
  String get attachmentsUpload;

  /// No description provided for @attachmentsHelp.
  ///
  /// In zh, this message translates to:
  /// **'HMAC 签名直传本地对象存储：创建会话 → PUT → complete。'**
  String get attachmentsHelp;

  /// No description provided for @uploading.
  ///
  /// In zh, this message translates to:
  /// **'上传中…'**
  String get uploading;

  /// No description provided for @uploadDemoFile.
  ///
  /// In zh, this message translates to:
  /// **'上传演示文件'**
  String get uploadDemoFile;

  /// No description provided for @noConflicts.
  ///
  /// In zh, this message translates to:
  /// **'当前无冲突'**
  String get noConflicts;

  /// No description provided for @conflictSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'{reason} · 远端版本 {version}'**
  String conflictSubtitle(String reason, String version);

  /// No description provided for @useRemote.
  ///
  /// In zh, this message translates to:
  /// **'采用远端'**
  String get useRemote;

  /// No description provided for @keepLocal.
  ///
  /// In zh, this message translates to:
  /// **'保留本地'**
  String get keepLocal;

  /// No description provided for @copiedToClipboard.
  ///
  /// In zh, this message translates to:
  /// **'已复制到剪贴板'**
  String get copiedToClipboard;

  /// No description provided for @copyCsv.
  ///
  /// In zh, this message translates to:
  /// **'复制 CSV'**
  String get copyCsv;

  /// No description provided for @notSignedInInvites.
  ///
  /// In zh, this message translates to:
  /// **'尚未登录同步，无法加载邀请'**
  String get notSignedInInvites;

  /// No description provided for @familySharing.
  ///
  /// In zh, this message translates to:
  /// **'家庭共享'**
  String get familySharing;

  /// No description provided for @inviteEmail.
  ///
  /// In zh, this message translates to:
  /// **'邀请邮箱'**
  String get inviteEmail;

  /// No description provided for @sendInvite.
  ///
  /// In zh, this message translates to:
  /// **'发送邀请'**
  String get sendInvite;

  /// No description provided for @sentInvites.
  ///
  /// In zh, this message translates to:
  /// **'已发出邀请'**
  String get sentInvites;

  /// No description provided for @inviteRoleToken.
  ///
  /// In zh, this message translates to:
  /// **'角色 {role} · token {token}'**
  String inviteRoleToken(String role, String token);

  /// No description provided for @fxRates.
  ///
  /// In zh, this message translates to:
  /// **'汇率'**
  String get fxRates;

  /// No description provided for @quoteCurrencyVsCny.
  ///
  /// In zh, this message translates to:
  /// **'报价币（相对 CNY）'**
  String get quoteCurrencyVsCny;

  /// No description provided for @exchangeRate.
  ///
  /// In zh, this message translates to:
  /// **'汇率'**
  String get exchangeRate;

  /// No description provided for @monthlyRent.
  ///
  /// In zh, this message translates to:
  /// **'每月房租'**
  String get monthlyRent;

  /// No description provided for @createdWillPostSoon.
  ///
  /// In zh, this message translates to:
  /// **'已创建，Worker 约 1 分钟内入账'**
  String get createdWillPostSoon;

  /// No description provided for @createdWillPostTomorrow.
  ///
  /// In zh, this message translates to:
  /// **'已创建，明日起由 Worker 入账'**
  String get createdWillPostTomorrow;

  /// No description provided for @recurring.
  ///
  /// In zh, this message translates to:
  /// **'周期记账'**
  String get recurring;

  /// No description provided for @ruleName.
  ///
  /// In zh, this message translates to:
  /// **'规则名称'**
  String get ruleName;

  /// No description provided for @amountYuan.
  ///
  /// In zh, this message translates to:
  /// **'金额（元）'**
  String get amountYuan;

  /// No description provided for @runNow.
  ///
  /// In zh, this message translates to:
  /// **'立即调度（runNow）'**
  String get runNow;

  /// No description provided for @createRule.
  ///
  /// In zh, this message translates to:
  /// **'创建规则'**
  String get createRule;

  /// No description provided for @upgraded.
  ///
  /// In zh, this message translates to:
  /// **'已升级'**
  String get upgraded;

  /// No description provided for @subscription.
  ///
  /// In zh, this message translates to:
  /// **'订阅权益'**
  String get subscription;

  /// No description provided for @currentPlan.
  ///
  /// In zh, this message translates to:
  /// **'当前方案'**
  String get currentPlan;

  /// No description provided for @devUpgradePlus.
  ///
  /// In zh, this message translates to:
  /// **'开发升级 Plus（附件/高级报表）'**
  String get devUpgradePlus;

  /// No description provided for @devUpgradeFamily.
  ///
  /// In zh, this message translates to:
  /// **'开发升级 Family（邀请）'**
  String get devUpgradeFamily;

  /// No description provided for @downgradeFree.
  ///
  /// In zh, this message translates to:
  /// **'降回 Free'**
  String get downgradeFree;

  /// No description provided for @statusLabel.
  ///
  /// In zh, this message translates to:
  /// **'状态：{label}'**
  String statusLabel(String label);

  /// No description provided for @cursorLabel.
  ///
  /// In zh, this message translates to:
  /// **'游标：{cursor}'**
  String cursorLabel(int cursor);

  /// No description provided for @pendingLabel.
  ///
  /// In zh, this message translates to:
  /// **'待推送：{count}'**
  String pendingLabel(int count);

  /// No description provided for @remoteBookLabel.
  ///
  /// In zh, this message translates to:
  /// **'远端账本：{id}'**
  String remoteBookLabel(String id);

  /// No description provided for @errorLabel.
  ///
  /// In zh, this message translates to:
  /// **'错误：{error}'**
  String errorLabel(String error);

  /// No description provided for @syncSuccess.
  ///
  /// In zh, this message translates to:
  /// **'同步成功 cursor={cursor}'**
  String syncSuccess(int cursor);

  /// No description provided for @syncFailed.
  ///
  /// In zh, this message translates to:
  /// **'同步失败：{message}'**
  String syncFailed(String message);

  /// No description provided for @syncNow.
  ///
  /// In zh, this message translates to:
  /// **'立即同步'**
  String get syncNow;

  /// No description provided for @noRemoteBook.
  ///
  /// In zh, this message translates to:
  /// **'无远端账本'**
  String get noRemoteBook;

  /// No description provided for @revisionHistory.
  ///
  /// In zh, this message translates to:
  /// **'历史版本'**
  String get revisionHistory;

  /// No description provided for @syncReady.
  ///
  /// In zh, this message translates to:
  /// **'就绪'**
  String get syncReady;

  /// No description provided for @syncError.
  ///
  /// In zh, this message translates to:
  /// **'出错'**
  String get syncError;

  /// No description provided for @bookBoundToOtherAccount.
  ///
  /// In zh, this message translates to:
  /// **'本地账本已绑定到其他账户，已停止同步。'**
  String get bookBoundToOtherAccount;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
