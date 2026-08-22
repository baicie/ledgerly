import 'biometric_auth.dart';
import 'biometric_auth_stub.dart'
    if (dart.library.io) 'biometric_auth_io.dart' as impl;

BiometricAuth createPlatformBiometricAuth() => impl.createPlatformBiometricAuth();
