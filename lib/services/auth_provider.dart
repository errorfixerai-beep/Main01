import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../services/security_service.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService.instance;

  // google_sign_in v7 is a singleton — no more `GoogleSignIn(...)` constructor.
  // It also requires an explicit, one-time async initialize() call before any
  // other method (signIn/authenticate/signOut) can be used.
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleSignInInitialized = false;

  Map<String, dynamic>? _user;
  bool _loading = true;

  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _loading;
  bool get isAdmin => _user?['role'] == 'admin';

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await _googleSignIn.initialize(serverClientId: AppConfig.googleServerClientId);
    _googleSignInInitialized = true;
  }

  Future<void> loadSession() async {
    _loading = true;
    notifyListeners();
    final token = await StorageService.getAccessToken();
    if (token == null) {
      _loading = false;
      notifyListeners();
      return;
    }
    try {
      final res = await _api.me();
      _user = res['user'];
    } catch (_) {
      await StorageService.clearTokens();
      _user = null;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _saveSessionFromAuthResponse(Map<String, dynamic> res) async {
    await StorageService.setAccessToken(res['accessToken']);
    if (res['refreshToken'] != null) {
      await StorageService.setRefreshToken(res['refreshToken']);
    }
    await StorageService.clearSuccessfulAuthState();
    _user = res['user'];
    notifyListeners();
  }

  Future<void> _guardSensitiveAuth(String action) async {
    final result = await SecurityService.evaluate();
    if (result.isBlocked) {
      throw Exception('Security validation failed for $action: ${result.issues.join(', ')}');
    }
    final locked = await StorageService.isAuthLocked();
    if (locked) {
      throw Exception('Login/Signup limit over. Please try again after 1 hour.');
    }
  }

  Future<void> emailSignup({required String name, required String email, required String password}) async {
    await _guardSensitiveAuth('signup');
    try {
      final res = await _api.signup(name: name, email: email, password: password);
      await _saveSessionFromAuthResponse(res);
    } catch (err) {
      await StorageService.recordAuthFailure();
      rethrow;
    }
  }

  Future<void> emailLogin({required String email, required String password}) async {
    await _guardSensitiveAuth('login');
    try {
      final res = await _api.login(email: email, password: password);
      await _saveSessionFromAuthResponse(res);
    } catch (err) {
      await StorageService.recordAuthFailure();
      rethrow;
    }
  }

  /// Real Google Sign-In flow using the google_sign_in plugin (v7 API),
  /// verified server-side by POST /api/auth/google (same backend endpoint
  /// the web app uses).
  Future<void> googleLogin() async {
    try {
      await _guardSensitiveAuth('google_login');
      await _ensureGoogleSignInInitialized();

      // Clear any cached account so the account picker always shows.
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // signOut can throw if no session exists yet — safe to ignore.
      }

      // v7: signIn() -> authenticate(). It throws GoogleSignInException
      // (e.g. code .canceled) instead of returning null when the user backs out.
      final account = await _googleSignIn.authenticate();

      // v7: `authentication` is now a synchronous getter, not a Future.
      final auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        throw Exception('Could not get Google ID token. Check googleServerClientId in config.dart');
      }

      final res = await _api.googleLogin(idToken);
      await _saveSessionFromAuthResponse(res);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw Exception('Google sign-in cancelled');
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw Exception(
            'Google Sign-In setup issue: the SHA-1 fingerprint or package name registered '
            'in Firebase/Google Cloud doesn\'t match this build. Re-check android/app/build.gradle applicationId, '
            'the SHA-1 in Firebase, and that google-services.json was re-downloaded after adding it.');
      }
      await StorageService.recordAuthFailure();
      rethrow;
    } catch (err) {
      await StorageService.recordAuthFailure();
      rethrow;
    }
  }

  Future<void> setupUsername({required String username, required String language, String? avatar}) async {
    final res = await _api.setupUsername(username: username, language: language, avatar: avatar);
    _user = res['user'];
    notifyListeners();
  }

  Future<void> refreshUser() async {
    try {
      final res = await _api.me();
      _user = res['user'];
      notifyListeners();
    } catch (_) {}
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } catch (_) {}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await StorageService.clearTokens();
    _user = null;
    notifyListeners();
  }
}