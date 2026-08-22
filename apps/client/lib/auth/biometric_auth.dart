abstract class BiometricAuth {
  Future<bool> isAvailable();

  Future<bool> authenticate({required String reason});
}

class UnavailableBiometricAuth implements BiometricAuth {
  const UnavailableBiometricAuth();

  @override
  Future<bool> authenticate({required String reason}) async => false;

  @override
  Future<bool> isAvailable() async => false;
}

class MemoryBiometricAuth implements BiometricAuth {
  MemoryBiometricAuth({this.available = true, this.succeeds = true});

  bool available;
  bool succeeds;
  var authenticateCount = 0;

  @override
  Future<bool> authenticate({required String reason}) async {
    authenticateCount += 1;
    return available && succeeds;
  }

  @override
  Future<bool> isAvailable() async => available;
}
