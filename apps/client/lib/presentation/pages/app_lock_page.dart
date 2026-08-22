import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/app_lock_store.dart';
import '../../l10n/l10n.dart';
import '../providers.dart';
import '../widgets/ledgerly_layout.dart';

class AppLockPage extends ConsumerStatefulWidget {
  const AppLockPage({super.key});

  @override
  ConsumerState<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends ConsumerState<AppLockPage> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _enable() async {
    final l10n = l10nOf(context);
    if (!isValidAppLockPin(_pin.text)) {
      setState(() => _error = l10n.invalidPin);
      return;
    }
    if (_pin.text != _confirm.text) {
      setState(() => _error = l10n.pinMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(appLockControllerProvider).enable(_pin.text);
      _pin.clear();
      _confirm.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final l10n = l10nOf(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(appLockControllerProvider).disable(_pin.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : l10n.wrongPin;
      if (ok) {
        _pin.clear();
        _confirm.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final lock = ref.watch(appLockControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appLock)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LedgerlySection(
              child: Text(l10n.appLockBody),
            ),
            const SizedBox(height: 12),
            LedgerlySection(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.enableAppLock),
                    value: lock.enabled,
                    onChanged: null,
                  ),
                  TextField(
                    key: const Key('app-lock-settings-pin'),
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: InputDecoration(
                      labelText: l10n.appLockPin,
                      hintText: l10n.appLockPinHint,
                      errorText: _error,
                      counterText: '',
                    ),
                  ),
                  if (!lock.enabled) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('app-lock-settings-confirm'),
                      controller: _confirm,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      decoration: InputDecoration(
                        labelText: l10n.appLockPinConfirm,
                        counterText: '',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('app-lock-save'),
                    onPressed: _busy
                        ? null
                        : lock.enabled
                            ? _disable
                            : _enable,
                    child: Text(
                      lock.enabled ? l10n.disableAppLock : l10n.enableAppLock,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
