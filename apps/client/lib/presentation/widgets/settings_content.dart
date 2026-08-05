import 'package:flutter/material.dart';

import 'ledgerly_layout.dart';

class SettingsContent extends StatelessWidget {
  const SettingsContent({
    super.key,
    required this.isLocal,
    required this.endpointLabel,
    required this.loggingOut,
    required this.changingEndpoint,
    required this.onChangeEndpoint,
    required this.onSync,
    required this.onConflicts,
    required this.onExport,
    required this.onCategories,
    this.onBudgets,
    required this.onLogout,
  });

  final bool isLocal;
  final String endpointLabel;
  final bool loggingOut;
  final bool changingEndpoint;
  final VoidCallback? onChangeEndpoint;
  final VoidCallback? onSync;
  final VoidCallback? onConflicts;
  final VoidCallback onExport;
  final VoidCallback onCategories;
  final VoidCallback? onBudgets;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return LedgerlyContent(
      slivers: [
        SliverToBoxAdapter(
          child: LedgerlyPageHeader(
            title: '设置',
            subtitle: isLocal ? '本地模式 · 数据保存在当前设备' : '已连接服务 · 自动同步账本数据',
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          sliver: SliverToBoxAdapter(
            child: _SettingsGroup(
              title: '数据与同步',
              children: [
                ListTile(
                  key: const Key('settings-api-edit'),
                  leading: Icon(
                    isLocal
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_done_outlined,
                  ),
                  title: const Text('API 服务'),
                  subtitle: Text(
                    endpointLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: changingEndpoint
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined, size: 20),
                  enabled: !changingEndpoint,
                  onTap: onChangeEndpoint,
                ),
                if (onSync != null)
                  _routeTile(
                    Icons.sync_rounded,
                    '同步中心',
                    '查看待同步与最近状态',
                    onSync!,
                  ),
                if (onConflicts != null)
                  _routeTile(
                    Icons.rule_folder_outlined,
                    '冲突处理',
                    null,
                    onConflicts!,
                  ),
                _routeTile(
                  Icons.file_download_outlined,
                  '导出 CSV',
                  '备份当前账本数据',
                  onExport,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverToBoxAdapter(
            child: _SettingsGroup(
              title: '账本',
              children: [
                _routeTile(
                  Icons.category_outlined,
                  '分类管理',
                  '维护支出与收入分类',
                  onCategories,
                ),
                if (onBudgets != null)
                  _routeTile(
                    Icons.flag_outlined,
                    '预算目标',
                    '设置每月支出上限与进度',
                    onBudgets!,
                  ),
              ],
            ),
          ),
        ),
        if (!isLocal)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            sliver: SliverToBoxAdapter(
              child: _SettingsGroup(
                title: '账户',
                children: [
                  ListTile(
                    key: const Key('settings-logout'),
                    leading: loggingOut
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.logout,
                            color: Theme.of(context).colorScheme.error,
                          ),
                    title: Text(
                      '退出登录',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    enabled: !loggingOut && !changingEndpoint,
                    onTap: onLogout,
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
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
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
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 2),
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
