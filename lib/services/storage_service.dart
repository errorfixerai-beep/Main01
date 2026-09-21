import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static const _accessTokenKey = 'tp_access_token';
  static const _refreshTokenKey = 'tp_refresh_token';
  static const _onboardedKey = 'tp_onboarded';
  static const _authRateLimitKey = 'tp_auth_rate_limit';
  static const _appIntegrityKey = 'tp_app_integrity_token';
  static const _diamondBalanceKey = 'tp_protected_diamond_balance';
  static const _diamondBalanceHashKey = 'tp_protected_diamond_hash';

  static Future<String?> getAccessToken() =>
      _secureStorage.read(key: _accessTokenKey);

  static Future<void> setAccessToken(String token) =>
      _secureStorage.write(key: _accessTokenKey, value: token);

  static Future<String?> getRefreshToken() =>
      _secureStorage.read(key: _refreshTokenKey);

  static Future<void> setRefreshToken(String token) =>
      _secureStorage.write(key: _refreshTokenKey, value: token);

  static Future<void> clearTokens() async {
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
  }

  static Future<bool> isOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardedKey) ?? false;
  }

  static Future<void> setOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
  }

  static Future<Map<String, dynamic>> getAuthRateLimitState() async {
    final raw = await _secureStorage.read(key: _authRateLimitKey);
    if (raw == null || raw.isEmpty)
      return {'failedAttempts': 0, 'lockUntilEpochMs': 0};
    try {
      final decoded = Map<String, dynamic>.from(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
      return decoded;
    } catch (_) {
      return {'failedAttempts': 0, 'lockUntilEpochMs': 0};
    }
  }

  static Future<void> saveAuthRateLimitState(Map<String, dynamic> state) async {
    final raw = jsonEncode(state);
    await _secureStorage.write(key: _authRateLimitKey, value: raw);
  }

  static Future<void> clearAuthRateLimitState() async {
    await _secureStorage.delete(key: _authRateLimitKey);
  }

  static Future<bool> isAuthLocked() async {
    final state = await getAuthRateLimitState();
    final lockUntil = state['lockUntilEpochMs'] as int? ?? 0;
    final remaining = lockUntil > DateTime.now().millisecondsSinceEpoch;
    if (!remaining) {
      await clearAuthRateLimitState();
    }
    return remaining;
  }

  static Future<void> recordAuthFailure() async {
    final state = await getAuthRateLimitState();
    final now = DateTime.now().millisecondsSinceEpoch;
    final failedAttempts = (state['failedAttempts'] as int? ?? 0) + 1;
    int lockUntil = state['lockUntilEpochMs'] as int? ?? 0;
    if (failedAttempts >= 4) {
      lockUntil = now + const Duration(hours: 1).inMilliseconds;
    }
    await saveAuthRateLimitState(
        {'failedAttempts': failedAttempts, 'lockUntilEpochMs': lockUntil});
  }

  static Future<void> clearSuccessfulAuthState() async {
    await clearAuthRateLimitState();
  }

  static String computeAppIntegrityToken(
      String packageName, String appVersion, String buildNumber) {
    final payload =
        '$packageName:$appVersion:$buildNumber:${const String.fromEnvironment('FLUTTER_BUILD_MODE', defaultValue: 'debug')}';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  static Future<String> getAppIntegrityToken() async {
    return (await _secureStorage.read(key: _appIntegrityKey)) ?? '';
  }

  static Future<void> setAppIntegrityToken(String token) async {
    await _secureStorage.write(key: _appIntegrityKey, value: token);
  }

  static Future<int> getDiamondBalance({int fallback = 0}) async {
    final raw = await _secureStorage.read(key: _diamondBalanceKey);
    final hash = await _secureStorage.read(key: _diamondBalanceHashKey);
    if (raw == null || hash == null || raw.isEmpty) return fallback;
    final balance = int.tryParse(raw) ?? 0;
    final expectedHash = sha256
        .convert(utf8.encode(
            '$balance:${const String.fromEnvironment('FLUTTER_BUILD_MODE', defaultValue: 'debug')}'))
        .toString();
    if (expectedHash != hash) return fallback;
    return balance;
  }

  static Future<void> setDiamondBalance(int balance) async {
    final hash = sha256
        .convert(utf8.encode(
            '$balance:${const String.fromEnvironment('FLUTTER_BUILD_MODE', defaultValue: 'debug')}'))
        .toString();
    await _secureStorage.write(
        key: _diamondBalanceKey, value: balance.toString());
    await _secureStorage.write(key: _diamondBalanceHashKey, value: hash);
  }
}
