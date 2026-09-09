import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/custom_dropdown.dart';

/// Screen 1/7 of the Creator OS suite — POST /api/ai/ideas.
/// NOTE ("Send to Scheduler"): UploadScreen is file-based (it needs an
/// actual video/image picked before any text field is shown), so there's
/// no existing hook to deep-link a text-only idea straight into it without
/// a larger UploadScreen refactor. Until that refactor happens, "Send to
/// Scheduler" copies the idea's title + script to the clipboard so the
/// creator can paste it in while uploading — a real, working action
/// instead of a dead button.
///
/// ⚠️ FIX (Boss request — "dropdown sahi se nahin ho raha, ise sahi
/// karo"): Niche/Platform were a `DropdownButtonFormField` (CustomDropdown)
/// whose opened menu is a separate Overlay that Flutter positions relative
/// to the field itself — on some devices/list lengths that overlay can
/// render oddly (clipped/overlapping nearby text). Swapped both to the
/// app's own bottom-sheet picker pattern (PickerField + a modal list,
/// same family as pickers used elsewhere in the app) — a fixed, full-width
/// sheet has none of that overlay-positioning risk and matches the rest
/// of the app's picker UX.
class AiIdeasScreen extends StatefulWidget {
  const AiIdeasScreen({super.key});
  @override
  State<AiIdeasScreen> createState() => _AiIdeasScreenState();
}

class _AiIdeasScreenState extends State<AiIdeasScreen> {
  static const _nicheKeys = [
    'niche_tech', 'niche_gaming', 'niche_lifestyle', 'niche_business',
    'niche_fitness', 'niche_food', 'niche_travel', 'niche_comedy',
  ];
  // ⚠️ HIDDEN (Boss request — "Facebook/Instagram verification pending,
  // YouTube verification complete, sirf YouTube launch kar rahe hain"):
  // this map itself is UNCHANGED and still contains instagram/facebook
  // labels — nothing was deleted here. The picker below (_pickPlatform)
  // just restricts which KEYS are offered as options, so only "YouTube"
  // ever shows up in the sheet. To bring Instagram/Facebook back later,
  // change `_platformOptionsShown` below back to `_platforms.keys.toList()`.
  static const _platforms = {'youtube': 'platform_youtube_label', 'instagram': 'platform_instagram_label', 'facebook': 'platform_facebook_label'};
  static const _platformOptionsShown = ['youtube'];

  String _nicheKey = _nicheKeys.first;
  String _platform = 'youtube';
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _ideas = [];
  final Set<int> _expanded = {};

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final niche = context.tr(_nicheKey);
      final res = await ApiService.instance.aiIdeas(niche: niche, platform: _platform, count: 5);
      final ideas = (res['ideas'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _ideas = ideas;
        _expanded.clear();
      });
      if (ideas.isEmpty && mounted) {
        showToast(context, context.tr('ai_ideas_no_ideas_error'), isError: true);
      }
    } catch (e) {
      if (mounted) showAiError(context, e);
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _scoreColor(int score) {
    if (score >= 70) return AppColors.green;
    if (score >= 40) return const Color(0xFFF5A623);
    return AppColors.red;
  }

  Future<void> _pickNiche() async {
    final picked = await _showPickerSheet(
      title: context.tr('select_niche_title'),
      options: _nicheKeys,
      labelBuilder: (k) => context.tr(k),
      selected: _nicheKey,
    );
    if (picked != null) setState(() => _nicheKey = picked);
  }

  Future<void> _pickPlatform() async {
    final picked = await _showPickerSheet(
      title: context.tr('select_platform_title'),
      options: _platformOptionsShown,
      labelBuilder: (k) => context.tr(_platforms[k]!),
      selected: _platform,
    );
    if (picked != null) setState(() => _platform = picked);
  }

  Future<String?> _showPickerSheet({
    required String title,
    required List<String> options,
    required String Function(String) labelBuilder,
    required String selected,
  }) {
    return showModalBottomSheet<String>(
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
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final option = options[i];
                    final isSelected = option == selected;
                    return ListTile(
                      title: Text(labelBuilder(option), style: TextStyle(fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500)),
                      trailing: isSelected ? const Icon(Icons.check_rounded, color: AppColors.purple) : null,
                      onTap: () => Navigator.of(sheetContext).pop(option),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('ai_ideas_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(context.tr('ai_ideas_niche_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          PickerField(
            value: context.tr(_nicheKey),
            onTap: _pickNiche,
            prefixIcon: const Icon(Icons.category_rounded, size: 18, color: AppColors.purple),
          ),
          const SizedBox(height: 16),
          Text(context.tr('ai_ideas_platform_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          PickerField(
            value: context.tr(_platforms[_platform]!),
            onTap: _pickPlatform,
            prefixIcon: const Icon(Icons.hub_rounded, size: 18, color: AppColors.purple),
          ),
          const SizedBox(height: 22),
          GradientButton(label: context.tr('ai_ideas_generate_btn'), icon: Icons.auto_awesome_rounded, loading: _loading, onPressed: _generate),
          const SizedBox(height: 24),
          if (!_loading && _ideas.isEmpty && _error == null)
            EmptyView(message: context.tr('ai_ideas_empty_state'), icon: Icons.lightbulb_outline_rounded),
          ..._ideas.asMap().entries.map((entry) {
            final i = entry.key;
            final idea = entry.value;
            final score = (idea['viralScore'] as num?)?.toInt() ?? 0;
            final expanded = _expanded.contains(i);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(idea['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    ),
                    const SizedBox(width: 8),
                    AppBadge(label: context.tr(_platforms[_platform]!), color: AppColors.purple),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.local_fire_department_rounded, size: 16, color: _scoreColor(score)),
                    const SizedBox(width: 5),
                    Text(context.tr('ai_ideas_viral_score'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                    const Spacer(),
                    Text('$score/100', style: TextStyle(color: _scoreColor(score), fontWeight: FontWeight.w800, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      minHeight: 6,
                      backgroundColor: context.surfaces.border,
                      valueColor: AlwaysStoppedAnimation(_scoreColor(score)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('"${idea['hook'] ?? ''}"', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13.5)),
                  const SizedBox(height: 6),
                  Text(idea['description'] ?? '', style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                  if (expanded && (idea['script'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(12)),
                      child: Text(idea['script'], style: const TextStyle(fontSize: 13, height: 1.5)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    TextButton.icon(
                      onPressed: () => setState(() => expanded ? _expanded.remove(i) : _expanded.add(i)),
                      icon: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                      label: Text(expanded ? context.tr('ai_ideas_hide_script') : context.tr('ai_ideas_full_script')),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () {
                        final text = '${idea['title']}\n\n${idea['script'] ?? idea['description']}';
                        Clipboard.setData(ClipboardData(text: text));
                        showToast(context, context.tr('ai_ideas_copied_toast'), isSuccess: true);
                      },
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: Text(context.tr('ai_ideas_send_to_scheduler')),
                    ),
                  ]),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
