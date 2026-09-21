import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/apply_to_video_sheet.dart';

/// AI Title / Description / Hashtags generator — combined into one screen.
///
/// ⚠️ REDESIGNED (Boss request — "checkbox lagao, jo tick karo wahi
/// generate ho, aur hashtags bhi add karo"): the old Title/Description
/// TOGGLE (pick one mode at a time) is replaced with 3 independent
/// checkboxes — Title / Description / Hashtags — so the user generates
/// only what they actually need in one go, off a single niche/topic input.
class AiTitleDescriptionScreen extends StatefulWidget {
  /// When true, opens with Description pre-checked and Title unchecked
  /// (used by the Dashboard's "Description Ideas" quick action).
  final bool startInDescriptionMode;
  const AiTitleDescriptionScreen({super.key, this.startInDescriptionMode = false});
  @override
  State<AiTitleDescriptionScreen> createState() => _AiTitleDescriptionScreenState();
}

class _AiTitleDescriptionScreenState extends State<AiTitleDescriptionScreen> {
  final _topicCtrl = TextEditingController();
  bool _loading = false;

  late bool _wantTitle = !widget.startInDescriptionMode;
  late bool _wantDescription = true;
  bool _wantHashtags = false;

  List<String> _titleOptions = [];
  List<String> _descriptionOptions = [];
  List<String> _hashtags = [];
  int? _selectedTitleIndex;
  int? _selectedDescIndex;

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  bool get _anySelected => _wantTitle || _wantDescription || _wantHashtags;

  Future<void> _generate() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) {
      showToast(context, context.tr('atd_topic_empty_error'), isError: true);
      return;
    }
    if (!_anySelected) {
      showToast(context, context.tr('atd_select_at_least_one_error'), isError: true);
      return;
    }

    setState(() {
      _loading = true;
      _selectedTitleIndex = null;
      _selectedDescIndex = null;
    });

    try {
      final futures = <Future>[];
      if (_wantTitle) futures.add(ApiService.instance.aiTitleOptions(topic));
      if (_wantDescription) futures.add(ApiService.instance.aiDescriptionOptions(topic));
      if (_wantHashtags) futures.add(ApiService.instance.aiHashtags(topic, 'youtube'));

      final results = await Future.wait(futures);
      int i = 0;
      List<String> titles = [];
      List<String> descriptions = [];
      List<String> hashtags = [];

      if (_wantTitle) {
        titles = ((results[i]['titles'] as List?) ?? []).cast<String>();
        i++;
      }
      if (_wantDescription) {
        descriptions = ((results[i]['descriptions'] as List?) ?? []).cast<String>();
        i++;
      }
      if (_wantHashtags) {
        hashtags = ((results[i]['hashtags'] as List?) ?? []).cast<String>();
        i++;
      }

      setState(() {
        _titleOptions = _wantTitle ? titles : [];
        _descriptionOptions = _wantDescription ? descriptions : [];
        _hashtags = _wantHashtags ? hashtags : [];
      });

      final gotNothing = (!_wantTitle || _titleOptions.isEmpty) &&
          (!_wantDescription || _descriptionOptions.isEmpty) &&
          (!_wantHashtags || _hashtags.isEmpty);
      if (gotNothing && mounted) {
        showToast(context, context.tr('atd_no_options_error'), isError: true);
      }
    } catch (e) {
      if (mounted) showAiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, context.tr('atd_copied_toast'), isSuccess: true);
  }

  void _copyAllHashtags() {
    Clipboard.setData(ClipboardData(text: _hashtags.map((h) => '#$h').join(' ')));
    showToast(context, context.tr('atd_copied_toast'), isSuccess: true);
  }

  Future<void> _applyToVideo() async {
    final title = _selectedTitleIndex != null ? _titleOptions[_selectedTitleIndex!] : null;
    final desc = _selectedDescIndex != null ? _descriptionOptions[_selectedDescIndex!] : null;
    if (title == null && desc == null) {
      showToast(context, context.tr('atd_select_option_error'), isError: true);
      return;
    }
    await showApplyToVideoSheet(context, title: title, description: desc);
  }

  Widget _checkboxRow(String label, bool value, ValueChanged<bool?> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Checkbox(value: value, onChanged: onChanged, activeColor: AppColors.purple),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }

  Widget _optionsList(List<String> options, int? selectedIndex, ValueChanged<int> onSelect) {
    return Column(
      children: options.asMap().entries.map((entry) {
        final i = entry.key;
        final text = entry.value;
        final selected = selectedIndex == i;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? AppColors.purple : context.surfaces.border, width: selected ? 1.6 : 1),
            borderRadius: BorderRadius.circular(14),
            color: selected ? AppColors.purple.withValues(alpha: 0.06) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? AppColors.purple : context.surfaces.textDim,
                ),
                onPressed: () => onSelect(i),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.45)),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.copy_rounded, size: 18, color: context.surfaces.textDim),
                onPressed: () => _copy(text),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyResults = _titleOptions.isNotEmpty || _descriptionOptions.isNotEmpty || _hashtags.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('atd_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(context.tr('atd_topic_hint_title'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _topicCtrl,
            decoration: InputDecoration(hintText: context.tr('atd_niche_hint')),
            onSubmitted: (_) => _generate(),
          ),
          const SizedBox(height: 14),
          Text(context.tr('atd_what_to_generate'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                _checkboxRow(context.tr('atd_mode_title'), _wantTitle, (v) => setState(() => _wantTitle = v ?? false)),
                Divider(height: 1, color: context.surfaces.border),
                _checkboxRow(context.tr('atd_mode_description'), _wantDescription, (v) => setState(() => _wantDescription = v ?? false)),
                Divider(height: 1, color: context.surfaces.border),
                _checkboxRow(context.tr('atd_mode_hashtags'), _wantHashtags, (v) => setState(() => _wantHashtags = v ?? false)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: context.tr('atd_generate_btn'),
            icon: Icons.auto_awesome_rounded,
            loading: _loading,
            onPressed: _generate,
          ),
          const SizedBox(height: 24),

          if (!_loading && !hasAnyResults)
            EmptyView(message: context.tr('atd_empty_generic'), icon: Icons.title_rounded),

          if (_titleOptions.isNotEmpty) ...[
            Text(context.tr('atd_mode_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            _optionsList(_titleOptions, _selectedTitleIndex, (i) => setState(() => _selectedTitleIndex = i)),
            const SizedBox(height: 12),
          ],

          if (_descriptionOptions.isNotEmpty) ...[
            Text(context.tr('atd_mode_description'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            _optionsList(_descriptionOptions, _selectedDescIndex, (i) => setState(() => _selectedDescIndex = i)),
            const SizedBox(height: 12),
          ],

          if (_hashtags.isNotEmpty) ...[
            Row(children: [
              Text(context.tr('atd_mode_hashtags'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const Spacer(),
              TextButton.icon(
                onPressed: _copyAllHashtags,
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: Text(context.tr('seo_copy_all_btn')),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _hashtags.map((h) => Chip(label: Text('#$h'), backgroundColor: AppColors.purple.withValues(alpha: 0.12))).toList(),
            ),
            const SizedBox(height: 12),
          ],

          if (_titleOptions.isNotEmpty || _descriptionOptions.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _applyToVideo,
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
