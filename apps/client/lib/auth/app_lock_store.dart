import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../platform/secure_storage.dart';
import 'biometric_auth.dart';

abstract interface class AppLockStore {
  Future<String?> readPin();

  Future<void> writePin(String pin);

  Future<bool> readBiometricEnabled();

  Future<void> writeBiometricEnabled(bool enabled);

  Future<void> clear();
}

class MemoryAppLockStore implements AppLockStore {
  MemoryAppLockStore({this.pin, this.biometricEnabled = false});

  String? pin;
  bool biometricEnabled;

  @override
  Future<void> clear() async {
    pin = null;
    biometricEnabled = false;
  }

  @override
  Future<bool> readBiometricEnabled() async => biometricEnabled;

  @override
  Future<String?> readPin() async => pin;

  @override
  Future<void> writeBiometricEnabled(bool enabled) async {
    biometricEnabled = enabled;
  }

  @override
  Future<void> writePin(String pin) async {
    this.pin = pin;
  }
}

class PlatformAppLockStore implements AppLockStore {
  PlatformAppLockStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? ledgerSecureStorage;

  static const pinStorageKey = 'ledgerly.app_lock.pin.v1';
  static const biometricStorageKey = 'ledgerly.app_lock.biometric.v1';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<void> clear() async {
    try {
      await _secureStorage.delete(key: pinStorageKey);
      await _secureStorage.delete(key: biometricStorageKey);
    } catch (_) {}
  }

  @override
  Future<bool> readBiometricEnabled() async {
    try {
      return await _secureStorage.read(key: biometricStorageKey) == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> readPin() async {
    try {
      return await _secureStorage.read(key: pinStorageKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeBiometricEnabled(bool enabled) {
    return _secureStorage.write(
      key: biometricStorageKey,
      value: enabled ? '1' : '0',
    );
  }

  @override
  Future<void> writePin(String pin) {
    return _secureStorage.write(key: pinStorageKey, value: pin);
  }
}

AppLockStore createPlatformAppLockStore() => PlatformAppLockStore();

bool isValidAppLockPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

class AppLockController extends ChangeNotifier {
  AppLockController({
    required AppLockStore store,
    BiometricAuth biometric = const UnavailableBiometricAuth(),
  })  : _store = store,
        _biometric = biometric;

  final AppLockStore _store;
  final BiometricAuth _biometric;
  var _loaded = false;
  var _enabled = false;
  var _locked = false;
  var _biometricEnabled = false;
  var _disposed = false;

  bool get loaded => _loaded;

  bool get enabled => _enabled;

  bool get locked => _locked;

  bool get biometricEnabled => _biometricEnabled;

  Future<bool> get canUseBiometrics => _biometric.isAvailable();

  Future<void> load() async {
    final pin = await _store.readPin();
    final biometricEnabled = await _store.readBiometricEnabled();
    if (_disposed) return;
    _enabled = pin != null && pin.isNotEmpty;
    _biometricEnabled = _enabled && biometricEnabled;
    _locked = _enabled;
    _loaded = true;
    notifyListeners();
  }

  void lock() {
    if (!_enabled || _locked) return;
    _locked = true;
    notifyListeners();
  }

  Future<bool> unlock(String pin) async {
    final stored = await _store.readPin();
    if (stored == null || stored != pin) return false;
    if (_disposed) return true;
    _locked = false;
    notifyListeners();
    return true;
  }

  Future<bool> unlockWithBiometrics({required String reason}) async {
    if (!_enabled || !_locked || !_biometricEnabled) return false;
    final ok = await _biometric.authenticate(reason: reason);
    if (!ok || _disposed) return ok;
    _locked = false;
    notifyListeners();
    return true;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (!_enabled) return;
    if (enabled && !await _biometric.isAvailable()) return;
    await _store.writeBiometricEnabled(enabled);
    if (_disposed) return;
    _biometricEnabled = enabled;
    notifyListeners();
  }

  Future<void> enable(String pin) async {
    if (!isValidAppLockPin(pin)) {
      throw ArgumentError.value(pin, 'pin', 'must be 4 to 8 digits');
    }
    await _store.writePin(pin);
    if (_disposed) return;
    _enabled = true;
    _locked = false;
    _loaded = true;
    notifyListeners();
  }

  Future<bool> disable(String pin) async {
    final stored = await _store.readPin();
    if (stored == null || stored != pin) return false;
    await _store.clear();
    if (_disposed) return true;
    _enabled = false;
    _biometricEnabled = false;
    _locked = false;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
