import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import 'common.dart';

/// Shared "Apply to Video" flow used by the AI Title/Description generator
/// and the SEO Optimizer's "Apply to Video" button.
///
/// ⚠️ FIX (Boss correction): previously the "Scheduled in TubePilot"
/// section ALWAYS rendered its header + an empty placeholder whenever
/// there were no queued TubePilot videos — even when the "Published on
/// YouTube" section right below it had real videos to pick from. That
/// made it look like nothing was available at all, even though a real,
/// usable list was sitting right under it. Now: a section (header +
/// content) only renders at all when it actually has something to show.
Future<bool?> showApplyToVideoSheet(
  BuildContext context, {
  String? title,
  String? description,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => _ApplyToVideoSheet(title: title, description: description),
  );
}

// Which list the currently-selected video came from — decides which API
// call _confirmApply() makes.
enum _Source { queued, youtube }

class _ApplyToVideoSheet extends StatefulWidget {
  final String? title;
  final String? description;
  const _ApplyToVideoSheet({this.title, this.description});

  @override
  State<_ApplyToVideoSheet> createState() => _ApplyToVideoSheetState();
}

class _ApplyToVideoSheetState extends State<_ApplyToVideoSheet> {
  bool _loading = true;
  bool _applying = false;

  List<Map<String, dynamic>> _queuedVideos = [];
  List<Map<String, dynamic>> _youtubeVideos = [];
  // Set when the "Published on YouTube" fetch fails for a reason other
  // than "no channel connected" (e.g. token expired) — shown as a small
  // inline note rather than blocking the queued-videos section.
  String? _youtubeLoadError;

  _Source? _selectedSource;
  String? _selectedVideoId; // TubePilot video _id (queued flow)
  String? _selectedPlatform; // platform chip (queued flow only)
  String? _selectedYoutubeVideoId; // real YouTube videoId (youtube flow)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.instance.listVideos(status: 'queued'),
        ApiService.instance.getMyYoutubeVideos().catchError((e) {
          // No channel connected (404) is an expected, silent case — just
          // means section 2 stays empty. Any other failure (expired
          // token, network) is surfaced as a small note instead of
          // blocking the sheet entirely.
          _youtubeLoadError = e.toString().contains('404') ? null : e.toString().replaceFirst('ApiException: ', '');
          return <String, dynamic>{};
        }),
      ]);
      if (!mounted) return;
      setState(() {
        _queuedVideos = (results[0]['videos'] as List? ?? []).cast<Map<String, dynamic>>();
        _youtubeVideos = (results[1]['videos'] as List? ?? []).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectQueued(String videoId) {
    setState(() {
      _selectedSource = _Source.queued;
      _selectedVideoId = videoId;
      _selectedPlatform = null;
      _selectedYoutubeVideoId = null;
    });
  }

  void _selectYoutube(String videoId) {
    setState(() {
      _selectedSource = _Source.youtube;
      _selectedYoutubeVideoId = videoId;
      _selectedVideoId = null;
      _selectedPlatform = null;
    });
  }

  bool get _canConfirm {
    if (_selectedSource == _Source.queued) {
      return _selectedVideoId != null && _selectedPlatform != null;
    }
    if (_selectedSource == _Source.youtube) {
      return _selectedYoutubeVideoId != null;
    }
    return false;
  }

  Future<void> _confirmApply() async {
    if (!_canConfirm) return;
    setState(() => _applying = true);
    try {
      if (_selectedSource == _Source.queued) {
        await ApiService.instance.updateVideoMetadata(
          _selectedVideoId!,
          platform: _selectedPlatform!,
          title: widget.title,
          description: widget.description,
        );
      } else {
        await ApiService.instance.updateYoutubeVideoMetadata(
          _selectedYoutubeVideoId!,
          title: widget.title,
          description: widget.description,
        );
      }
      if (mounted) {
        showToast(context, context.tr('apply_to_video_success_toast'), isSuccess: true);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedQueuedVideo = _queuedVideos.firstWhere(
      (v) => v['_id'] == _selectedVideoId,
      orElse: () => <String, dynamic>{},
    );
    final platformTargets = (selectedQueuedVideo['platforms'] as List? ?? []).cast<Map<String, dynamic>>();

    // ⚠️ FIX: nothing at all to show anywhere — this is the ONLY case
    // where a combined empty state makes sense now.
    final nothingAtAll = !_loading && _queuedVideos.isEmpty && _youtubeVideos.isEmpty && _youtubeLoadError == null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Icon(Icons.send_rounded, color: AppColors.purple, size: 20),
              const SizedBox(width: 8),
              Text(context.tr('apply_to_video_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            const SizedBox(height: 4),
            Text(
              context.tr('apply_to_video_subtitle'),
              style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5),
            ),
            const SizedBox(height: 16),

            if (_loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: LoadingView())
            else if (nothingAtAll)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: EmptyView(message: context.tr('apply_to_video_empty'), icon: Icons.video_library_outlined),
              )
            else ...[
              // ---------------- Section 1: TubePilot queued videos ----------------
              // ⚠️ FIX: this ENTIRE section (header + empty placeholder)
              // is skipped when there are no queued videos — it no longer
              // shows a "not available" message sitting above a real,
              // usable YouTube video list.
              if (_queuedVideos.isNotEmpty) ...[
                Text(context.tr('apply_to_video_section_queued'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ..._queuedVideos.map((v) {
                  final selected = _selectedSource == _Source.queued && v['_id'] == _selectedVideoId;
                  return GestureDetector(
                    onTap: () => _selectQueued(v['_id']),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: selected ? AppColors.purple : context.surfaces.border, width: selected ? 1.6 : 1),
                        borderRadius: BorderRadius.circular(12),
                        color: selected ? AppColors.purple.withValues(alpha: 0.08) : null,
                      ),
                      child: Row(children: [
                        Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            size: 18, color: selected ? AppColors.purple : context.surfaces.textDim),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _queuedVideoLabel(v),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                        ),
                      ]),
                    ),
                  );
                }),

                if (_selectedSource == _Source.queued && platformTargets.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(context.tr('apply_to_video_platform_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: platformTargets.map((p) {
                      final platform = p['platform'] as String;
                      final selected = platform == _selectedPlatform;
                      return ChoiceChip(
                        label: Text(platform[0].toUpperCase() + platform.substring(1)),
                        selected: selected,
                        selectedColor: AppColors.purple,
                        labelStyle: TextStyle(color: selected ? Colors.white : null, fontWeight: FontWeight.w700, fontSize: 12.5),
                        onSelected: (_) => setState(() => _selectedPlatform = platform),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 20),
              ],

              // ---------------- Section 2: real YouTube channel videos ----------------
              if (_youtubeVideos.isNotEmpty || _youtubeLoadError != null) ...[
                Text(context.tr('apply_to_video_section_youtube'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_youtubeLoadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_youtubeLoadError!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
                  )
                else
                  ..._youtubeVideos.map((v) {
                    final selected = _selectedSource == _Source.youtube && v['videoId'] == _selectedYoutubeVideoId;
                    final thumb = (v['thumbnail'] ?? '').toString();
                    return GestureDetector(
                      onTap: () => _selectYoutube(v['videoId']),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: selected ? AppColors.purple : context.surfaces.border, width: selected ? 1.6 : 1),
                          borderRadius: BorderRadius.circular(12),
                          color: selected ? AppColors.purple.withValues(alpha: 0.08) : null,
                        ),
                        child: Row(children: [
                          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                              size: 18, color: selected ? AppColors.purple : context.surfaces.textDim),
                          const SizedBox(width: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: thumb.isNotEmpty
                                ? Image.network(thumb, width: 42, height: 42, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(width: 42, height: 42, color: context.surfaces.card2))
                                : Container(width: 42, height: 42, color: context.surfaces.card2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (v['title'] ?? '').toString().isNotEmpty ? v['title'] : context.tr('apply_to_video_untitled'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                            ),
                          ),
                        ]),
                      ),
                    );
                  }),
                const SizedBox(height: 20),
              ],

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (!_canConfirm || _applying) ? null : _confirmApply,
                  child: _applying
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(context.tr('apply_to_video_confirm_btn')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _queuedVideoLabel(Map<String, dynamic> v) {
    final platforms = (v['platforms'] as List? ?? []).cast<Map<String, dynamic>>();
    final firstTitle = platforms.map((p) => p['title']).firstWhere((t) => (t ?? '').toString().isNotEmpty, orElse: () => null);
    return firstTitle ?? context.tr('apply_to_video_untitled');
  }
}