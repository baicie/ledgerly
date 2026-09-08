// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Ledgerly';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get close => '关闭';

  @override
  String get save => '保存';

  @override
  String get saving => '保存中';

  @override
  String get savingEllipsis => '保存中…';

  @override
  String get retry => '重试';

  @override
  String get create => '创建';

  @override
  String get edit => '编辑';

  @override
  String get delete => '删除';

  @override
  String get unknown => '未知';

  @override
  String get show => '显示';

  @override
  String get hide => '隐藏';

  @override
  String get processing => '处理中…';

  @override
  String get navFeed => '流水';

  @override
  String get navAssets => '资产';

  @override
  String get navReports => '报表';

  @override
  String get navMe => '我的';

  @override
  String get addTransaction => '记一笔';

  @override
  String monthPickerLabel(int year, int month) {
    return '$year年 $month月';
  }

  @override
  String get previousMonth => '上个月';

  @override
  String get nextMonth => '下个月';

  @override
  String get weekdayMon => '周一';

  @override
  String get weekdayTue => '周二';

  @override
  String get weekdayWed => '周三';

  @override
  String get weekdayThu => '周四';

  @override
  String get weekdayFri => '周五';

  @override
  String get weekdaySat => '周六';

  @override
  String get weekdaySun => '周日';

  @override
  String feedDayLabel(int month, int day, String weekday) {
    return '$month月$day日 $weekday';
  }

  @override
  String fullDateLabel(int year, int month, int day) {
    return '$year年$month月$day日';
  }

  @override
  String insightDailyDate(int year, int month, int day) {
    return '$year年$month月$day日';
  }

  @override
  String insightMonthlyDate(int year, int month) {
    return '$year年$month月';
  }

  @override
  String trendChartLabel(int year, int month) {
    return '$year年$month月每日收支趋势图';
  }

  @override
  String get uncategorized => '未分类';

  @override
  String get accountCash => '现金';

  @override
  String get accountBank => '银行卡';

  @override
  String get accountTransfer => '账户转账';

  @override
  String get accountOther => '其他';

  @override
  String get categoryFood => '餐饮';

  @override
  String get categoryMeals => '日常用餐';

  @override
  String get categoryDrinksSnacks => '饮品零食';

  @override
  String get categoryTransport => '交通';

  @override
  String get categoryPublicTransport => '公交地铁';

  @override
  String get categoryTaxi => '网约车';

  @override
  String get categoryCarExpenses => '驾车养车';

  @override
  String get categoryShopping => '购物';

  @override
  String get categoryDailyEssentials => '日用百货';

  @override
  String get categoryClothing => '服饰美妆';

  @override
  String get categoryElectronics => '数码电器';

  @override
  String get categoryHousing => '居住';

  @override
  String get categoryRentMortgage => '房租房贷';

  @override
  String get categoryUtilities => '水电燃气';

  @override
  String get categoryPropertyServices => '物业家政';

  @override
  String get categoryLeisure => '休闲';

  @override
  String get categoryEntertainment => '娱乐';

  @override
  String get categoryFitness => '运动健身';

  @override
  String get categoryTravel => '旅行';

  @override
  String get categoryHealthcare => '医疗健康';

  @override
  String get categoryMedicalCare => '看病就医';

  @override
  String get categoryMedicine => '药品保健';

  @override
  String get categoryEducation => '学习';

  @override
  String get categoryBooks => '书籍';

  @override
  String get categoryCourses => '课程培训';

  @override
  String get categoryOtherExpense => '其他支出';

  @override
  String get categorySalary => '工资收入';

  @override
  String get categoryBaseSalary => '基本工资';

  @override
  String get categoryBonus => '奖金';

  @override
  String get categorySideIncome => '副业收入';

  @override
  String get categoryFreelance => '自由职业';

  @override
  String get categoryBusinessIncome => '经营收入';

  @override
  String get categoryInvestmentIncome => '投资收益';

  @override
  String get categoryInterest => '利息';

  @override
  String get categoryDividends => '分红';

  @override
  String get categoryOtherIncome => '其他收入';

  @override
  String get assetAccounts => '资产账户';

  @override
  String accountsSubtitle(int count) {
    return '$count 个账户 · 人民币 CNY';
  }

  @override
  String get newAccount => '新建账户';

  @override
  String get standardLedger => '标准账本';

  @override
  String get newBook => '新建账本';

  @override
  String get bookName => '账本名称';

  @override
  String get switchBook => '切换账本';

  @override
  String get netWorth => '净资产';

  @override
  String get accountDetails => '账户明细';

  @override
  String totalWithAmount(String amount) {
    return '合计 $amount';
  }

  @override
  String get noAssetAccounts => '还没有资产账户';

  @override
  String get noAssetAccountsHint => '新建现金、银行卡或其他资产账户。';

  @override
  String accountsLoadFailed(String error) {
    return '账户加载失败：$error';
  }

  @override
  String get newAccountName => '新账户';

  @override
  String get newAssetAccount => '新建资产账户';

  @override
  String get accountName => '账户名称';

  @override
  String get liabilityAccount => '负债账户';

  @override
  String get assetAccount => '资产账户';

  @override
  String get allTransactions => '全部流水';

  @override
  String get monthlyFeedStats => '本月流水统计';

  @override
  String feedLoadFailed(String error) {
    return '流水加载失败：$error';
  }

  @override
  String insightLoadFailed(String error) {
    return '分析加载失败：$error';
  }

  @override
  String get emptyMonthTitle => '这个月还没有流水';

  @override
  String get emptyMonthMessage => '点击底部的 +，记下第一笔收支。';

  @override
  String get dayNet => '当日净额';

  @override
  String get deleteTransaction => '删除流水';

  @override
  String get monthlyInsightEntryTitle => '每月分析';

  @override
  String get monthlyInsightEntrySubtitle => '在报表页查看所选月份的 AI 月报';

  @override
  String get reportsTitle => '报表';

  @override
  String get reportsSummarySection => '本月概览';

  @override
  String get reportsTrendSection => '近 6 个月趋势';

  @override
  String get reportsBudgetSection => '预算';

  @override
  String get reportsBudgetEmptyTitle => '该周期暂无预算';

  @override
  String get reportsBudgetEmptyAction => '去设置预算';

  @override
  String get reportsHeroIncome => '入账';

  @override
  String get reportsHeroExpense => '支出';

  @override
  String get reportsHeroNet => '结余';

  @override
  String get reportsHeroBudgetLeft => '预算剩';

  @override
  String get reportsHeroBudgetUnset => '未设置';

  @override
  String get budgetCreated => '已添加预算';

  @override
  String get budgetDeleted => '已删除预算';

  @override
  String get reportsIncome => '收入';

  @override
  String get reportsExpense => '支出';

  @override
  String get reportsNet => '净额';

  @override
  String get reportsBaseCurrency => '基础货币';

  @override
  String reportsUpdatedAgo(String time) => '$time前更新';

  @override
  String get reportsUpdatedJustNow => '刚刚更新';

  @override
  String get reportsCategories => '主要分类';

  @override
  String get reportsNoBudgets => '尚未配置预算。';

  @override
  String get reportsPrevMonth => '上一月';

  @override
  String get reportsNextMonth => '下一月';

  @override
  String get reportsRefresh => '刷新';

  @override
  String get aiInsightCardTitle => 'AI 总结';

  @override
  String get aiInsightHighlights => '重点';

  @override
  String get aiInsightAdvice => '建议';

  @override
  String get aiInsightRegenerate => '重新生成';

  @override
  String get aiInsightStale => '数据已变更 — 请重新生成';

  @override
  String get aiInsightUnconfigured => '接入 AI 服务即可生成本月洞察。';

  @override
  String get aiInsightUnconfiguredDesc => '我们将按月分析你的收入、支出和分类情况。';

  @override
  String get aiInsightConfigure => '去配置';

  @override
  String get aiInsightEmpty => '暂无可总结的内容。';

  @override
  String get aiInsightEmptyDesc => '本月记几笔交易后，摘要会显示在这里。';

  @override
  String get aiInsightPeriodMenu => '周期';

  @override
  String get aiInsightPeriodMonth => '本月';

  @override
  String reportsAllCategories(int count) => '全部类别（$count）';

  @override
  String get reportsNoCategories => '没有匹配的类别。';

  @override
  String get reportsSearchHint => '搜索类别';

  @override
  String get reportsRangeTitle => '时间范围';

  @override
  String get reportsRangeMonth => '本月';

  @override
  String get reportsRangeLast3 => '最近 3 个月';

  @override
  String get reportsRangeLast6 => '最近 6 个月';

  @override
  String get reportsRangeLast7 => '最近 7 天';

  @override
  String get reportsRangeLast30 => '最近 30 天';

  @override
  String get reportsRangeLast90 => '最近 90 天';

  @override
  String get reportsRangeYear => '今年';

  @override
  String get reportsRangeCustom => '自定义范围';

  @override
  String get reportsRangeStart => '起始';

  @override
  String get reportsRangeEnd => '结束';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonRetry => '重试';

  @override
  String get reportsExport => '导出与分享';

  @override
  String get reportsExportCsv => '导出 CSV';

  @override
  String get reportsShare => '分享摘要';

  @override
  String get reportsExportNoData => '暂无数据可导出。';

  @override
  String get reportsExportCsvDone => 'CSV 导出成功。';

  @override
  String get reportsExportCsvError => '导出失败';

  @override
  String get reportsTrendJumpToMonth => '跳转到该月';

  @override
  String get localShort => '本地';

  @override
  String get syncedShort => '已同步';

  @override
  String get refreshRemoteSummary => '刷新服务端汇总';

  @override
  String get monthlyFlowStats => '本月收支统计';

  @override
  String get incomeSources => '收入来源';

  @override
  String get noIncomeThisMonth => '本月暂无收入';

  @override
  String get expenseBreakdown => '支出分布';

  @override
  String get noExpenseThisMonth => '本月暂无支出';

  @override
  String get monthlyTrend => '月度趋势';

  @override
  String transactionCountLabel(int count) {
    return '$count 笔';
  }

  @override
  String rankingTrailing(int count, String amount) {
    return '$count 笔 · $amount';
  }

  @override
  String get cloudCheck => '云端校验';

  @override
  String remoteNet(String net, String currency) {
    return '服务端净额 $net · $currency';
  }

  @override
  String reportsLoadFailed(String error) {
    return '报表加载失败：$error';
  }

  @override
  String get thisMonthBalance => '本月结余';

  @override
  String incomeAmount(String amount) {
    return '收入 $amount';
  }

  @override
  String expenseAmount(String amount) {
    return '支出 $amount';
  }

  @override
  String get income => '收入';

  @override
  String get expense => '支出';

  @override
  String get transfer => '转账';

  @override
  String get insightKindDaily => '日分析';

  @override
  String get insightKindMonthly => '月报';

  @override
  String aiInsightTitleWithPeriod(String kind, String period) {
    return 'AI $kind · $period';
  }

  @override
  String aiInsightTitleKindOnly(String kind) {
    return 'AI $kind';
  }

  @override
  String get goConfigure => '去配置';

  @override
  String get insightExpand => '展开分析';

  @override
  String get insightCollapse => '收起分析';

  @override
  String get regenerate => '重新生成';

  @override
  String get generate => '生成';

  @override
  String get insightUnconfiguredDaily =>
      '配置模型供应商和 API Key 后，可在流水里生成每日消费总结。当天和昨天会自动补齐，往日需点生成。当前接入的文本模型不支持语音转文字。';

  @override
  String get insightUnconfiguredMonthly =>
      '配置模型供应商和 API Key 后，可自动生成所选月份的消费月报，并在新月补齐上月月报。当前接入的文本模型不支持语音转文字。';

  @override
  String get insightNotGenerated => '尚未生成分析';

  @override
  String get insightGenerating => '正在生成分析…';

  @override
  String get insightEmptyDaily => '当日暂无消费';

  @override
  String get insightEmptyMonthly => '当月暂无消费';

  @override
  String get insightEmptyNoModel => '暂无消费，未调用模型。';

  @override
  String get insightFailed => '分析失败';

  @override
  String get insightStale => '账目已更新，可重新生成。';

  @override
  String get insightFallbackHeadline => '消费总结';

  @override
  String tokenUsage(String model, String prompt, String completion) {
    return '$model · 入 $prompt / 出 $completion tokens';
  }

  @override
  String get aiSettingsTitle => '智能分析';

  @override
  String get modelService => '模型服务';

  @override
  String get provider => '供应商';

  @override
  String get aiProviderCustom => '自定义兼容接口';

  @override
  String get model => '模型';

  @override
  String get custom => '自定义';

  @override
  String get customModelId => '自定义模型 ID';

  @override
  String get autoGenerateInsights => '自动生成分析';

  @override
  String get autoGenerateInsightsSubtitle => '打开应用时补齐今日、昨日和上月总结。往日流水需点生成。';

  @override
  String get aiPromptPreset => '系统提示词';

  @override
  String get aiPromptPresetBalanced => '均衡总结';

  @override
  String get aiPromptPresetFrugal => '节约教练';

  @override
  String get aiPromptPresetReview => '复盘助手';

  @override
  String get aiPromptPresetConcise => '极简结论';

  @override
  String get aiPromptPresetCustom => '自定义';

  @override
  String get aiPromptPresetBalancedSubtitle => '总结结构、异常大额，并给一句可执行建议。';

  @override
  String get aiPromptPresetFrugalSubtitle => '优先找可砍或可延后的支出，语气直接。';

  @override
  String get aiPromptPresetReviewSubtitle => '先事实后判断，标出占比最高和最异常的一笔。';

  @override
  String get aiPromptPresetConciseSubtitle => '标题更短，只保留最重要的三条事实和一条建议。';

  @override
  String get aiPromptPresetCustomSubtitle => '使用你自己的系统提示词。仍会要求模型只输出 JSON。';

  @override
  String get aiCustomSystemPrompt => '自定义系统提示词';

  @override
  String get aiCustomSystemPromptHint => '例如：用更口语的方式总结消费，并提醒是否超出日常节奏。';

  @override
  String get testingConnection => '测试中…';

  @override
  String get testConnection => '测试连接';

  @override
  String get capabilitiesAndUsage => '能力与用量';

  @override
  String get aiSavedLocally => '已保存。密钥只留在本机，不会同步到账本服务。';

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get enterApiKeyFirst => '请先填写 API Key。';

  @override
  String get connectionSuccess => '连接成功。';

  @override
  String get aiCapabilityProtocol =>
      '当前走 OpenAI 兼容的 Chat Completions。分析模型不能语音转文字。分析会把分类、金额和备注发送到你配置的端点。';

  @override
  String get aiCapabilityOpencode =>
      'OpenCode 使用 Zen Go 网关 https://opencode.ai/zen/go/v1。网页浏览器会拦截跨域请求，测试连接在网页里会失败；请保存后用 App。预设仅包含 Chat Completions 模型，GPT / Claude 本期不接。';

  @override
  String aiCapabilityUsage(String hint) {
    return '第一期不做累计用量看板，$hint分析卡片会显示最近一次调用的 token。';
  }

  @override
  String get aiUsageHintDeepseek => '余额请到 DeepSeek 控制台查看。';

  @override
  String get aiUsageHintOpencode =>
      '密钥和余额请到 OpenCode 控制台查看。网页浏览器无法直连该接口（无 CORS），请在 App 中使用。';

  @override
  String get aiUsageHintCustom => '用量请到你使用的供应商控制台查看。';

  @override
  String get invalidHttpUrl => '请输入 http(s) 地址';

  @override
  String get urlMustNotIncludeCredentials => '地址不能包含账号密码';

  @override
  String get cannotSaveApiKey => '无法保存 API Key。';

  @override
  String get cannotSaveModelSettings => '无法保存模型设置。';

  @override
  String get modelReturnedEmpty => '模型没有返回可用内容。';

  @override
  String get invalidApiKey => 'API Key 无效，请检查设置。';

  @override
  String get modelBalanceLow => '模型账户余额不足。';

  @override
  String get tooManyRequests => '请求过于频繁，请稍后再试。';

  @override
  String get corsBlockedOpencode =>
      '浏览器拦截了跨域请求。OpenCode 官方接口不允许网页直连，请保存后在 App 中使用，或改用带 CORS 的兼容网关。';

  @override
  String get cannotReachModelWeb => '无法连接模型服务。网页端可能被跨域拦截，请改用 App 或兼容端点。';

  @override
  String get cannotReachModel => '无法连接模型服务，请检查网络和 Base URL。';

  @override
  String get modelTimeout => '模型服务超时，请稍后重试。';

  @override
  String get modelCallFailed => '模型调用失败。';

  @override
  String modelCallFailedWithStatus(int status) {
    return '模型调用失败（$status）。';
  }

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSubtitleLocal => '本地模式 · 数据保存在当前设备';

  @override
  String get settingsSubtitleRemote => '已连接服务 · 自动同步账本数据';

  @override
  String get dataAndSync => '数据与同步';

  @override
  String get apiService => 'API 服务';

  @override
  String get syncCenter => '同步中心';

  @override
  String get syncCenterSubtitle => '查看待同步与最近状态';

  @override
  String get syncStatusReady => '已同步';

  @override
  String get syncStatusPending => '同步中…';

  @override
  String get syncStatusError => '同步异常';

  @override
  String get syncRemoteBook => '云端账本';

  @override
  String get syncCursorLabel => '同步游标';

  @override
  String get syncPendingLabel => '待上传变更';

  @override
  String syncPendingCount(int count) {
    if (count == 0) return '无待上传';
    if (count == 1) return '1 项待上传';
    return '$count 项待上传';
  }

  @override
  String get syncLastError => '上次错误';

  @override
  String get syncInProgress => '正在同步…';

  @override
  String get conflicts => '冲突处理';

  @override
  String get conflictEntityHint => '交易';

  @override
  String get conflictResolveRemoteHint => '放弃本地修改，使用云端版本';

  @override
  String get conflictResolveLocalHint => '保留本地修改，并推送到云端';

  @override
  String get conflictResolved => '冲突已处理';

  @override
  String conflictRemoteVersion(String version) => '云端版本 $version';

  @override
  String get exportCsv => '导出 CSV';

  @override
  String get exportCsvSubtitle => '备份当前账本数据';

  @override
  String get ledgerSection => '账本';

  @override
  String get categoryManagement => '分类管理';

  @override
  String get categoryManagementSubtitle => '维护支出与收入分类';

  @override
  String get budgetTargets => '预算目标';

  @override
  String get budgetTargetsSubtitle => '设置每月支出上限与进度';

  @override
  String get smartInsights => '智能分析';

  @override
  String get aiSpendInsights => 'AI 消费总结';

  @override
  String get aiSpendInsightsSubtitle => '供应商、密钥、模型、提示词与自动分析';

  @override
  String get accountSection => '账户';

  @override
  String get logOut => '退出登录';

  @override
  String get switchToLocalTitle => '改为仅本地存储？';

  @override
  String get connectApiTitle => '连接 API 服务？';

  @override
  String get switchApiTitle => '切换 API 服务？';

  @override
  String get switchToLocalBody => '远端登录会退出，本机账本数据会保留。';

  @override
  String get connectApiBody => '连接后需要登录服务，本机账本数据会保留。';

  @override
  String get localOnlyStorage => '仅本地存储';

  @override
  String get localOnlyHelp => '接入服务端后即可开启同步';

  @override
  String get confirmConnect => '确认连接';

  @override
  String get apiSettingsSaveFailed => 'API 设置保存失败，仍保持原存储模式。';

  @override
  String get confirmLogoutTitle => '确认退出登录？';

  @override
  String get confirmLogoutBody => '本机账本数据会保留，下次登录后可继续使用。';

  @override
  String get endpointUnsetLocal => '未设置（仅本地存储）';

  @override
  String get login => '登录';

  @override
  String get register => '注册';

  @override
  String get email => '邮箱';

  @override
  String get emailTooLong => '邮箱不能超过 254 个字符';

  @override
  String get invalidEmail => '请输入有效邮箱';

  @override
  String get displayName => '称呼';

  @override
  String get enterDisplayName => '请输入称呼';

  @override
  String get displayNameTooLong => '称呼不能超过 80 个字符';

  @override
  String get password => '密码';

  @override
  String get showPassword => '显示密码';

  @override
  String get hidePassword => '隐藏密码';

  @override
  String get passwordTooShort => '密码至少 8 位';

  @override
  String get passwordTooLong => '密码不能超过 128 位';

  @override
  String get registerAndContinue => '注册并继续';

  @override
  String get changeApiService => '更换 API 服务';

  @override
  String get apiAddressSaveFailed => 'API 地址保存失败，请稍后重试。';

  @override
  String get restoreSessionFailed => '会话恢复失败。';

  @override
  String get restoreSessionFailedRetry => '恢复会话失败，请稍后重试。';

  @override
  String get loginFailedRetry => '登录失败，请稍后重试。';

  @override
  String get registerFailedRetry => '注册失败，请稍后重试。';

  @override
  String get logoutRemoteRevokeFailed => '已清除本机登录状态，但服务器会话撤销失败。';

  @override
  String get sessionExpired => '登录状态已失效，请重新登录。';

  @override
  String get invalidCredentials => '邮箱或密码错误。';

  @override
  String get emailTaken => '该邮箱已注册。';

  @override
  String get weakPassword => '密码需为 8–128 位。';

  @override
  String get cannotReachServer => '无法连接服务器，请检查网络后重试。';

  @override
  String get cannotReadSavedApi => '无法读取已保存的 API 地址，请重新设置。';

  @override
  String get apiEndpointSetupTitle => 'API 服务配置';

  @override
  String get apiEndpointSetupSubtitle => '地址选填，留空时仅在本机存储';

  @override
  String get apiAddressOptional => 'API 地址（选填）';

  @override
  String get apiAddressHelper => '原生端支持局域网 IP；留空则仅本地存储';

  @override
  String get saveSettings => '保存设置';

  @override
  String get requireHttpsLanOk => '请使用 HTTPS；原生客户端也支持局域网 IP 地址';

  @override
  String get webReleaseHttps443 => 'Web 正式版本仅支持 HTTPS 默认端口（443）';

  @override
  String get apiOriginOnly => '请输入不含路径、查询或凭据的 API 根地址';

  @override
  String get enterApiAddress => '请输入 API 地址';

  @override
  String get invalidHttpApiAddress => '请输入有效的 HTTP(S) API 地址';

  @override
  String get newCategory => '新建分类';

  @override
  String categoryTypeHeading(String type) {
    return '$type分类';
  }

  @override
  String categoryLevelCounts(int roots, int seconds) {
    return '$roots 个一级 · $seconds 个二级';
  }

  @override
  String noCategoriesOfType(String type) {
    return '还没有$type分类';
  }

  @override
  String get noCategoriesHint => '新建一级分类后即可继续添加二级分类。';

  @override
  String get categoriesLoadFailed => '分类加载失败';

  @override
  String get noSecondLevelCategories => '暂无二级分类';

  @override
  String secondLevelCount(int count) {
    return '$count 个二级分类';
  }

  @override
  String addChildCategoryUnder(String name) {
    return '在$name下新增二级分类';
  }

  @override
  String editNamedCategory(String name) {
    return '编辑$name';
  }

  @override
  String get secondLevelCategory => '二级分类';

  @override
  String get firstLevelCategory => '一级分类';

  @override
  String get needParentCategoryFirst => '请先新建一个同类型的一级分类';

  @override
  String get categorySaveFailed => '分类保存失败，请稍后重试';

  @override
  String get editCategory => '编辑分类';

  @override
  String get categoryInfo => '分类信息';

  @override
  String get categoryName => '分类名称';

  @override
  String get flowType => '收支类型';

  @override
  String get categoryLevel => '分类级别';

  @override
  String get parentCategory => '上级分类';

  @override
  String get categoryHasChildrenKeepRoot => '该分类包含二级分类，级别保持为一级。';

  @override
  String get categoryNotFound => '分类不存在';

  @override
  String get cannotNestRootWithChildren => '包含二级分类的一级分类不能改为二级';

  @override
  String get enterCategoryName => '请输入分类名称';

  @override
  String get categoryNameTooLong => '分类名称不能超过 24 个字符';

  @override
  String get invalidCategoryType => '分类类型无效';

  @override
  String get categoryCannotBeOwnParent => '分类不能作为自己的上级分类';

  @override
  String get chooseSameTypeParent => '请选择同类型的一级分类';

  @override
  String get categoryMaxTwoLevels => '分类最多只能分为两级';

  @override
  String get duplicateCategoryName => '同类型下已存在该分类';

  @override
  String get editTransaction => '编辑流水';

  @override
  String get date => '日期';

  @override
  String get category => '分类';

  @override
  String get fromAccount => '转出账户';

  @override
  String get account => '账户';

  @override
  String get toAccount => '转入账户';

  @override
  String get noteOptional => '添加备注（可选）';

  @override
  String get expenseAmountLabel => '支出金额';

  @override
  String get incomeAmountLabel => '收入金额';

  @override
  String get transferAmountLabel => '转账金额';

  @override
  String get updateExpense => '更新支出';

  @override
  String get saveExpense => '保存支出';

  @override
  String get updateIncome => '更新收入';

  @override
  String get saveIncome => '保存收入';

  @override
  String get updateTransfer => '更新转账';

  @override
  String get saveTransfer => '保存转账';

  @override
  String get pickIncomeCategory => '选择收入分类';

  @override
  String get pickExpenseCategory => '选择支出分类';

  @override
  String get pickDate => '选择日期';

  @override
  String get ok => '确定';

  @override
  String get pickFromAccount => '选择转出账户';

  @override
  String get pickAccount => '选择账户';

  @override
  String get pickToAccount => '选择转入账户';

  @override
  String get enterPositiveAmount => '请输入大于 0 的金额';

  @override
  String get missingCategoryOrAccount => '当前账本缺少可用的分类或账户';

  @override
  String get transferAccountsMustDiffer => '转出账户和转入账户不能相同';

  @override
  String get finishEditing => '完成编辑';

  @override
  String get editCategoryAction => '编辑分类';

  @override
  String get noCategories => '暂无分类';

  @override
  String get noAccounts => '暂无可用账户';

  @override
  String get addCategory => '新增分类';

  @override
  String parentSecondLevel(String parent) {
    return '$parent · 二级分类';
  }

  @override
  String editNamed(String name) {
    return '编辑$name';
  }

  @override
  String selectNamed(String name) {
    return '选择$name';
  }

  @override
  String get backspace => '退格';

  @override
  String get decimalPoint => '小数点';

  @override
  String get notSignedInBudgets => '尚未登录同步，无法加载预算目标';

  @override
  String get createExpenseCategoryFirst => '请先创建一个支出分类，再设置预算目标';

  @override
  String get notSignedInCreateBudget => '尚未登录同步，无法创建预算目标';

  @override
  String get allExpenses => '全部支出';

  @override
  String get expenseCategory => '支出分类';

  @override
  String get cannotReachService => '无法连接服务，请检查网络后重试';

  @override
  String get budgetsLoadFailed => '预算目标加载失败，请稍后重试';

  @override
  String get refreshBudgets => '刷新预算目标';

  @override
  String get addBudget => '新增预算目标';

  @override
  String get noBudgets => '还没有预算目标';

  @override
  String get noBudgetsHint => '为支出分类设定每月上限，随时掌握进度。';

  @override
  String get setFirstBudget => '设置第一个目标';

  @override
  String get thisMonthTargets => '本月目标';

  @override
  String itemCount(int count) {
    return '$count 项';
  }

  @override
  String budgetDefaultName(String name) {
    return '本月$name';
  }

  @override
  String get enterPositiveDecimalAmount => '请输入大于 0 且最多两位小数的金额';

  @override
  String get setBudgetTarget => '设置预算目标';

  @override
  String get thisMonth => '本月';

  @override
  String get targetName => '目标名称';

  @override
  String get monthlyAmount => '每月金额';

  @override
  String get saveTarget => '保存目标';

  @override
  String get monthTotalTarget => '本月总目标';

  @override
  String get overBudget => '已超出';

  @override
  String get budgetTarget => '预算目标';

  @override
  String monthlyWithCategory(String category) {
    return '每月 · $category';
  }

  @override
  String spentAmount(String amount) {
    return '已用 $amount';
  }

  @override
  String overByAmount(String amount) {
    return '超出 $amount';
  }

  @override
  String remainingAmount(String amount) {
    return '剩余 $amount';
  }

  @override
  String get notSignedInSync => '尚未登录同步';

  @override
  String get attachmentsUpload => '附件上传';

  @override
  String get attachmentsHelp => 'HMAC 签名直传本地对象存储：创建会话 → PUT → complete。';

  @override
  String get uploading => '上传中…';

  @override
  String get uploadDemoFile => '上传演示文件';

  @override
  String get noConflicts => '当前无冲突';

  @override
  String conflictSubtitle(String reason, String version) {
    return '$reason · 远端版本 $version';
  }

  @override
  String get useRemote => '采用远端';

  @override
  String get keepLocal => '保留本地';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get copyCsv => '复制 CSV';

  @override
  String get notSignedInInvites => '尚未登录同步，无法加载邀请';

  @override
  String get familySharing => '家庭共享';

  @override
  String get inviteEmail => '邀请邮箱';

  @override
  String get sendInvite => '发送邀请';

  @override
  String get sentInvites => '已发出邀请';

  @override
  String inviteRoleToken(String role, String token) {
    return '角色 $role · token $token';
  }

  @override
  String get fxRates => '汇率';

  @override
  String get quoteCurrencyVsCny => '报价币（相对 CNY）';

  @override
  String get exchangeRate => '汇率';

  @override
  String get monthlyRent => '每月房租';

  @override
  String get createdWillPostSoon => '已创建，Worker 约 1 分钟内入账';

  @override
  String get createdWillPostTomorrow => '已创建，明日起由 Worker 入账';

  @override
  String get recurring => '周期记账';

  @override
  String get ruleName => '规则名称';

  @override
  String get amountInvalid => '请输入有效的金额';

  @override
  String get amountRequired => '请填写金额';

  @override
  String get amountMustBePositive => '金额必须大于零';

  @override
  String get merchantOptional => '商户（可选）';

  @override
  String get note => '备注';

  @override
  String get runNow => '立即调度（runNow）';

  @override
  String get createRule => '创建规则';

  @override
  String get upgraded => '已升级';

  @override
  String get subscription => '订阅权益';

  @override
  String get currentPlan => '当前方案';

  @override
  String get devUpgradePlus => '开发升级 Plus（附件/高级报表）';

  @override
  String get devUpgradeFamily => '开发升级 Family（邀请）';

  @override
  String get downgradeFree => '降回 Free';

  @override
  String statusLabel(String label) {
    return '状态：$label';
  }

  @override
  String cursorLabel(int cursor) {
    return '游标：$cursor';
  }

  @override
  String pendingLabel(int count) {
    return '待推送：$count';
  }

  @override
  String remoteBookLabel(String id) {
    return '远端账本：$id';
  }

  @override
  String errorLabel(String error) {
    return '错误：$error';
  }

  @override
  String syncSuccess(int cursor) {
    return '同步成功 cursor=$cursor';
  }

  @override
  String syncFailed(String message) {
    return '同步失败：$message';
  }

  @override
  String get syncNow => '立即同步';

  @override
  String get noRemoteBook => '无远端账本';

  @override
  String get revisionHistory => '历史版本';

  @override
  String get syncReady => '就绪';

  @override
  String get syncError => '出错';

  @override
  String get bookBoundToOtherAccount => '本地账本已绑定到其他账户，已停止同步。';

  @override
  String get searchTransactionsHint => '搜索备注、分类、账户或金额';

  @override
  String get noSearchResults => '没有匹配的流水';

  @override
  String get noSearchResultsMessage => '试试其他关键字，或清空搜索';

  @override
  String get feedSourceFilterAll => '全部';

  @override
  String get feedSourceFilterAuto => '自动';

  @override
  String get feedSourceFilterManual => '手动';

  @override
  String get feedSourceFilterAutoTooltip => '只显示由微信 / 支付宝通知自动入账的交易';

  @override
  String get feedSourceBadgeTooltip => '来自支付通知自动入账';

  @override
  String get feedMonthlySummaryAll => '本月总览';

  @override
  String get feedMonthlySummaryAuto => '本月自动入账';

  @override
  String get feedMonthlySummaryManual => '本月手动入账';

  @override
  String get securitySection => '安全';

  @override
  String get appLock => '应用锁';

  @override
  String get appLockSubtitle => '用 PIN 或生物识别保护打开应用';

  @override
  String get appLockBody => '启用后，冷启动和回到前台需要解锁。PIN 始终可用；可再打开指纹或面容。';

  @override
  String get enableAppLock => '启用应用锁';

  @override
  String get disableAppLock => '关闭应用锁';

  @override
  String get appLockPin => 'PIN';

  @override
  String get appLockPinConfirm => '确认 PIN';

  @override
  String get appLockPinHint => '4 到 8 位数字';

  @override
  String get unlock => '解锁';

  @override
  String get wrongPin => 'PIN 不正确';

  @override
  String get pinMismatch => '两次 PIN 不一致';

  @override
  String get invalidPin => '请输入 4 到 8 位数字';

  @override
  String get appLockedTitle => '已锁定';

  @override
  String get unlockWithBiometrics => '用指纹或面容解锁';

  @override
  String get useBiometrics => '生物识别解锁';

  @override
  String get useBiometricsSubtitle => '打开应用时优先用指纹或面容，失败再输入 PIN';

  @override
  String get biometricsUnavailable => '这台设备没有可用的生物识别';

  @override
  String get importSelectAll => '全选';

  @override
  String get importSelectNone => '全不选';

  @override
  String get importDuplicateHint => '账本里已有同日同额同备注，已取消勾选';

  @override
  String get importHelp => '支持支付宝、微信导出的 CSV（UTF-8 或 GBK）。退款和关闭单会跳过。确认后才会写入账本。';

  @override
  String get importCsv => '导入账单';

  @override
  String get importCsvSubtitle => '从支付宝、微信或导出的 CSV 导入';

  @override
  String get importCsvTitle => '导入账单';

  @override
  String get pickCsv => '选择 CSV 文件';

  @override
  String get importConfirm => '确认入账';

  @override
  String importSelectedCount(int count) {
    return '将导入 $count 笔';
  }

  @override
  String importedCount(int count) {
    return '已导入 $count 笔';
  }

  @override
  String get importNothing => '没有可导入的记录';

  @override
  String get saveCsvFile => '保存 / 分享';

  @override
  String get csvSaved => '已导出文件';

  @override
  String get allExpensesBudgetName => '全部支出预算';

  @override
  String get dayOfMonth => '每月几号';

  @override
  String nextRunDate(String date) {
    return '下次入账 $date';
  }

  @override
  String get recurringLocalHelp =>
      '每月 1 到 31 日自动记账；没有那天就记在月末。只保存在本机，重复的不会再记一笔。';

  @override
  String get recurringSubtitle => '每月固定日期自动记账';

  @override
  String get attachmentsLocalHelp => '附件只保存在本机，不会同步到服务器。';

  @override
  String get attachmentsSubtitle => '只保存在本机，不同步';

  @override
  String get addAttachment => '添加文件';

  @override
  String get addImage => '添加图片';

  @override
  String get noAttachments => '还没有附件';

  @override
  String get monthBudgetProgress => '本月预算';

  @override
  String get lastDayOfMonthHint => '该月没有这天则记在月末';

  @override
  String get deleteBudget => '删除预算';

  @override
  String get pauseRule => '暂停';

  @override
  String get resumeRule => '启用';

  @override
  String get deleteRule => '删除规则';

  @override
  String get kindLabel => '类型';

  @override
  String get kindExpense => '支出';

  @override
  String get kindIncome => '收入';

  @override
  String get fundingAccount => '资金账户';

  @override
  String get autoLedgerSection => '自动记账';

  @override
  String get autoLedgerTitle => '自动捕捉支付通知';

  @override
  String get autoLedgerSubtitle => '读取微信和支付宝通知，自动入账为支出或收入';

  @override
  String get autoLedgerEnable => '开启自动记账';

  @override
  String get autoLedgerDisable => '关闭自动记账';

  @override
  String get autoLedgerGranted => '已授予通知使用权';

  @override
  String get autoLedgerNotGranted => '尚未授予通知使用权';

  @override
  String get autoLedgerOpenSettings => '打开通知设置';

  @override
  String get autoLedgerSyncNow => '立即同步待入账通知';

  @override
  String autoLedgerSyncSummary(int posted, int duplicates, int skipped) {
    return '已入账 $posted，重复 $duplicates，已跳过 $skipped';
  }

  @override
  String get autoLedgerEmpty => '暂无待入账通知';

  @override
  String get autoLedgerFailed => '无法读取通知权限状态';

  @override
  String get amountYuan => '金额（元）';

  @override
  String autoLedgerPendingCount(int count) {
    return '$count 条待入账';
  }

  @override
  String get autoLedgerPlatformWechat => '微信支付';

  @override
  String get autoLedgerPlatformAlipay => '支付宝';

  @override
  String get autoLedgerPlatformUnknown => '未知平台';

  @override
  String get autoLedgerRescueTitle => '手动入账这条通知';

  @override
  String autoLedgerRescueReason(String reason) {
    return '失败原因：$reason';
  }

  @override
  String get autoLedgerRescuePlatform => '平台';

  @override
  String get autoLedgerRescueTime => '时间';

  @override
  String get autoLedgerRescueRawLabel => '通知原文';

  @override
  String get autoLedgerRescueSubmit => '保存到账本';

  @override
  String get autoLedgerRescueAlreadySaved => '这条已经入过账了。';

  @override
  String get autoLedgerRescueCategoryLabel => '分类';

  @override
  String get autoLedgerRescueLearnRule => '记住这条商户 → 分类规则';

  @override
  String get autoLedgerRescueLearnRuleHint => '以后同一家商户的通知会自动入到这里。';

  @override
  String get autoLedgerRescueLearnRuleToast => '已记住规则，下次这家商户会自动入账。';

  @override
  String get all => '全部';

  @override
  String get autoLedgerUnparsedEmpty => '暂无未识别的通知';

  @override
  String get autoLedgerUnparsedEmptyHint => '无法识别为入账或出账的通知会出现在这里。';

  @override
  String autoLedgerUnparsedCount(int count) {
    return '$count 条未识别';
  }

  @override
  String get autoLedgerUnparsedDismiss => '全部忽略';

  @override
  String get autoLedgerUnparsedCopy => '复制原文';

  @override
  String get autoLedgerUnparsedCopied => '已复制原文';

  @override
  String autoLedgerBulkRescueTitle(int count) {
    return '批量入账（$count 条）';
  }

  @override
  String autoLedgerBulkRescueSummary(int count) {
    return '将使用同一个金额和分类入账 $count 条记录。';
  }

  @override
  String autoLedgerBulkRescueAmountHint(int count) {
    return '这笔批量里 $count 条都用同一个金额。';
  }

  @override
  String autoLedgerBulkRescueConfirm(int count) {
    return '入账 $count 条';
  }

  @override
  String autoLedgerBulkSelectedCount(int count) {
    return '已选 $count 条';
  }

  @override
  String get autoLedgerBulkClear => '清空';

  @override
  String autoLedgerBulkRescue(int count) {
    return '入账 ($count)';
  }

  @override
  String autoLedgerBulkRescueSuccess(int count) {
    return '已成功入账 $count 条。';
  }

  @override
  String autoLedgerBulkRescuePartial(int rescued, int failed) {
    return '成功 $rescued 条，失败 $failed 条。';
  }

  @override
  String autoLedgerBulkRescueTotalPreview(
      int count, String unit, String total) {
    return '$count 笔 × ¥$unit = ¥$total';
  }

  @override
  String autoLedgerBacklogTitle(int count) {
    return '$count 条通知待处理';
  }

  @override
  String autoLedgerBacklogDominantHint(String reason, int count) {
    return '其中最多的是 $reason（$count 条），可以添加商户规则覆盖这种情况。';
  }

  @override
  String get autoLedgerBacklogAction => '去看看';

  @override
  String get selectAll => '全选';

  @override
  String get autoLedgerRulesTitle => '商户分类规则';

  @override
  String get autoLedgerRulesSubtitle => '告诉 Ledgerly 某个商户应归入哪个分类。自定义规则优先于内置默认。';

  @override
  String get autoLedgerRulesEmpty => '尚未添加自定义规则';

  @override
  String get autoLedgerRulesEmptyHint => '只要某条通知被误分类，可以手动添加一条规则。规则仅保存在本机。';

  @override
  String get autoLedgerRuleAddTitle => '新增分类规则';

  @override
  String get autoLedgerRuleEditTitle => '编辑分类规则';

  @override
  String get autoLedgerRuleAdd => '添加规则';

  @override
  String get autoLedgerRuleNeedlesLabel => '匹配关键词';

  @override
  String get autoLedgerRuleNeedlesHelper => '多个关键词请用逗号分隔。任一匹配即生效。';

  @override
  String get autoLedgerRuleCategoryLabel => '默认分类';

  @override
  String get autoLedgerRuleChooseCategory => '请先选择一个分类。';

  @override
  String get autoLedgerRuleNeedNeedle => '至少添加一个匹配关键词。';

  @override
  String get autoLedgerRuleDeleteTitle => '删除该规则？';

  @override
  String get autoLedgerRuleDeleteBody => '以后匹配该规则的通知将回落到内置默认。';
}
