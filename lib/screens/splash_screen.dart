import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/storage_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import 'onboarding_screen.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Splash visible for 7 seconds
  static const _minSplashDuration = Duration(seconds: 7);

  late final AnimationController _logoController; // scale/fade-in for the logo
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack);
    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeIn);
    _logoController.forward();

    // ⚠️ REMOVED (Google Play policy fix): upfront Permission.photos /
    // Permission.videos requests were removed from here. Google Play's
    // Photo and Video Permissions policy flags apps that request
    // READ_MEDIA_IMAGES / READ_MEDIA_VIDEO for infrequent, user-initiated
    // access like ours — the correct approach is to let image_picker use
    // the Android Photo Picker (API 33+) reactively, exactly when the user
    // taps "select a video" / "select a thumbnail" on the Upload screen.
    // The Photo Picker needs NO permission grant at all, so there is
    // nothing to request here anymore. See AndroidManifest.xml, where
    // READ_MEDIA_IMAGES / READ_MEDIA_VIDEO are now explicitly removed via
    // tools:node="remove" to stop them being merged in from this package's
    // (and permission_handler's) own manifests.

    _decideNextScreen();
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  Future<void> _decideNextScreen() async {
    final auth = context.read<AuthProvider>();

    await Future.wait([
      auth.loadSession(),
      Future.delayed(_minSplashDuration),
    ]);

    if (!mounted) return;

    Widget next;

    if (auth.isLoggedIn) {
      next = const DashboardScreen();
      PushService.initAfterLogin();
    } else {
      final onboarded = await StorageService.isOnboarded();
      next = onboarded ? const LoginScreen() : const OnboardingScreen();
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => next),
    );
  }

  // ⚠️ FIX (Boss request): the real logo lives at assets/logo.png (add it
  // to pubspec.yaml's flutter/assets list if it isn't already there — a
  // single transparent-background PNG, ideally square, is what this
  // widget expects). Used for BOTH the small lockup mark and the large
  // centered brand mark below, so there's only one source of truth for
  // "what the TubePilot logo looks like" instead of a separate mocked
  // icon in each spot.
  Widget _realLogo({required double size}) {
    return Image.asset(
      'assets/splash.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      // Fallback only fires if assets/logo.png is missing from the
      // project/pubspec — keeps the splash from crashing while the real
      // asset is wired in.
      errorBuilder: (_, __, ___) => Icon(Icons.play_arrow_rounded, color: AppColors.purple, size: size * 0.6),
    );
  }

  // ⚠️ RESTORED (Boss request): the solid light background + faint
  // repeating play-icon watermark pattern that used to sit behind the
  // logo/text. A previous change made the whole Scaffold transparent and
  // removed every decorative shape along with it — that's what turned the
  // splash fully black (it was showing through to the native black
  // launch-screen behind Flutter). This brings back ONLY the background:
  // a light off-white base with faint purple play-icon shapes scattered
  // near the corners, same as the reference look. Nothing about the
  // logo, text, or layout below changed.
  Widget _watermarkPattern() {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.07,
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(vertical: 40),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 30,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemCount: 32,
          itemBuilder: (context, index) => Icon(
            Icons.play_circle_outline_rounded,
            color: AppColors.purple,
            size: 42,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ⚠️ RESTORED: light background color (was Colors.transparent,
      // which let the native black launch background show through).
      backgroundColor: const Color(0xFFFAF7FC),
      body: SafeArea(
        child: Stack(
          children: [
            // Faint watermark pattern behind everything else.
            Positioned.fill(child: _watermarkPattern()),

            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo lockup: "Tube [real logo] Pilot" — same wordmark
                  // as before, but the mock bordered play-icon box in the
                  // middle is now the real logo image.
                  ScaleTransition(
                    scale: _logoScale,
                    child: FadeTransition(
                      opacity: _logoFade,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => AppColors.gradient.createShader(bounds),
                            child: const Text(
                              'Tube',
                              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _realLogo(size: 40),
                          ),
                          ShaderMask(
                            shaderCallback: (bounds) => AppColors.gradient.createShader(bounds),
                            child: const Text(
                              'Pilot',
                              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 60),

                  // Large centered brand mark — real logo only, no
                  // border/box container around it anymore.
                  ScaleTransition(
                    scale: _logoScale,
                    child: FadeTransition(
                      opacity: _logoFade,
                      child: _realLogo(size: 140),
                    ),
                  ),

                  const SizedBox(height: 26),

                  FadeTransition(
                    opacity: _logoFade,
                    child: Text(
                      context.tr('splash_tagline'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.purple, letterSpacing: 0.2),
                    ),
                  ),
                ],
              ),
            ),

            // ⚠️ "Powered by TubePilot" centered at the very bottom of the
            // splash screen.
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: FadeTransition(
                opacity: _logoFade,
                child: Center(
                  child: Text(
                    context.tr('splash_powered_by'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.purple.withValues(alpha: 0.65)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}