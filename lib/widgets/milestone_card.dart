import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

String formatMilestone(num n) {
  String trim(double v) => v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  if (n >= 1000000) return '${trim(n / 1000000)}M';
  if (n >= 1000) return '${trim(n / 1000)}K';
  return n.toString();
}

/// The shareable achievement card. Wrap in RepaintBoundary to export as PNG.
class MilestoneCard extends StatelessWidget {
  final String type; // 'subscribers' | 'views'
  final int value;
  final String channelTitle;
  final String? videoTitle;

  const MilestoneCard({
    super.key,
    required this.type,
    required this.value,
    required this.channelTitle,
    this.videoTitle,
  });

  @override
  Widget build(BuildContext context) {
    final v = formatMilestone(value);
    final isSubs = type == 'subscribers';

    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.pink, AppColors.purple],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.purpleLight.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipOval(
                child: Image.asset('assets/splash.png', width: 30, height: 30, fit: BoxFit.cover),
              ),
              const SizedBox(width: 8),
              const Text(
                'TubePilot',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.4),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            width: 150,
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.18),
              border: Border.all(color: AppColors.diamond, width: 6),
              boxShadow: [BoxShadow(color: AppColors.diamond.withValues(alpha: 0.35), blurRadius: 24)],
            ),
            child: Text(
              v,
              style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Congratulations!',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            isSubs ? 'You reached $v subscribers' : 'Your latest video hit $v views',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
          ),
          if (!isSubs && (videoTitle ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              videoTitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              channelTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}