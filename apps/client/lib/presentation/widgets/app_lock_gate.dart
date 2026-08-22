import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import '../providers.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(appLockControllerProvider).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockControllerProvider);
    if (!lock.loaded || !lock.locked) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        const _AppLockScrim(),
      ],
    );
  }
}

class _AppLockScrim extends ConsumerStatefulWidget {
  const _AppLockScrim();

  @override
  ConsumerState<_AppLockScrim> createState() => _AppLockScrimState();
}

class _AppLockScrimState extends ConsumerState<_AppLockScrim> {
  final _pin = TextEditingController();
  var _busy = false;
  var _triedBiometric = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_tryBiometric());
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    if (_triedBiometric || !mounted) return;
    _triedBiometric = true;
    final lock = ref.read(appLockControllerProvider);
    if (!lock.biometricEnabled) return;
    await lock.unlockWithBiometrics(
      reason: l10nOf(context).unlockWithBiometrics,
    );
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(appLockControllerProvider).unlock(_pin.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : l10nOf(context).wrongPin;
      if (ok) _pin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final lock = ref.watch(appLockControllerProvider);
    return Material(
      color: LedgerlyColors.canvas.withValues(alpha: 0.97),
      child: SafeArea(
        child: PopScope(
          canPop: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      l10n.appLockedTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      key: const Key('app-lock-pin'),
                      controller: _pin,
                      obscureText: true,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      autofocus: !lock.biometricEnabled,
                      onSubmitted: (_) => _unlock(),
                      decoration: InputDecoration(
                        labelText: l10n.appLockPin,
                        hintText: l10n.appLockPinHint,
                        errorText: _error,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('app-lock-unlock'),
                      onPressed: _busy ? null : _unlock,
                      child: Text(l10n.unlock),
                    ),
                    if (lock.biometricEnabled) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        key: const Key('app-lock-biometric'),
                        onPressed: _busy
                            ? null
                            : () => lock.unlockWithBiometrics(
                                  reason: l10n.unlockWithBiometrics,
                                ),
                        icon: const Icon(Icons.fingerprint),
                        label: Text(l10n.unlockWithBiometrics),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
