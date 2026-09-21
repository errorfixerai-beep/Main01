import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import 'upload_screen.dart';
import 'diamond_store_screen.dart';

/// ⚠️ RENAMED (Boss request): "Channel Audit" → "Channel SEO Score" — ties
/// directly to the Diamond package's seoScoreLevel, but with a STRICTER
/// gate than Video SEO Optimizer.
///
/// Rule: the health score + stats grid are ALWAYS shown, on any plan
/// (even no plan at all). Suggestions/recommendations ONLY show when the
/// backend flags `channelSeoUnlocked: true`, which only happens for
/// seoScoreLevel === 'advance' (₹100+ packs). No blurred preview when
/// locked — the recommendations section is replaced by a single upgrade
/// banner, nothing partial is shown.
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen())).then((_) => _load());
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
      appBar: AppBar(title: Text(context.tr('channel_seo_score_title'))),
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
    // Backend always returns `channelSeoUnlocked` + `recommendations`
    // (empty when locked). When true, recommendations always has at least
    // a "healthy" fallback entry if nothing is actually wrong — so this
    // list is ALWAYS rendered when unlocked, regardless of health score,
    // per Boss's "90% ke upar bhi suggestion dikhna chahiye" rule.
    final unlocked = audit['channelSeoUnlocked'] == true;
    final recommendations = (audit['recommendations'] as List? ?? []).cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
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
          childAspectRatio: 1.15,
          children: [
            StatCard(label: context.tr('audit_engagement_pct'), value: audit['engagementPct'] != null ? '${audit['engagementPct']}%' : '—'),
            StatCard(label: context.tr('audit_shorts_long_ratio'), value: audit['weeklyShortToLongRatio'] != null ? '${audit['weeklyShortToLongRatio']}' : '—'),
            StatCard(label: context.tr('audit_subscribers'), value: '${audit['subscriberCount'] ?? '—'}'),
            StatCard(label: context.tr('audit_uploads_7d'), value: '${audit['recentUploadsLast7Days'] ?? 0}'),
          ],
        ),
        const SizedBox(height: 24),
        Text(context.tr('audit_recommendations'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),

        // Locked state: NO recommendations rendered at all (no messages,
        // no blur preview) — just one upgrade banner, per Boss's
        // "suggestion mat do" instruction. Score/stats above stay full.
        if (!unlocked)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.diamond.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.lock_rounded, color: AppColors.diamond, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(context.tr('audit_channel_seo_locked_notice'), style: const TextStyle(fontSize: 13, height: 1.4))),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: _goToUpgrade, child: Text(context.tr('audit_channel_seo_upgrade_btn'))),
                ),
              ],
            ),
          )
        else
          ...recommendations.map((r) => _recommendationCard(r)),
      ],
    );
  }

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

  // Only ever rendered when unlocked == true (see _buildAudit), so
  // Copy/Gemini here are real, immediate actions — no redirect-to-upgrade
  // needed inside a card that's already gated at the section level.
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

          if (prompt != null && prompt.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(10)),
              child: Text(prompt, style: TextStyle(fontSize: 12, color: context.surfaces.textDim, height: 1.4)),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyPrompt(prompt),
                  icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.diamond),
                  label: Text(context.tr('audit_copy_prompt_btn')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyPrompt(prompt),
                  icon: Image.asset('assets/gemini_icon.png', width: 16, height: 16, errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome_rounded, size: 15)),
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

  void _copyPrompt(String prompt) {
    Clipboard.setData(ClipboardData(text: prompt));
    showToast(context, context.tr('atd_copied_toast'), isSuccess: true);
  }
}
