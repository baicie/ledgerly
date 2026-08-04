import 'package:flutter/material.dart';

import '../design/ledgerly_theme.dart';
import 'ledgerly_layout.dart';

class SettingsContent extends StatelessWidget {
  const SettingsContent({
    super.key,
    required this.isLocal,
    required this.planLabel,
    required this.endpointLabel,
    required this.appLock,
    required this.loggingOut,
    required this.changingEndpoint,
    required this.onChangeEndpoint,
    required this.onAppLockChanged,
    required this.onSync,
    required this.onConflicts,
    required this.onExport,
    required this.onCategories,
    required this.onSubscription,
    required this.onFx,
    required this.onFamily,
    required this.onBudgets,
    required this.onRecurring,
    required this.onAttachments,
    required this.onLogout,
  });

  final bool isLocal;
  final String planLabel;
  final String endpointLabel;
  final bool appLock;
  final bool loggingOut;
  final bool changingEndpoint;
  final VoidCallback? onChangeEndpoint;
  final ValueChanged<bool> onAppLockChanged;
  final VoidCallback? onSync;
  final VoidCallback? onConflicts;
  final VoidCallback onExport;
  final VoidCallback onCategories;
  final VoidCallback? onSubscription;
  final VoidCallback? onFx;
  final VoidCallback? onFamily;
  final VoidCallback? onBudgets;
  final VoidCallback? onRecurring;
  final VoidCallback? onAttachments;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return LedgerlyContent(
      slivers: [
        const SliverToBoxAdapter(
          child: LedgerlyPageHeader(
            title: '我的',
            subtitle: '标准账本 · 本地优先',
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          sliver: SliverToBoxAdapter(
            child: _ProfilePanel(isLocal: isLocal, planLabel: planLabel),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverToBoxAdapter(
            child: _SettingsGroup(
              title: '数据与同步',
              children: [
                ListTile(
                  leading: Icon(
                    isLocal
                        ? Icons.storage_outlined
                        : Icons.cloud_done_outlined,
                  ),
                  title: Text(isLocal ? '存储模式' : '当前方案'),
                  subtitle: Text(isLocal ? '仅本地存储' : planLabel),
                ),
                ListTile(
                  key: const Key('settings-api-edit'),
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('API 服务'),
                  subtitle: Text(endpointLabel),
                  trailing: changingEndpoint
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined),
                  enabled: !changingEndpoint,
                  onTap: onChangeEndpoint,
                ),
                ListTile(
                  leading: const Icon(Icons.sync_rounded),
                  title: const Text('同步中心'),
                  subtitle: const Text('查看待同步与最近状态'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: onSync != null,
                  onTap: onSync,
                ),
                ListTile(
                  leading: const Icon(Icons.rule_folder_outlined),
                  title: const Text('冲突处理'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: onConflicts != null,
                  onTap: onConflicts,
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导出 CSV'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onExport,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverToBoxAdapter(
            child: _SettingsGroup(
              title: '账本工具',
              children: [
                _routeTile(
                  Icons.category_outlined,
                  '分类管理',
                  '维护支出与收入分类',
                  onCategories,
                ),
                _routeTile(Icons.workspace_premium_outlined, '订阅权益',
                    'Free / Plus / Family', onSubscription),
                _routeTile(Icons.currency_exchange, '汇率', null, onFx),
                _routeTile(
                    Icons.group_outlined, '家庭共享', '需 Family 方案', onFamily),
                _routeTile(Icons.savings_outlined, '预算', '月度预算与进度', onBudgets),
                _routeTile(Icons.event_repeat_outlined, '周期记账', '自动执行记账规则',
                    onRecurring),
                _routeTile(
                    Icons.attach_file, '附件', '需 Plus · HMAC 直传', onAttachments),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverToBoxAdapter(
            child: _SettingsGroup(
              title: '安全',
              children: [
                if (!isLocal)
                  ListTile(
                    key: const Key('settings-logout'),
                    leading: loggingOut
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.logout,
                            color: Theme.of(context).colorScheme.error,
                          ),
                    title: Text(
                      '退出登录',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                    enabled: !loggingOut && !changingEndpoint,
                    onTap: onLogout,
                  ),
                SwitchListTile(
                  secondary: const Icon(Icons.lock_outline),
                  title: const Text('应用锁'),
                  subtitle: const Text('生物识别能力接入后可直接启用'),
                  value: appLock,
                  onChanged: onAppLockChanged,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  ListTile _routeTile(
    IconData icon,
    String title,
    String? subtitle,
    VoidCallback? onTap,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({required this.isLocal, required this.planLabel});

  final bool isLocal;
  final String planLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: LedgerlyColors.brand,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_outline,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ledgerly 用户',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isLocal ? '数据仅保存在当前设备' : '$planLabel 方案 · 已连接服务',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.76),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isLocal ? Icons.offline_bolt_outlined : Icons.cloud_done_outlined,
              color: LedgerlyColors.brandMint,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LedgerlySection(
      title: title,
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
      headerPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const Divider(indent: 56, endIndent: 16),
            children[index],
          ],
        ],
      ),
    );
  }
}
