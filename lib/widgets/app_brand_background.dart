import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The shared "off-white base + faint play-icon watermark" background
/// (same look as Splash) — factored out so Onboarding, Login/Signup, and
/// Profile Setup can all share exactly one implementation instead of
/// copy-pasted per screen. Splash screen itself is untouched and keeps
/// its own inline version.
class AppBrandBackground extends StatelessWidget {
  final Widget child;
  const AppBrandBackground({super.key, required this.child});

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
    return Container(
      color: const Color(0xFFFAF7FC),
      child: Stack(
        children: [
          Positioned.fill(child: _watermarkPattern()),
          child,
        ],
      ),
    );
  }
}