import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';

/// Screen 4/7.
///
/// NOTE on the heatmap: there is no per-channel "audience peak activity"
/// endpoint in the backend (that requires YouTube Analytics API's
/// audience-retention/traffic-source data, which isn't wired up yet). The
/// grid below shows general platform best-practice posting windows
/// (labelled as such in the UI) rather than fabricating personalized
/// numbers for this specific creator's audience.
///
/// The Auto-Slotting switch reflects rules that are ALREADY enforced
/// server-side (1-hour minimum buffer in routes/video.js, daily
/// Free=1/Premium=2 caps) — toggling it here doesn't loosen or tighten
/// those, since the backend enforces them unconditionally regardless of
/// any client-side preference. It's shown as an informational toggle over
/// an always-on backend guarantee, not a real feature flag, and is labelled
/// that way rather than implying it does something it can't.
class SmartSchedulerScreen extends StatefulWidget {
  const SmartSchedulerScreen({super.key});
  @override
  State<SmartSchedulerScreen> createState() => _SmartSchedulerScreenState();
}

class _SmartSchedulerScreenState extends State<SmartSchedulerScreen> {
  // General best-practice engagement windows per weekday (0=low .. 3=peak),
  // sourced from common platform posting-time guidance, NOT this specific
  // channel's real analytics.
  static const _heat = [
    [0, 1, 1, 2, 2, 1, 0, 0], // Mon
    [0, 1, 2, 2, 2, 2, 1, 0], // Tue
    [0, 1, 2, 3, 2, 2, 1, 0], // Wed
    [0, 1, 2, 2, 3, 2, 1, 0], // Thu
    [0, 1, 2, 2, 2, 3, 2, 1], // Fri
    [0, 0, 1, 2, 3, 3, 2, 1], // Sat
    [0, 0, 1, 2, 2, 2, 1, 0], // Sun
  ];
  static const _hourLabels = ['6a', '9a', '12p', '3p', '6p', '9p', '12a', '3a'];

  bool _autoSlotting = true;
  bool _loading = true;
  List<Map<String, dynamic>> _queued = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Localized day abbreviations — pulled at build/use time via context.tr()
  // instead of a static const list, since the label needs to change live
  // when the user switches language.
  List<String> _days(BuildContext context) => [
        context.tr('day_mon'),
        context.tr('day_tue'),
        context.tr('day_wed'),
        context.tr('day_thu'),
        context.tr('day_fri'),
        context.tr('day_sat'),
        context.tr('day_sun'),
      ];

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.instance.listVideos(status: 'queued');
      setState(() => _queued = (res['videos'] as List? ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ⚠️ CONTRAST FIX: solid AppColors.purple (a dark plum) barely stood out
  // against the also-dark card background — swapped the top of the scale
  // to purpleLight (a brighter plum tint) so "peak" cells are clearly
  // visible, and raised the floor opacity so even "no activity" cells read
  // as part of the grid rather than nearly invisible against the card.
  Color _heatColor(int level) {
    switch (level) {
      case 3:
        return AppColors.purpleLight;
      case 2:
        return AppColors.purpleLight.withValues(alpha: 0.6);
      case 1:
        return AppColors.purpleLight.withValues(alpha: 0.32);
      default:
        return AppColors.purpleLight.withValues(alpha: 0.14);
    }
  }

  String? _earliestScheduledAt(Map<String, dynamic> video) {
    final platforms = video['platforms'] as List? ?? [];
    final dates = platforms
        .map((p) => p is Map ? p['scheduledAt'] : null)
        .whereType<String>()
        .map((s) => DateTime.tryParse(s))
        .whereType<DateTime>()
        .toList();
    if (dates.isEmpty) return null;
    dates.sort();
    final d = dates.first;
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final days = _days(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('smart_scheduler_title'))),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.purple,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(context.tr('audience_peak_activity'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(context.tr('audience_peak_subtitle'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Row(children: [
                    const SizedBox(width: 32),
                    ..._hourLabels.map((h) => Expanded(child: Text(h, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: context.surfaces.textDim)))),
                  ]),
                  const SizedBox(height: 6),
                  ...List.generate(7, (row) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            days[row],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                        ...List.generate(8, (col) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(1.5),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(color: _heatColor(_heat[row][col]), borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                            ),
                          );
                        }),
                      ]),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
              child: SwitchListTile(
                value: _autoSlotting,
                onChanged: (v) => setState(() => _autoSlotting = v),
                activeTrackColor: AppColors.purple,
                title: Text(context.tr('auto_slotting_title'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text(
                  context.tr('auto_slotting_subtitle'),
                  style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(context.tr('preview_queue'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: LoadingView())
            else if (_queued.isEmpty)
              EmptyView(message: context.tr('queue_empty'), icon: Icons.event_note_rounded)
            else
              ..._queued.map((v) {
                final when = _earliestScheduledAt(v);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.schedule_rounded, size: 18, color: AppColors.purple),
                    const SizedBox(width: 10),
                    Expanded(child: Text(v['title'] ?? context.tr('untitled_video'), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                    if (when != null) Text(when, style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                  ]),
                );
              }),
          ],
        ),
      ),
    );
  }
}