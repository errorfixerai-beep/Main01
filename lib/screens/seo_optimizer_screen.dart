import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/custom_dropdown.dart';
import '../widgets/apply_to_video_sheet.dart';
import 'diamond_store_screen.dart';

/// ⚠️ RENAMED (Boss request): "SEO Optimizer" → "Video SEO Optimizer" —
/// this screen optimizes ONE selected video's title/description/tags.
///
/// ⚠️ NEW: video-select dropdown at the top (from My Videos / library) —
/// picking a video auto-fills Title/Description/Tags instead of forcing
/// the user to retype them.
///
/// ⚠️ NEW: unlock check — seoScoreLevel != 'none' (ANY purchased pack,
/// including ₹10) unlocks the FULL problems list + real video score + tags.
/// A user with no pack at all sees only 1-2 free issue lines, rest blurred.
/// This is a LOOSER threshold than Channel SEO Score (channel_audit_screen)
/// which requires 'advance' (₹100+) specifically.
class SeoOptimizerScreen extends StatefulWidget {
  const SeoOptimizerScreen({super.key});
  @override
  State<SeoOptimizerScreen> createState() => _SeoOptimizerScreenState();
}

class _SeoOptimizerScreenState extends State<SeoOptimizerScreen> {
  static const _platforms = {
    'youtube': 'platform_youtube_label',
  };

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  String _platform = 'youtube';
  bool _loading = false;
  bool _loadingVideos = true;
  bool _unlocked = false; // seoScoreLevel != 'none'

  List<Map<String, dynamic>> _videos = [];
  String? _selectedVideoLabel;

  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _loadVideosAndPlan();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVideosAndPlan() async {
    setState(() => _loadingVideos = true);
    try {
      final results = await Future.wait([
        ApiService.instance.getVideoLibrary(),
        ApiService.instance.dashboard(),
      ]);
      final dash = results[1]['data'];
      // ASSUMPTION: dashboard response carries `seoScoreLevel`
      // ('none'/'basic'/'advance') on the user object — backend's
      // GET /api/dashboard route needs to expose this field for the
      // unlock check to work correctly.
      final level = dash?['seoScoreLevel'] as String?;
      setState(() {
        _videos = ((results[0]['videos'] as List?) ?? []).cast<Map<String, dynamic>>();
        _unlocked = level != null && level != 'none';
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loadingVideos = false);
    }
  }

  void _goToUpgrade() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen())).then((_) => _loadVideosAndPlan());
  }

  Future<void> _pickVideo() async {
    if (_videos.isEmpty) {
      showToast(context, context.tr('vso_no_videos'), isError: true);
      return;
    }
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: sheetContext.surfaces.border, borderRadius: BorderRadius.circular(999))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(context.tr('vso_select_video_label'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _videos.length,
                  itemBuilder: (_, i) {
                    final v = _videos[i];
                    final title = (v['title'] ?? '').toString().isNotEmpty ? v['title'].toString() : context.tr('apply_to_video_untitled');
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 32,
                          child: (v['thumbnail'] ?? '').toString().isNotEmpty
                              ? Image.network(v['thumbnail'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2))
                              : Container(color: context.surfaces.card2),
                        ),
                      ),
                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () => Navigator.of(sheetContext).pop(v),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedVideoLabel = (picked['title'] ?? '').toString();
        _titleCtrl.text = (picked['title'] ?? '').toString();
        _descCtrl.text = (picked['description'] ?? '').toString();
        final tags = (picked['tags'] as List? ?? []).cast<String>();
        _tagsCtrl.text = tags.join(', ');
        _result = null;
      });
    }
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

  /// Real "what's wrong with this video" list, from backend `issues`
  /// array (utils/groq.js analyzeSeoScore). Unlocked users see everything;
  /// locked users (no pack at all) see the first 1-2 items only, rest
  /// blurred with an upgrade CTA.
  Widget _issuesSection(List<String> issues) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final visibleCount = _unlocked ? issues.length : (issues.length < 2 ? issues.length : 2);
    final hiddenCount = issues.length - visibleCount;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('vso_issues_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 10),
          ...issues.take(visibleCount).map((issue) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFF5A623)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(issue, style: const TextStyle(fontSize: 13, height: 1.4))),
                ]),
              )),
          if (hiddenCount > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Opacity(
                    opacity: 0.35,
                    child: Column(
                      children: List.generate(hiddenCount, (i) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            height: 14,
                            width: double.infinity,
                            color: context.surfaces.card2,
                          )),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: _goToUpgrade,
                        icon: const Icon(Icons.lock_rounded, size: 14, color: AppColors.diamond),
                        label: Text(context.tr('vso_unlock_more_btn').replaceAll('%d', '$hiddenCount')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = _result?['breakdown'] as Map<String, dynamic>?;
    final recommendedTags = _unlocked ? (_result?['recommendedTags'] as List? ?? []).cast<String>() : <String>[];
    final issues = (_result?['issues'] as List? ?? []).cast<String>();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('video_seo_optimizer_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!_loadingVideos && _videos.isNotEmpty) ...[
            Text(context.tr('vso_select_video_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            PickerField(
              value: _selectedVideoLabel ?? context.tr('vso_choose_video_hint'),
              onTap: _pickVideo,
              prefixIcon: const Icon(Icons.video_library_outlined, size: 18, color: AppColors.purple),
            ),
            const SizedBox(height: 16),
          ],
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
                _breakdownBadge('Title', (breakdown['titleScore'] as num?)?.toInt() ?? 0),
                _breakdownBadge('Description', (breakdown['descScore'] as num?)?.toInt() ?? 0),
                _breakdownBadge('Tags', (breakdown['tagScore'] as num?)?.toInt() ?? 0),
              ]),

            _issuesSection(issues),

            if (_unlocked && (_result!['notes'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(12)),
                child: Text(_result!['notes'], style: TextStyle(fontSize: 13, color: context.surfaces.textDim)),
              ),
            ],

            if (_unlocked && recommendedTags.isNotEmpty) ...[
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

            if (!_unlocked) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.diamond.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.diamond_rounded, color: AppColors.diamond, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(context.tr('vso_upgrade_notice'), style: const TextStyle(fontSize: 12.5, height: 1.4))),
                  TextButton(onPressed: _goToUpgrade, child: Text(context.tr('vso_upgrade_btn'))),
                ]),
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
