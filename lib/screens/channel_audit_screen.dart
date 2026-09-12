import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import 'upload_screen.dart';
import 'diamond_store_screen.dart';

/// Screen 6/7 — GET /api/analytics/audit.
class ChannelAuditScreen extends StatefulWidget {
  const ChannelAuditScreen({super.key});
  @override
  State<ChannelAuditScreen> createState() => _ChannelAuditScreenState();
}

class _ChannelAuditScreenState extends State<ChannelAuditScreen> {
  bool _loading = true;
  Map<String, dynamic>? _audit;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.instance.getChannelAudit();
      setState(() => _audit = res['audit']);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // A simple, transparent rollup of the backend's real metrics into one
  // headline number — NOT a separate AI/ML score. Weighted so an inactive
  // channel (no uploads this week) can't hide behind a decent engagement %.
  int _healthScore(Map<String, dynamic> audit) {
    final engagement = (audit['engagementPct'] as num?)?.toDouble();
    final recentUploads = (audit['recentUploadsLast7Days'] as num?)?.toInt() ?? 0;
    final engagementComponent = engagement == null ? 50.0 : (engagement.clamp(0, 10) / 10 * 60);
    final activityComponent = recentUploads == 0 ? 0.0 : (recentUploads.clamp(0, 4) / 4 * 40);
    return (engagementComponent + activityComponent).round().clamp(0, 100).toInt();
  }

  String _healthLabel(int score) {
    if (score >= 80) return context.tr('audit_health_excellent');
    if (score >= 60) return context.tr('audit_health_good');
    if (score >= 35) return context.tr('audit_health_needs_attention');
    return context.tr('audit_health_at_risk');
  }

  Color _healthColor(int score) {
    if (score >= 80) return AppColors.green;
    if (score >= 60) return AppColors.purple;
    if (score >= 35) return const Color(0xFFF5A623);
    return AppColors.red;
  }

  void _goToUpgrade() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen()));
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'description':
        return Icons.description_outlined;
      case 'banner':
        return Icons.image_outlined;
      case 'title':
        return Icons.badge_outlined;
      case 'engagement':
        return Icons.favorite_outline_rounded;
      case 'uploads':
        return Icons.cloud_upload_outlined;
      case 'shorts':
        return Icons.movie_filter_outlined;
      default:
        return Icons.tips_and_updates_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('channel_audit_title'))),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.purple,
        child: _loading
            ? const LoadingView()
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 60),
                    EmptyView(message: _error!, icon: Icons.error_outline_rounded),
                  ])
                : _audit == null
                    ? EmptyView(message: context.tr('audit_no_data'), icon: Icons.fact_check_outlined)
                    : _buildAudit(_audit!),
      ),
    );
  }

  Widget _buildAudit(Map<String, dynamic> audit) {
    final score = _healthScore(audit);
    final color = _healthColor(score);
    final recommendations = (audit['recommendations'] as List? ?? []).cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ⚠️ FIX (Boss correction — "background mein koi color nahi hona
        // chahiye, health score ko sahi se colorful dikhao"): dropped the
        // solid `AppColors.gradient` fill in favour of the same
        // transparent/bordered look used by every other card on this
        // screen. The gauge itself now carries the color instead of the
        // card background.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            Text(context.tr('audit_channel_health'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            _healthGauge(score, color),
            const SizedBox(height: 4),
            AppBadge(label: _healthLabel(score), color: color),
          ]),
        ),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            StatCard(
              label: context.tr('audit_engagement_pct'),
              value: audit['engagementPct'] != null ? '${audit['engagementPct']}%' : '—',
            ),
            StatCard(
              label: context.tr('audit_shorts_long_ratio'),
              value: audit['weeklyShortToLongRatio'] != null ? '${audit['weeklyShortToLongRatio']}' : '—',
            ),
            StatCard(label: context.tr('audit_subscribers'), value: '${audit['subscriberCount'] ?? '—'}'),
            StatCard(label: context.tr('audit_uploads_7d'), value: '${audit['recentUploadsLast7Days'] ?? 0}'),
          ],
        ),
        const SizedBox(height: 24),
        Text(context.tr('audit_recommendations'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...recommendations.map((r) => _recommendationCard(r)),
      ],
    );
  }

  // ⚠️ FIX (Boss correction — "health score ko sahi se colorful
  // dikhao"): the filled arc and center number were hardcoded to plain
  // white/white-alpha (made sense on the old solid-gradient card, not on
  // a transparent one). Now uses the already-computed `_healthColor`
  // (green ≥80, purple ≥60, orange ≥35, red below) so the ring and
  // number both reflect the actual score, and the unfilled remainder of
  // the ring uses the theme's border color instead of a translucent
  // white so it reads correctly on a plain background.
  Widget _healthGauge(int score, Color color) {
    return SizedBox(
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 0,
              centerSpaceRadius: 52,
              sections: [
                PieChartSectionData(value: score.toDouble(), color: color, radius: 20, showTitle: false),
                PieChartSectionData(value: (100 - score).toDouble(), color: context.surfaces.border, radius: 20, showTitle: false),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$score', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: color)),
              Text('/100', style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recommendationCard(Map<String, dynamic> rec) {
    final type = rec['type'] as String? ?? '';
    final message = rec['message'] as String? ?? '';
    final prompt = rec['prompt'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(_iconForType(type), color: AppColors.purple, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 13, height: 1.4))),
          ]),

          // ⚠️ NEW (Boss request — monetization gate): if this gap has a
          // ready-made AI prompt, show a blurred/truncated preview of it
          // plus Copy + Gemini buttons. BOTH buttons deliberately do NOT
          // perform their literal action (copy to clipboard / open
          // Gemini) — tapping either sends the user straight to the
          // Diamond Store, since the actual usable prompt is a paid
          // feature (₹10/month plan, per Boss). This is intentional
          // product behaviour, not a bug.
          if (prompt != null && prompt.isNotEmpty) ...[
            const SizedBox(height: 12),
            _promptPreview(prompt),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _goToUpgrade,
                  icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.diamond),
                  label: Text(context.tr('audit_copy_prompt_btn')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _goToUpgrade,
                  // "Real icon" per Boss request — Gemini's own logo
                  // asset (add assets/gemini_icon.png + register it in
                  // pubspec.yaml). Falls back to a sparkle icon if the
                  // asset is missing so the app never crashes over a
                  // missing image file.
                  icon: Image.asset(
                    'assets/gemini_icon.png',
                    width: 16,
                    height: 16,
                    errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome_rounded, size: 15),
                  ),
                  label: Text(context.tr('audit_open_gemini_btn')),
                ),
              ),
            ]),
          ] else if (type == 'uploads' || type == 'shorts') ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen())),
                icon: const Icon(Icons.upload_rounded, size: 15),
                label: Text(context.tr('audit_upload_now_btn')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Shows only a truncated, blurred slice of the prompt with a fade + lock
  // badge on top — enough to prove a real, specific prompt exists for this
  // gap, not enough to actually read/use it for free.
  Widget _promptPreview(String prompt) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(10)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 44),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 2.4, sigmaY: 2.4),
                child: Text(
                  prompt,
                  style: TextStyle(fontSize: 12, color: context.surfaces.textDim, height: 1.4),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, context.surfaces.card2.withValues(alpha: 0.92)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 13, color: AppColors.diamond),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('audit_prompt_locked_label'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.diamond),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}