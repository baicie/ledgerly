import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AppLockStore {
  Future<String?> readPin();

  Future<void> writePin(String pin);

  Future<void> clear();
}

class MemoryAppLockStore implements AppLockStore {
  MemoryAppLockStore({this.pin});

  String? pin;

  @override
  Future<void> clear() async {
    pin = null;
  }

  @override
  Future<String?> readPin() async => pin;

  @override
  Future<void> writePin(String pin) async {
    this.pin = pin;
  }
}

class PlatformAppLockStore implements AppLockStore {
  PlatformAppLockStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(migrateWithBackup: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const pinStorageKey = 'ledgerly.app_lock.pin.v1';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<void> clear() async {
    try {
      await _secureStorage.delete(key: pinStorageKey);
    } catch (_) {}
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
  Future<void> writePin(String pin) {
    return _secureStorage.write(key: pinStorageKey, value: pin);
  }
}

AppLockStore createPlatformAppLockStore() => PlatformAppLockStore();

bool isValidAppLockPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

class AppLockController extends ChangeNotifier {
  AppLockController({required AppLockStore store}) : _store = store;

  final AppLockStore _store;
  var _loaded = false;
  var _enabled = false;
  var _locked = false;
  var _disposed = false;

  bool get loaded => _loaded;

  bool get enabled => _enabled;

  bool get locked => _locked;

  Future<void> load() async {
    final pin = await _store.readPin();
    if (_disposed) return;
    _enabled = pin != null && pin.isNotEmpty;
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
