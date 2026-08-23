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
  String get conflicts => '冲突处理';

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
  String get amountYuan => '金额（元）';

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
}
