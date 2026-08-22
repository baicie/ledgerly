import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
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
    this.onImport,
    this.onBudgets,
    this.onRecurring,
    this.onAttachments,
    this.onLock,
    required this.onAi,
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
  final VoidCallback? onImport;
  final VoidCallback? onBudgets;
  final VoidCallback? onRecurring;
  final VoidCallback? onAttachments;
  final VoidCallback? onLock;
  final VoidCallback onAi;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return LedgerlyContent(
      slivers: [
        SliverToBoxAdapter(
          child: LedgerlyPageHeader(
            title: l10n.settingsTitle,
            subtitle: isLocal
                ? l10n.settingsSubtitleLocal
                : l10n.settingsSubtitleRemote,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          sliver: SliverToBoxAdapter(
            child: _SettingsGroup(
              title: l10n.dataAndSync,
              children: [
                ListTile(
                  key: const Key('settings-api-edit'),
                  leading: Icon(
                    isLocal
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_done_outlined,
                  ),
                  title: Text(l10n.apiService),
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
                    l10n.syncCenter,
                    l10n.syncCenterSubtitle,
                    onSync!,
                  ),
                if (onConflicts != null)
                  _routeTile(
                    Icons.rule_folder_outlined,
                    l10n.conflicts,
                    null,
                    onConflicts!,
                  ),
                _routeTile(
                  Icons.file_download_outlined,
                  l10n.exportCsv,
                  l10n.exportCsvSubtitle,
                  onExport,
                ),
                if (onImport != null)
                  _routeTile(
                    Icons.file_upload_outlined,
                    l10n.importCsv,
                    l10n.importCsvSubtitle,
                    onImport!,
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverToBoxAdapter(
            child: _SettingsGroup(
              title: l10n.ledgerSection,
              children: [
                _routeTile(
                  Icons.category_outlined,
                  l10n.categoryManagement,
                  l10n.categoryManagementSubtitle,
                  onCategories,
                ),
                if (onBudgets != null)
                  _routeTile(
                    Icons.flag_outlined,
                    l10n.budgetTargets,
                    l10n.budgetTargetsSubtitle,
                    onBudgets!,
                  ),
                if (onRecurring != null)
                  _routeTile(
                    Icons.repeat_rounded,
                    l10n.recurring,
                    l10n.recurringSubtitle,
                    onRecurring!,
                  ),
                if (onAttachments != null)
                  _routeTile(
                    Icons.attachment_outlined,
                    l10n.attachmentsUpload,
                    l10n.attachmentsSubtitle,
                    onAttachments!,
                  ),
              ],
            ),
          ),
        ),
        if (onLock != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            sliver: SliverToBoxAdapter(
              child: _SettingsGroup(
                title: l10n.securitySection,
                children: [
                  _routeTile(
                    Icons.lock_outline_rounded,
                    l10n.appLock,
                    l10n.appLockSubtitle,
                    onLock!,
                  ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverToBoxAdapter(
            child: _SettingsGroup(
              title: l10n.smartInsights,
              children: [
                _routeTile(
                  Icons.auto_awesome_outlined,
                  l10n.aiSpendInsights,
                  l10n.aiSpendInsightsSubtitle,
                  onAi,
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
                title: l10n.accountSection,
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
                      l10n.logOut,
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
