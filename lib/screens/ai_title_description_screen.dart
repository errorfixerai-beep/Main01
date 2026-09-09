import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/apply_to_video_sheet.dart';

/// AI Title Generator + AI Description Generator, combined into one screen
/// with a mode toggle rather than two near-identical screens — same
/// "Generate & Select" flow for both: enter a topic, generate 4-5 options,
/// copy or select one, then Apply to Video.
class AiTitleDescriptionScreen extends StatefulWidget {
  /// When true, opens straight into Description mode (used by the
  /// Dashboard's "Description Ideas" quick action) instead of the
  /// default Title mode.
  final bool startInDescriptionMode;
  const AiTitleDescriptionScreen({super.key, this.startInDescriptionMode = false});
  @override
  State<AiTitleDescriptionScreen> createState() => _AiTitleDescriptionScreenState();
}

enum _Mode { title, description }

class _AiTitleDescriptionScreenState extends State<AiTitleDescriptionScreen> {
  late _Mode _mode = widget.startInDescriptionMode ? _Mode.description : _Mode.title;
  final _topicCtrl = TextEditingController();
  bool _loading = false;
  List<String> _options = [];
  int? _selectedIndex;

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) {
      showToast(context, context.tr('atd_topic_empty_error'), isError: true);
      return;
    }
    setState(() {
      _loading = true;
      _selectedIndex = null;
    });
    try {
      final res = _mode == _Mode.title
          ? await ApiService.instance.aiTitleOptions(topic)
          : await ApiService.instance.aiDescriptionOptions(topic);
      final list = (_mode == _Mode.title ? res['titles'] : res['descriptions']) as List? ?? [];
      setState(() => _options = list.cast<String>());
      if (_options.isEmpty && mounted) {
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

  Future<void> _applyToVideo() async {
    if (_selectedIndex == null) {
      showToast(context, context.tr('atd_select_option_error'), isError: true);
      return;
    }
    final chosen = _options[_selectedIndex!];
    await showApplyToVideoSheet(
      context,
      title: _mode == _Mode.title ? chosen : null,
      description: _mode == _Mode.description ? chosen : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('atd_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Mode toggle — same visual pattern as the Live/Schedule tab in
          // upload_screen.dart, for consistency across the app.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(999)),
            child: Row(children: [
              Expanded(child: _modeTab(context.tr('atd_mode_title'), _Mode.title)),
              Expanded(child: _modeTab(context.tr('atd_mode_description'), _Mode.description)),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _topicCtrl,
            decoration: InputDecoration(hintText: _mode == _Mode.title ? context.tr('atd_topic_hint_title') : context.tr('atd_topic_hint_description')),
            onSubmitted: (_) => _generate(),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: _mode == _Mode.title ? context.tr('atd_generate_titles_btn') : context.tr('atd_generate_descriptions_btn'),
            icon: Icons.auto_awesome_rounded,
            loading: _loading,
            onPressed: _generate,
          ),
          const SizedBox(height: 24),
          if (!_loading && _options.isEmpty)
            EmptyView(
              message: _mode == _Mode.title ? context.tr('atd_empty_title') : context.tr('atd_empty_description'),
              icon: Icons.title_rounded,
            ),
          ..._options.asMap().entries.map((entry) {
            final i = entry.key;
            final text = entry.value;
            final selected = _selectedIndex == i;
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
                    onPressed: () => setState(() => _selectedIndex = i),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedIndex = i),
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
          }),
          if (_options.isNotEmpty) ...[
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

  Widget _modeTab(String label, _Mode mode) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _mode = mode;
        _options = [];
        _selectedIndex = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selected ? Colors.white : context.surfaces.textDim)),
      ),
    );
  }
}