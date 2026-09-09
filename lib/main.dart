import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'providers/theme_provider.dart';
import 'providers/language_provider.dart';
import 'services/auth_provider.dart';
import 'services/api_service.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/meta_page_picker_screen.dart';
import 'widgets/common.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// ⚠️ TODO: replace with your real OneSignal App ID
const String oneSignalAppId = '205c5c05-ad00-4e06-a8f4-d7ff9245ccfd';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⚠️ FIX (Boss request: native white screen was showing 6-7s): keep only
  // the FAST local read (SharedPreferences) before runApp() — this still
  // prevents the old English-flash bug. The SLOW network-dependent
  // Firebase/OneSignal init calls have been moved below, AFTER runApp(),
  // so they no longer block the first Flutter frame from being drawn.
  final languageProvider = LanguageProvider();
  await languageProvider.loadSaved();

  runApp(TubePilotApp(languageProvider: languageProvider));

  // Fire-and-forget: runs in the background while the (already-visible)
  // Dart SplashScreen is up. Same calls, same try/catch, same behavior —
  // only WHEN they run has changed, not WHAT they do.
  _initBackgroundServices();
}

Future<void> _initBackgroundServices() async {
  try {
    await Firebase.initializeApp().timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw Exception('Firebase.initializeApp() timed out after 8s'),
    );
  } catch (e) {
    debugPrint('⚠️ Firebase init failed/skipped, continuing without push notifications: $e');
  }

  try {
    OneSignal.initialize(oneSignalAppId);
    OneSignal.Notifications.requestPermission(true);
  } catch (e) {
    debugPrint('⚠️ OneSignal init failed/skipped, continuing without diamond-alert push: $e');
  }
}

class TubePilotApp extends StatefulWidget {
  final LanguageProvider languageProvider;
  const TubePilotApp({super.key, required this.languageProvider});
  @override
  State<TubePilotApp> createState() => _TubePilotAppState();
}

class _TubePilotAppState extends State<TubePilotApp> {
  StreamSubscription<Uri>? _linkSub;

  final AuthProvider _authProvider = AuthProvider();
  bool _pushInitDone = false;

  Uri? _lastHandledUri;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _initOneSignalPlayerIdSync();

    _authProvider.addListener(_maybeInitPush);
    _maybeInitPush(); // covers "already logged in, app just reopened"
  }

  void _maybeInitPush() {
    final isLoggedIn = _authProvider.user != null;
    if (!isLoggedIn) {
      _pushInitDone = false;
      return;
    }
    if (_pushInitDone) return;
    _pushInitDone = true;
    PushService.initAfterLogin();
  }

  void _initOneSignalPlayerIdSync() {
    try {
      final existingId = OneSignal.User.pushSubscription.id;
      if (existingId != null) {
        ApiService.instance.registerOneSignalPlayerId(existingId).catchError((_) {});
      }
      OneSignal.User.pushSubscription.addObserver((state) {
        final playerId = OneSignal.User.pushSubscription.id;
        if (playerId != null) {
          ApiService.instance.registerOneSignalPlayerId(playerId).catchError((_) {});
        }
      });
    } catch (e) {
      debugPrint('⚠️ OneSignal player id sync failed to start: $e');
    }
  }

  Future<void> _initDeepLinks() async {
    try {
      final appLinks = AppLinks();

      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }

      _linkSub = appLinks.uriLinkStream.listen(_handleDeepLink);
    } catch (e) {
      debugPrint('⚠️ Deep link listener failed to start: $e');
    }
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme != 'tubepilot' || uri.host != 'oauth-success') return;

    if (_lastHandledUri == uri) return;
    _lastHandledUri = uri;

    final hasYoutubeParam = uri.queryParameters.containsKey('youtube_connected');
    final hasDriveParam = uri.queryParameters.containsKey('drive_connected');
    final hasMetaParam = uri.queryParameters.containsKey('meta_connected');
    final ctx = navigatorKey.currentContext;

    bool metaSuccess = false;
    bool metaMultiplePages = false;

    if (hasYoutubeParam) {
      final connected = uri.queryParameters['youtube_connected'] == '1';
      if (ctx != null) {
        showToast(ctx, connected ? 'YouTube channel connected!' : 'Failed to connect YouTube channel', isSuccess: connected, isError: !connected);
      }
    } else if (hasDriveParam) {
      final connected = uri.queryParameters['drive_connected'] == '1';
      if (ctx != null) {
        showToast(ctx, connected ? 'Google Drive connected!' : 'Failed to connect Google Drive', isSuccess: connected, isError: !connected);
      }
    } else if (hasMetaParam) {
      metaSuccess = uri.queryParameters['meta_connected'] == '1';
      metaMultiplePages = uri.queryParameters['multiple_pages'] == '1';
      if (ctx != null && !metaMultiplePages) {
        showToast(ctx, metaSuccess ? 'Facebook / Instagram connected!' : 'Failed to connect Facebook / Instagram', isSuccess: metaSuccess, isError: !metaSuccess);
      }
    }

    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (route) => false,
    );

    if (hasMetaParam && metaSuccess && metaMultiplePages) {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const MetaPagePickerScreen()));
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _authProvider.removeListener(_maybeInitPush);
    widget.languageProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: _authProvider),
        ChangeNotifierProvider<LanguageProvider>.value(value: widget.languageProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return LanguageScope(
            languageProvider: widget.languageProvider,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              title: 'TubePilot',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: themeProvider.themeMode,
              home: const SplashScreen(),
            ),
          );
        },
      ),
    );
  }
}