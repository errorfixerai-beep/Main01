import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/custom_dropdown.dart';
import '../widgets/apply_to_video_sheet.dart';

/// Screen 2/7 — POST /api/ai/seo-score.
class SeoOptimizerScreen extends StatefulWidget {
  const SeoOptimizerScreen({super.key});
  @override
  State<SeoOptimizerScreen> createState() => _SeoOptimizerScreenState();
}

class _SeoOptimizerScreenState extends State<SeoOptimizerScreen> {
  // ⚠️ [ANIK REQUEST - YouTube-only launch]: Instagram/Facebook options
  // hidden from the platform dropdown — Meta business verification pending.
  // CustomDropdown builds its items from _platforms.keys, so removing
  // entries here is enough; _platform state and the SEO score API call
  // (platform: _platform) are untouched. Uncomment to restore.
  static const _platforms = {
    'youtube': 'platform_youtube_label',
    // 'instagram': 'platform_instagram_label',
    // 'facebook': 'platform_facebook_label',
  };

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  String _platform = 'youtube';
  bool _loading = false;

  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    if (_titleCtrl.text.trim().isEmpty) {
      showToast(context, context.tr('seo_enter_title_error'), isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final tags = _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      final res = await ApiService.instance.aiSeoScore(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        tags: tags,
        platform: _platform,
      );
      setState(() => _result = res);
    } catch (e) {
      if (mounted) showAiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _bandColor(int score) {
    if (score > 70) return AppColors.green;
    if (score >= 50) return const Color(0xFFF5A623);
    return AppColors.red;
  }

  String _bandLabel(int score) {
    if (score > 70) return context.tr('seo_band_strong');
    if (score >= 50) return context.tr('seo_band_needs_work');
    return context.tr('seo_band_weak');
  }

  Widget _scoreGauge(int score) {
    final color = _bandColor(score);
    return Center(
      child: SizedBox(
        width: 160,
        height: 160,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: CircularProgressIndicator(
                value: score / 100,
                strokeWidth: 12,
                backgroundColor: context.surfaces.border,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$score', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: color)),
                Text(_bandLabel(score), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _breakdownBadge(String label, int value) {
    final color = _bandColor(value);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Column(children: [
          Text('$value', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: context.surfaces.textDim, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = _result?['breakdown'] as Map<String, dynamic>?;
    final recommendedTags = (_result?['recommendedTags'] as List? ?? []).cast<String>();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('seo_optimizer_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(context.tr('seo_platform_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          CustomDropdown<String>(
            value: _platform,
            items: _platforms.keys.toList(),
            labelBuilder: (v) => context.tr(_platforms[v] ?? v),
            onChanged: (v) => setState(() => _platform = v ?? _platform),
            prefixIcon: const Icon(Icons.hub_rounded, size: 18, color: AppColors.purple),
          ),
          const SizedBox(height: 16),
          Text(context.tr('seo_title_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextFormField(controller: _titleCtrl, decoration: InputDecoration(hintText: context.tr('seo_title_hint'))),
          const SizedBox(height: 16),
          Text(context.tr('seo_description_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextFormField(controller: _descCtrl, maxLines: 4, decoration: InputDecoration(hintText: context.tr('seo_description_hint'))),
          const SizedBox(height: 16),
          Text(context.tr('seo_tags_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextFormField(controller: _tagsCtrl, decoration: InputDecoration(hintText: context.tr('seo_tags_hint'))),
          const SizedBox(height: 22),
          GradientButton(label: context.tr('seo_analyze_btn'), icon: Icons.query_stats_rounded, loading: _loading, onPressed: _analyze),

          if (_result != null) ...[
            const SizedBox(height: 28),
            _scoreGauge((_result!['seoScore'] as num?)?.toInt() ?? 0),
            const SizedBox(height: 20),
            if (breakdown != null)
              Row(children: [
                _breakdownBadge('Title Length', (breakdown['titleScore'] as num?)?.toInt() ?? 0),
                _breakdownBadge('Keyword Density', (breakdown['descScore'] as num?)?.toInt() ?? 0),
                _breakdownBadge('Tag Relevance', (breakdown['tagScore'] as num?)?.toInt() ?? 0),
              ]),
            if ((_result!['notes'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(12)),
                child: Text(_result!['notes'], style: TextStyle(fontSize: 13, color: context.surfaces.textDim)),
              ),
            ],
            if (recommendedTags.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(children: [
                Text(context.tr('seo_recommended_tags'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: recommendedTags.join(', ')));
                    showToast(context, context.tr('seo_tags_copied_toast'), isSuccess: true);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: Text(context.tr('seo_copy_all_btn')),
                ),
              ]),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recommendedTags.map((t) => Chip(label: Text(t), backgroundColor: AppColors.purple.withValues(alpha: 0.12))).toList(),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {
                  final existing = _tagsCtrl.text.trim();
                  final merged = {...existing.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty), ...recommendedTags}.join(', ');
                  setState(() => _tagsCtrl.text = merged);
                  showToast(context, context.tr('seo_tags_appended_toast'), isSuccess: true);
                },
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(context.tr('seo_append_to_post_btn')),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => showApplyToVideoSheet(
                  context,
                  title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
                  description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(context.tr('apply_to_video_btn_label')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}