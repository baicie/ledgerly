import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../platform/secure_storage.dart';

abstract interface class BackupAutoPasswordStore {
  Future<String?> read();

  Future<void> write(String password);

  Future<void> clear();
}

class PlatformBackupAutoPasswordStore implements BackupAutoPasswordStore {
  PlatformBackupAutoPasswordStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? ledgerSecureStorage;

  static const String storageKey = 'ledgerly.backup.autoPassword.v1';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<String?> read() => _secureStorage.read(key: storageKey);

  @override
  Future<void> write(String password) {
    return _secureStorage.write(key: storageKey, value: password);
  }

  @override
  Future<void> clear() async {
    try {
      await _secureStorage.delete(key: storageKey);
    } catch (_) {}
  }
}

class MemoryBackupAutoPasswordStore implements BackupAutoPasswordStore {
  MemoryBackupAutoPasswordStore({this.password});

  String? password;

  @override
  Future<String?> read() async => password;

  @override
  Future<void> write(String password) async {
    this.password = password;
  }

  @override
  Future<void> clear() async {
    password = null;
  }
}
