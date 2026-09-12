import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/brand_icons.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _features = [
    _Feature(icon: Icons.cloud_upload_rounded, titleKey: 'feature_multi_platform_title', descKey: 'feature_multi_platform_desc'),
    _Feature(icon: Icons.folder_special_rounded, titleKey: 'feature_drive_title', descKey: 'feature_drive_desc'),
    _Feature(icon: Icons.schedule_send_rounded, titleKey: 'feature_scheduling_title', descKey: 'feature_scheduling_desc'),
    _Feature(icon: Icons.auto_awesome_rounded, titleKey: 'feature_ai_title', descKey: 'feature_ai_desc'),
    _Feature(icon: Icons.lock_clock_rounded, titleKey: 'feature_privacy_title', descKey: 'feature_privacy_desc'),
    _Feature(icon: Icons.notifications_active_rounded, titleKey: 'feature_notif_title', descKey: 'feature_notif_desc'),
    _Feature(icon: Icons.diamond_rounded, titleKey: 'feature_credit_title', descKey: 'feature_credit_desc'),
    _Feature(icon: Icons.card_giftcard_rounded, titleKey: 'feature_refer_title', descKey: 'feature_refer_desc'),
    _Feature(icon: Icons.dark_mode_rounded, titleKey: 'feature_theme_title', descKey: 'feature_theme_desc'),
  ];

  static const _steps = [
    _Step(number: '1', titleKey: 'step_connect_title', descKey: 'step_connect_desc'),
    _Step(number: '2', titleKey: 'step_upload_title', descKey: 'step_upload_desc'),
    _Step(number: '3', titleKey: 'step_relax_title', descKey: 'step_relax_desc'),
  ];

  static const _platforms = [
    _Platform(name: 'YouTube', descKey: 'platform_youtube_desc'),
  ];

  static const _storyParagraphs = [
    _StoryParagraph(
      heading: 'Where It Started',
      body:
          'Tube Pilot began with a simple, familiar frustration: creators building an audience across YouTube, Facebook, and Instagram were stuck '
          're-uploading the same video three separate times, on three separate apps, writing three separate captions, and manually tracking which '
          'platform still needed a thumbnail or a schedule slot. None of that busywork made the content itself any better — it just ate the hours '
          'that should have gone into making the next video. Tube Pilot exists to give creators that time back.',
    ),
    _StoryParagraph(
      heading: 'What We Believe',
      body:
          'We built this app around one guiding idea: a creator\'s job is to make things worth watching, not to become a part-time platform-ops '
          'manager. Every feature in Tube Pilot — bulk uploads, cross-platform scheduling, AI-assisted titles and captions, SEO scoring, competitor '
          'tracking — exists to shrink the distance between "I finished editing" and "it\'s live everywhere it needs to be," so more of a creator\'s '
          'week goes toward the work only they can do.',
    ),
    _StoryParagraph(
      heading: 'How We Build',
      body:
          'We treat the pipes as seriously as the polish. OAuth, tokens, and payments are handled the way anything holding real accounts and real '
          'money should be — verified server-side, never trusted from the client alone, and built to fail safely (a failed upload refunds its cost '
          'automatically rather than silently keeping it). The visible parts of the app — the Neon Dusk and Plum themes, the clean platform picker, '
          'the one-tap scheduler — are the surface. Underneath, the priority has always been: don\'t lose a creator\'s upload, and don\'t touch their '
          'wallet unless the job actually completed.',
    ),
    _StoryParagraph(
      heading: 'Where We\'re Headed',
      body:
          'Tube Pilot keeps growing in the direction creators actually ask for — more Creator OS tools (AI ideas, SEO scoring, channel audits, '
          'competitor radar), tighter automation for scheduling, and support for wherever audiences move next. This is still early. What stays '
          'constant is the same starting question: does this feature give a creator back time, clarity, or reach — and if it doesn\'t, it doesn\'t '
          'ship.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('about_app_bar_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ⚠️ FIX (Boss request): removed the top icon + "Tube Pilot" +
          // tagline block — the AppBar title already says "About App", this
          // duplicate branding block right below it isn't needed. Content
          // now starts directly at "What is Tube Pilot".
          const SizedBox(height: 8),

          // ---------------- What is Tube Pilot ----------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('what_is_tubepilot'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(
                  context.tr('what_is_tubepilot_body'),
                  style: TextStyle(color: context.surfaces.textDim, fontSize: 13.5, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---------------- Our Story ----------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('our_story_title'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ..._storyParagraphs.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: p.heading == null
                          ? Text(p.body, style: TextStyle(color: context.surfaces.textDim, fontSize: 13.5, height: 1.6))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.heading!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 6),
                                Text(p.body, style: TextStyle(color: context.surfaces.textDim, fontSize: 13.5, height: 1.6)),
                              ],
                            ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ---------------- Supported Platforms ----------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('supported_platforms_title'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                for (int i = 0; i < _platforms.length; i++) ...[
                  _PlatformRow(platform: _platforms[i]),
                  if (i != _platforms.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---------------- Features ----------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('features_title'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                for (int i = 0; i < _features.length; i++) ...[
                  _FeatureRow(feature: _features[i]),
                  if (i != _features.length - 1) const SizedBox(height: 16),
                ],
                const SizedBox(height: 16),
                Divider(color: context.surfaces.border, height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.purple, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      context.tr('app_version_label'),
                      style: TextStyle(color: context.surfaces.textDim, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---------------- How it works ----------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('how_it_works_title'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                for (int i = 0; i < _steps.length; i++) ...[
                  _StepRow(step: _steps[i]),
                  if (i != _steps.length - 1) const SizedBox(height: 18),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---------------- Why Tube Pilot ----------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('why_creators_title'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _WhyRow(icon: Icons.speed_rounded, text: context.tr('why_speed')),
                const SizedBox(height: 10),
                _WhyRow(icon: Icons.hub_rounded, text: context.tr('why_hub')),
                const SizedBox(height: 10),
                _WhyRow(icon: Icons.auto_mode_rounded, text: context.tr('why_automation')),
                const SizedBox(height: 10),
                _WhyRow(icon: Icons.support_agent_rounded, text: context.tr('why_support')),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ---------------- Signature footer (bottom-right only) ----------------
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  context.tr('developed_powered_by'),
                  style: TextStyle(color: context.surfaces.textDim, fontSize: 11, letterSpacing: 0.3),
                ),
                const SizedBox(height: 10),
                Image.asset(
                  'assets/signature.png',
                  height: 46,
                  errorBuilder: (_, __, ___) => Text(
                    'Anik Kesharwani',
                    style: TextStyle(
                      fontFamily: 'cursive',
                      fontSize: 22,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      color: context.surfaces.textDim,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Mr. Anik Kesharwani',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(context.tr('ceo_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11, letterSpacing: 1)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---------------- Footer ----------------
          Center(
            child: Text(
              _fmt(context.tr('about_footer_rights'), DateTime.now().year),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

String _fmt(String template, Object value) => template.replaceFirst('%d', '$value').replaceFirst('%s', '$value');

class _Feature {
  final IconData icon;
  final String titleKey;
  final String descKey;
  const _Feature({required this.icon, required this.titleKey, required this.descKey});
}

class _Step {
  final String number;
  final String titleKey;
  final String descKey;
  const _Step({required this.number, required this.titleKey, required this.descKey});
}

class _Platform {
  final String name;
  final String descKey;
  const _Platform({required this.name, required this.descKey});
}

class _StoryParagraph {
  final String? heading;
  final String body;
  const _StoryParagraph({this.heading, required this.body});
}

class _FeatureRow extends StatelessWidget {
  final _Feature feature;
  const _FeatureRow({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(feature.icon, color: AppColors.green, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(feature.titleKey),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                context.tr(feature.descKey),
                style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final _Step step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(gradient: AppColors.gradient, shape: BoxShape.circle),
          child: Center(
            child: Text(
              step.number,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(step.titleKey),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                context.tr(step.descKey),
                style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlatformRow extends StatelessWidget {
  final _Platform platform;
  const _PlatformRow({required this.platform});

  Widget _logoFor(String name) {
    switch (name) {
      case 'YouTube':
        return const YoutubeIcon(size: 18);
      case 'Facebook':
        return const FacebookIcon(size: 18);
      case 'Instagram':
        return const InstagramIcon(size: 18);
      default:
        return const Icon(Icons.public_rounded, size: 18);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.purple.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: _logoFor(platform.name),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(platform.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(context.tr(platform.descKey), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _WhyRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _WhyRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.purple, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: context.surfaces.textDim, fontSize: 13, height: 1.45),
          ),
        ),
      ],
    );
  }
}