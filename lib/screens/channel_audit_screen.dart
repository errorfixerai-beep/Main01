import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import 'upload_screen.dart';

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
    final recommendations = (audit['recommendations'] as List? ?? []).cast<String>();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            Text(context.tr('audit_channel_health'), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('$score/100', style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            AppBadge(label: _healthLabel(score), color: _healthColor(score)),
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
        ...recommendations.map((r) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.tips_and_updates_rounded, color: AppColors.purple, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 13, height: 1.4))),
                  ]),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen())),
                      icon: const Icon(Icons.upload_rounded, size: 15),
                      label: Text(context.tr('audit_upload_now_btn')),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}