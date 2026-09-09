import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/brand_icons.dart';

class UpcomingScreen extends StatefulWidget {
  final bool embedded;
  const UpcomingScreen({super.key, this.embedded = false});
  @override
  State<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends State<UpcomingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Video.status (top-level) is derived server-side from platforms[] via
  // recomputeStatus() — see models/Video.js. Tabs filter on that field.
  // ⚠️ Keys here are stable internal identifiers (English, lowercase) —
  // NOT display text. The translated Tab label is looked up separately via
  // _tabLabel(context, key) in build(), so switching app language never
  // breaks the status-filtering logic that keys off these Map keys.
  final Map<String, List<String>> statusMap = const {
    'upcoming': ['queued'],
    'completed': ['uploaded', 'partially_uploaded'],
    'drafts': ['draft'],
    'failed': ['failed'],
  };

  final Map<String, List<dynamic>> videosByTab = {};
  final Map<String, bool> loadingByTab = {};

  String _tabLabel(BuildContext c, String key) {
    switch (key) {
      case 'upcoming':
        return c.tr('uc_tab_upcoming');
      case 'completed':
        return c.tr('uc_tab_completed');
      case 'drafts':
        return c.tr('uc_tab_drafts');
      case 'failed':
        return c.tr('uc_tab_failed');
      default:
        return key;
    }
  }

  String _platformLabel(BuildContext c, String platform) {
    switch (platform) {
      case 'youtube':
        return c.tr('up_youtube_label');
      case 'instagram':
        return c.tr('instagram_label');
      case 'facebook':
        return c.tr('uc_platform_facebook');
      default:
        return platform;
    }
  }

  // Search + platform filter — new, on top of the existing tabs, so a long
  // Upcoming/Completed list is actually usable once there are 50-100 videos
  // in it from bulk uploads.
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _platformFilter; // null = all platforms

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: statusMap.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _load(statusMap.keys.elementAt(_tabController.index));
      }
    });
    _load(statusMap.keys.first);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String tabKey) async {
    setState(() => loadingByTab[tabKey] = true);
    try {
      final statuses = statusMap[tabKey]!;
      final results = await Future.wait(statuses.map((s) => ApiService.instance.listVideos(status: s)));
      final all = results.expand((r) => (r['videos'] as List)).toList();
      all.sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));
      if (!mounted) return;
      setState(() => videosByTab[tabKey] = all);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => loadingByTab[tabKey] = false);
    }
  }

  Future<void> _cancel(String id, String tabKey) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('uc_cancel_dialog_title')),
        content: Text(context.tr('uc_cancel_dialog_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('uc_no_btn'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('uc_yes_cancel_btn'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.instance.cancelVideo(id);
      if (mounted) showToast(context, context.tr('uc_cancelled_toast'), isSuccess: true);
      _load(tabKey);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  (Color, String) _platformStatusBadge(BuildContext c, String status) {
    switch (status) {
      case 'pending': return (AppColors.diamond, c.tr('uc_status_scheduled'));
      case 'queued': return (AppColors.diamond, c.tr('uc_status_queued'));
      case 'processing': return (AppColors.diamond, c.tr('uc_status_uploading'));
      case 'uploaded': return (AppColors.green, c.tr('uc_status_live'));
      case 'failed': return (AppColors.red, c.tr('uc_status_failed'));
      default: return (AppColors.diamond, status);
    }
  }

  Widget _platformIcon(String platform, {double size = 13}) {
    switch (platform) {
      case 'youtube': return YoutubeIcon(size: size);
      case 'facebook': return FacebookIcon(size: size);
      default: return Icon(Icons.public_rounded, size: size);
    }
  }

  // A quick display title for the card header — prefers the YouTube title if
  // present, otherwise falls back to an Instagram/Facebook caption snippet,
  // otherwise a generic label.
  String _videoDisplayTitle(BuildContext c, dynamic v) {
    final platforms = (v['platforms'] as List?) ?? [];
    final yt = platforms.firstWhere((p) => p['platform'] == 'youtube', orElse: () => null);
    if (yt != null && (yt['title'] ?? '').toString().isNotEmpty) return yt['title'];
    final withCaption = platforms.firstWhere(
      (p) => (p['caption'] ?? '').toString().isNotEmpty,
      orElse: () => null,
    );
    if (withCaption != null) {
      final caption = withCaption['caption'].toString();
      return caption.length > 60 ? '${caption.substring(0, 60)}...' : caption;
    }
    return c.tr('uc_untitled_upload');
  }

  List<dynamic> _filtered(List<dynamic> videos) {
    return videos.where((v) {
      if (_searchQuery.isNotEmpty && !_videoDisplayTitle(context, v).toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_platformFilter != null) {
        final platforms = (v['platforms'] as List?) ?? [];
        if (!platforms.any((p) => p['platform'] == _platformFilter)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('uc_title')),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 12.5),
          labelColor: AppColors.purple,
          indicatorColor: AppColors.purple,
          tabs: statusMap.keys.map((k) => Tab(text: _tabLabel(context, k))).toList(),
        ),
      ),
      body: Column(
        children: [
          // ---------------- Search + platform filter bar ----------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: context.tr('uc_search_hint'),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _searchQuery = '';
                            }),
                          )
                        : null,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                // ⚠️ HIDDEN (Boss request — "Facebook/Instagram verification
                // pending, YouTube verification complete, sirf YouTube
                // launch kar rahe hain"): the "Facebook" filter chip is
                // removed from this row — the "All" chip already covers
                // every platform, so no functionality is actually lost.
                // _platformLabel()/_platformFilter/_filtered() logic is
                // fully untouched — to restore, just add this chip back:
                //   const SizedBox(width: 8),
                //   _filterChip(label: _platformLabel(context, 'facebook'), icon: const FacebookIcon(size: 14), selected: _platformFilter == 'facebook', onTap: () => setState(() => _platformFilter = 'facebook')),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _filterChip(label: context.tr('uc_filter_all'), selected: _platformFilter == null, onTap: () => setState(() => _platformFilter = null)),
                      const SizedBox(width: 8),
                      _filterChip(label: _platformLabel(context, 'youtube'), icon: const YoutubeIcon(size: 14), selected: _platformFilter == 'youtube', onTap: () => setState(() => _platformFilter = 'youtube')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: statusMap.keys.map((tabKey) {
                final loading = loadingByTab[tabKey] ?? true;
                final videos = _filtered(videosByTab[tabKey] ?? []);
                final isUpcoming = tabKey == 'upcoming';

                if (loading && videos.isEmpty) return const LoadingView();

                return RefreshIndicator(
                  onRefresh: () => _load(tabKey),
                  child: videos.isEmpty
                      ? ListView(children: [EmptyView(message: context.tr('uc_no_videos_in_tab'), icon: Icons.video_library_outlined)])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: videos.length,
                          itemBuilder: (_, i) {
                            final v = videos[i];
                            final platforms = (v['platforms'] as List?) ?? [];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 54, height: 54,
                                        decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(10)),
                                        child: const Center(child: Icon(Icons.movie_outlined, size: 22)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(_videoDisplayTitle(context, v), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                            const SizedBox(height: 4),
                                            Text(formatDate(v['createdAt']), style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                                            const SizedBox(height: 6),
                                            AppBadge(
                                              label: (v['diamondsCharged'] ?? 0) > 0
                                                  ? context.tr('uc_diamond_charged_badge').replaceFirst('%d', '${v['diamondsCharged']}')
                                                  : context.tr('uc_free_upload_badge'),
                                              color: (v['diamondsCharged'] ?? 0) > 0 ? AppColors.diamond : AppColors.green,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isUpcoming)
                                        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _cancel(v['_id'], tabKey)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  // Per-platform status row — this is the key new
                                  // piece: one video can be "Live" on YouTube while
                                  // still "Queued" on Facebook, etc.
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: platforms.map<Widget>((p) {
                                      final platform = p['platform'] as String;
                                      final (color, label) = _platformStatusBadge(context, p['status'] ?? '');
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(999)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          _platformIcon(platform),
                                          const SizedBox(width: 5),
                                          Text(_platformLabel(context, platform), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                          const SizedBox(width: 5),
                                          AppBadge(label: label, color: color),
                                        ]),
                                      );
                                    }).toList(),
                                  ),
                                  // Show fail reasons for any failed platform target.
                                  ...platforms
                                      .where((p) => p['status'] == 'failed' && (p['failReason'] ?? '').toString().isNotEmpty)
                                      .map((p) => Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.red),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    '${_platformLabel(context, p['platform'])}: ${p['failReason']}',
                                                    style: TextStyle(color: context.surfaces.textDim, fontSize: 12),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )),
                                ],
                              ),
                            );
                          },
                        ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({required String label, Widget? icon, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple.withValues(alpha: 0.14) : context.surfaces.card2,
          border: Border.all(color: selected ? AppColors.purple : context.surfaces.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[icon, const SizedBox(width: 6)],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? AppColors.purple : null)),
        ]),
      ),
    );
  }
}
