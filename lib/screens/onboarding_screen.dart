import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/app_brand_background.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

// Now holds translation KEYS instead of display text — resolved via
// context.tr() when building each page, so swiping/tapping between steps
// always shows the currently selected language. iconAsset is the "real"
// icon image for this step; icon is the fallback if the asset is missing.
class _OnboardingStep {
  final IconData icon;
  final String iconAsset;
  final String titleKey;
  final String descKey;
  const _OnboardingStep(this.icon, this.iconAsset, this.titleKey, this.descKey);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _steps = const [
    _OnboardingStep(Icons.cloud_upload_rounded, 'assets/onboarding_upload.png', 'onboarding_title_1', 'onboarding_desc_1'),
    _OnboardingStep(Icons.phonelink_off_rounded, 'assets/onboarding_anywhere.png', 'onboarding_title_2', 'onboarding_desc_2'),
    _OnboardingStep(Icons.auto_awesome_rounded, 'assets/onboarding_ai.png', 'onboarding_title_3', 'onboarding_desc_3'),
  ];

  int _step = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _finish() async {
    await StorageService.setOnboarded();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _goToStep(int step) {
    _pageController.animateToPage(step, duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ⚠️ FIX (Boss request): same off-white base + watermark as Splash.
      backgroundColor: const Color(0xFFFAF7FC),
      body: AppBrandBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: _finish, child: Text(context.tr('skip'), style: TextStyle(color: context.surfaces.textDim))),
                  ],
                ),
                // ---------------- Swipeable step pages ----------------
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _steps.length,
                    onPageChanged: (i) => setState(() => _step = i),
                    itemBuilder: (_, i) {
                      final s = _steps[i];
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // ⚠️ FIX (Boss request — "peeche jo blur plum
                          // colour dikh raha hai use pura hatao"): the
                          // RadialGradient glow container behind the icon
                          // is removed entirely — this is now a plain,
                          // fully transparent SizedBox, so nothing but the
                          // icon itself renders. Icon itself bumped up
                          // (96 → 116) to compensate visually since the
                          // glow isn't there to fill the space anymore.
                          SizedBox(
                            width: 210,
                            height: 210,
                            child: Center(
                              child: Image.asset(
                                s.iconAsset,
                                width: 116,
                                height: 116,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 116, height: 116,
                                  decoration: const BoxDecoration(gradient: AppColors.gradient, shape: BoxShape.circle),
                                  child: Icon(s.icon, size: 52, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(context.tr(s.titleKey), textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(context.tr(s.descKey), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_steps.length, (i) => GestureDetector(
                    onTap: () => _goToStep(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _step ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _step ? AppColors.purpleLight : context.surfaces.border,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  )),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_step < _steps.length - 1) {
                        _goToStep(_step + 1);
                      } else {
                        _finish();
                      }
                    },
                    child: Text(_step == _steps.length - 1 ? context.tr('get_started') : context.tr('next')),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}