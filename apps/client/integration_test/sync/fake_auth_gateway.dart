// An [AuthGateway] that returns a pre-baked [AuthSession] and ignores
// login / logout calls. Sufficient for the multi-device sync scenarios,
// which only consult `currentSession.bookId` from SyncService.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ledgerly_client/auth/auth_repository.dart';

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({required AuthSession session}) : _session = session;

  final AuthSession _session;
  final List<VoidCallback> _listeners = [];

  AuthSession? _current;

  @override
  AuthSession? get currentSession => _current;

  @override
  Future<AuthSession?> restore() async {
    _current = _session;
    return _session;
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    _current = _session;
    _notify();
    return _session;
  }

  @override
  Future<AuthSession> registerAndLogin({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _current = _session;
    _notify();
    return _session;
  }

  @override
  Future<void> logout() async {
    _current = null;
    _notify();
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _listeners.remove(listener);

  void _notify() {
    for (final l in List<VoidCallback>.from(_listeners)) {
      l();
    }
  }
}
