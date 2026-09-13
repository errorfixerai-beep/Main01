import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../providers/language_provider.dart';

class ReferEarnScreen extends StatelessWidget {
  const ReferEarnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user ?? {};
    final code = (user['referralCode'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('refer_earn'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ⚠️ FIX (Boss request — "bada sa plum background hata do, isko
          // transparent karo"): was a solid AppColors.gradient container.
          // Swapped to the app's neutral bordered-card style (card2 +
          // border), with the icon sitting in a soft purple-tinted
          // circle instead of white-on-gradient. Same content, same
          // layout — just not a big solid color block anymore.
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.surfaces.card2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.surfaces.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.card_giftcard_rounded, color: AppColors.purple, size: 30),
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('invite_friends_earn'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr('refer_earn_body'),
                  style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(context.tr('your_referral_code'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(code.isEmpty ? '—' : code, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: code.isEmpty ? null : () {
                    Clipboard.setData(ClipboardData(text: code));
                    showToast(context, context.tr('referral_code_copied'), isSuccess: true);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          GradientButton(
            label: context.tr('share_invite'),
            icon: Icons.share_outlined,
            onPressed: code.isEmpty ? null : () {
              SharePlus.instance.share(ShareParams(
                text: context.tr('share_invite_message').replaceAll('%s', code),
              ));
            },
          ),
          const SizedBox(height: 24),

          Text(context.tr('how_it_works'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _step(context, Icons.ios_share_rounded, context.tr('refer_step_1')),
          _step(context, Icons.person_add_alt_1_rounded, context.tr('refer_step_2')),
          _step(context, Icons.diamond_rounded, context.tr('refer_step_3')),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: const BoxDecoration(gradient: AppColors.gradient, shape: BoxShape.circle),
            child: Center(child: Icon(icon, color: Colors.white, size: 15)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }
}