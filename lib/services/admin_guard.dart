import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AdminGuard {
  static const _k = FlutterSecureStorage();
  static const _pinKey = 'admin_pin';
  Future<void> setPin(String pin) async => _k.write(key: _pinKey, value: pin);
  Future<bool> verify(String pin) async {
    final p = await _k.read(key: _pinKey);
    return p != null && p == pin;
  }
}
