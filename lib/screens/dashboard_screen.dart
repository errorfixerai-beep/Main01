import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/brand_icons.dart';
import 'upload_screen.dart';
import 'upcoming_screen.dart';
import 'analytics_screen.dart';
import 'profile_screen.dart';
import 'wallet_screen.dart';
import 'notifications_screen.dart';
import 'rate_us_screen.dart';
import 'ai_ideas_screen.dart';
import 'ai_title_description_screen.dart';
import 'channel_audit_screen.dart';

// Key used in SharedPreferences to remember when the AI Idea popup
// (see showIdeaPopup below) was last shown, so it can be re-shown once
// every 24 hours instead of on every app open. Shared between this file
// and username_setup_screen.dart (which sets it right after the very
// first popup shown post-signup).
const String kIdeasPopupLastShownKey = 'ideas_popup_last_shown_ms';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const _DashboardHome(),
      const UploadScreen(embedded: true),
      const UpcomingScreen(embedded: true),
      const AnalyticsScreen(embedded: true),
      const ProfileScreen(embedded: true),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _tabIndex, children: screens),
      bottomNavigationBar: AppBottomNav(currentIndex: _tabIndex, onTap: (i) => setState(() => _tabIndex = i)),
    );
  }
}

class _DashboardHome extends StatefulWidget {
  const _DashboardHome();
  @override
  State<_DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<_DashboardHome> {
  Map<String, dynamic>? data;
  List<dynamic> notifications = [];
  int unreadCount = 0;

  Map<String, dynamic>? youtubeChannel;
  Map<String, dynamic>? facebookStatus;

  List<Map<String, dynamic>> upcomingEvents = [];
  List<Map<String, dynamic>> recentVideos = [];

  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load().then((_) async {
      if (!mounted) return;
      maybeShowRateUsPopup(context);
      // Small delay so the rate-us popup (if it shows) isn't immediately
      // stacked under the idea popup — the two are independent nudges,
      // this just keeps them from fighting over the same frame.
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) await _maybeShowIdeaPopup();
    });
  }

  // ⚠️ NEW (Boss request — "daily yani 24 hours baad naya ideas suggest
  // kare"): checks SharedPreferences for when the idea popup last showed;
  // if it's been 24+ hours (or never), fetches 3 fresh ideas — personalized
  // using the connected channel's category/niche when available — and
  // shows them via the shared showIdeaPopup() below, then stamps "now" as
  // the new last-shown time.
  //
  // ⚠️ Personalization now actually has real data to read: the backend's
  // OAuth callback (routes/youtube.js) detects the connected channel's
  // topic/category via YouTube's own topicDetails at connect time and
  // saves it as `category` on the channel record — GET /youtube/channel
  // (loaded in _load() below, into `youtubeChannel`) now returns it. Before
  // this backend change, `youtubeChannel?['category']` was always null and
  // every popup silently fell back to the generic 'Tech' niche inside
  // showIdeaPopup().
  Future<void> _maybeShowIdeaPopup() async {
    final prefs = await SharedPreferences.getInstance();
    final lastShown = prefs.getInt(kIdeasPopupLastShownKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastShown != null && now - lastShown < const Duration(hours: 24).inMilliseconds) {
      return;
    }
    if (!mounted) return;
    final niche = youtubeChannel?['category'] ?? youtubeChannel?['topicCategory'];
    await showIdeaPopup(context, channelNiche: niche is String && niche.isNotEmpty ? niche : null);
    await prefs.setInt(kIdeasPopupLastShownKey, now);
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.dashboard(),
        ApiService.instance.getNotifications(),
        ApiService.instance.getYoutubeChannel().catchError((_) => <String, dynamic>{}),
        ApiService.instance.getMetaStatus().catchError((_) => <String, dynamic>{}),
        ApiService.instance.listVideos(status: 'queued').catchError((_) => <String, dynamic>{}),
        // Real recently-published videos, used to render the "Recent
        // Activity" thumbnail list — same listVideos() call the queued
        // fetch below already uses, just filtered to 'uploaded' status.
        ApiService.instance.listVideos(status: 'uploaded').catchError((_) => <String, dynamic>{}),
      ]);

      final dash = results[0]['data'];
      final notifRes = results[1];
      final ytRes = results[2];
      final metaRes = results[3];
      final queuedRes = results[4];
      final uploadedRes = results[5];

      final events = _extractPlatformEvents(queuedRes, const {'pending', 'queued'});
      events.sort((a, b) {
        final aTime = a['scheduledAt'] as String?;
        final bTime = b['scheduledAt'] as String?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return -1;
        if (bTime == null) return 1;
        return aTime.compareTo(bTime);
      });

      final recent = _extractPlatformEvents(uploadedRes, const {'uploaded'});
      recent.sort((a, b) {
        final aTime = (a['publishedAt'] ?? a['scheduledAt']) as String?;
        final bTime = (b['publishedAt'] ?? b['scheduledAt']) as String?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime); // newest first
      });

      setState(() {
        data = dash;
        notifications = (notifRes['notifications'] as List?) ?? [];
        unreadCount = notifRes['unreadCount'] ?? 0;
        youtubeChannel = ytRes['success'] == true ? ytRes['channel'] : null;
        facebookStatus = metaRes['facebook'];
        upcomingEvents = events.take(5).toList();
        recentVideos = recent.take(4).toList();
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (showLoader && mounted) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> _extractPlatformEvents(Map<String, dynamic> res, Set<String> statuses) {
    final out = <Map<String, dynamic>>[];
    final videos = (res['videos'] as List?) ?? [];
    for (final v in videos) {
      final platforms = (v['platforms'] as List?) ?? [];
      for (final p in platforms) {
        if (!statuses.contains(p['status'])) continue;
        out.add({
          'videoId': v['_id'],
          'platform': p['platform'],
          'title': p['platform'] == 'youtube'
              ? (p['title'] ?? 'Untitled')
              : ((p['caption'] ?? '').toString().isNotEmpty ? p['caption'] : 'Untitled'),
          'scheduledAt': p['scheduledAt'],
          'publishedAt': p['publishedAt'],
          'thumbnailUrl': p['thumbnailUrl'] ?? '',
          'status': p['status'],
        });
      }
    }
    return out;
  }

  void _goToProfile() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())).then((_) => _load(showLoader: false));
  }

  void _openPreview(Map<String, dynamic> event) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UpcomingScreen())).then((_) => _load(showLoader: false));
  }

  // ⚠️ FIX (Boss request — avatar/greeting showed the wrong or a stale
  // email): this used to read email/name off the /dashboard endpoint's
  // response (`data?['email']`, etc), which isn't guaranteed to carry the
  // same fields the account actually has. Settings screen (settings_screen.dart)
  // already gets this right by reading straight from AuthProvider's cached
  // user object — so the dashboard avatar/greeting now reads from the SAME
  // source of truth instead of the dashboard payload, guaranteeing they can
  // never disagree with each other again.
  String? _userEmail(BuildContext context) {
    final user = context.watch<AuthProvider>().user ?? {};
    final email = user['email'];
    return (email is String && email.isNotEmpty) ? email : null;
  }

  // Real first-letter fallback for the profile avatar — used whenever
  // there's no connected YouTube channel photo to show instead.
  String _userInitial(BuildContext context) {
    final email = _userEmail(context);
    return (email != null) ? email.trim()[0].toUpperCase() : '?';
  }

  // Real first name for the "Hello, {name}" greeting — falls back to the
  // email's local-part, then to a generic greeting if neither is set.
  String _userFirstName(BuildContext context) {
    final user = context.watch<AuthProvider>().user ?? {};
    final name = user['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim().split(' ').first;
    final email = _userEmail(context);
    if (email != null && email.contains('@')) return email.split('@').first;
    return context.tr('there_fallback');
  }

  int get _diamondCostPerUpload {
    final cost = data?['diamondCostPerUpload'] ?? data?['uploadCostDiamonds'];
    if (cost is num && cost > 0) return cost.toInt();
    return 10;
  }

  ({String label, Color color}) _platformMeta(BuildContext context, String? platform) {
    switch (platform) {
      case 'youtube':
        return (label: context.tr('platform_youtube_label'), color: AppColors.red);
      case 'facebook':
        return (label: context.tr('platform_facebook_label'), color: AppColors.diamond);
      default:
        return (label: platform ?? '', color: AppColors.purple);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diamondBalance = (data?['diamondBalance'] ?? 0) as num;
    final worthUploads = diamondBalance ~/ _diamondCostPerUpload;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⚠️ FIX (Boss request — "logo bada karna hai"): bumped from
            // 26x26 to 36x36 so the real logo actually reads clearly next
            // to the wordmark instead of looking like a small favicon.
            Image.asset('assets/splash.png', width: 36, height: 36),
            const SizedBox(width: 8),
            // ⚠️ FIX (Boss request — "TubePilot ko Tube Pilot karo, Tube
            // black aur Pilot plum color mein"): split into two colored
            // spans instead of one plain Text widget.
            RichText(
              text: const TextSpan(
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFamily: 'inherit'),
                children: [
                  TextSpan(text: 'Tube', style: TextStyle(color: Colors.black)),
                  TextSpan(text: 'Pilot', style: TextStyle(color: AppColors.purple)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())).then((_) => _load(showLoader: false)),
              ),
              if (unreadCount > 0)
                Positioned(right: 10, top: 10, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle))),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 2),
            child: Tooltip(
              message: context.tr('profile_tooltip'),
              child: GestureDetector(
                onTap: _goToProfile,
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
                  ),
                  // Always shows the signed-up TubePilot account's email
                  // first letter — never a connected YouTube channel's
                  // logo/photo — and now always agrees with what Settings
                  // shows, since both read from AuthProvider.
                  child: Text(
                    _userInitial(context),
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: () => _load(showLoader: false),
              child: ListView(
                // ⚠️ TIGHTENED FURTHER (Boss request — "sabhi ko aur upar
                // karo"): top padding trimmed from 8 → 4.
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                children: [
                  // ---------------- Greeting ----------------
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black),
                      children: [
                        TextSpan(text: '${context.tr('hello_greeting')} '),
                        TextSpan(text: '${_userFirstName(context)}! 👋', style: const TextStyle(color: AppColors.purple)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(context.tr('welcome_back_subtitle'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                  // ⚠️ TIGHTENED: 14 → 12.
                  const SizedBox(height: 12),

                  // ---------------- Stats grid (real data) ----------------
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    // ⚠️ FIX (Boss request — "BOTTOM OVERFLOWED" red pixel
                    // errors on every metric card): 1.6 was too short for
                    // the icon + label + value (+ subtitle) column to fit,
                    // so every card clipped its bottom row. Lowered to 1.3
                    // (taller cards) — combined with the tightened
                    // _MetricCard padding/spacing below — so the content
                    // fits with room to spare instead of overflowing.
                    childAspectRatio: 1.3,
                    children: [
                      _MetricCard(
                        icon: Icons.cloud_upload_rounded,
                        label: context.tr('stat_free_uploads_left'),
                        value: '${data?['remainingFreeUploads'] ?? 0}',
                        subtitle: context.tr('resets_30_days'),
                      ),
                      _MetricCard(
                        icon: Icons.diamond_rounded,
                        label: context.tr('stat_diamond_balance'),
                        value: '$diamondBalance',
                        subtitle: worthUploads > 0 ? context.tr('diamonds_worth_uploads').replaceAll('%d', '$worthUploads') : null,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen())).then((_) => _load(showLoader: false)),
                      ),
                      _MetricCard(
                        icon: Icons.play_circle_fill_rounded,
                        label: context.tr('stat_videos_published'),
                        value: '${data?['totalUploadedVideos'] ?? 0}',
                        subtitle: context.tr('total_videos'),
                      ),
                      _MetricCard(
                        icon: Icons.event_available_rounded,
                        label: context.tr('scheduled_videos'),
                        value: '${upcomingEvents.length}',
                        subtitle: context.tr('this_month'),
                      ),
                    ],
                  ),
                  // ⚠️ FIX (Boss request — "quick action ke upar gap hai
                  // use hatao aur quick action ko aur upar karo"): 14 → 6.
                  const SizedBox(height: 6),

                  // ---------------- Quick Actions ----------------
                  Text(context.tr('quick_actions'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _quickAction(
                        icon: Icons.cloud_upload_rounded,
                        label: context.tr('qa_upload_video'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen())).then((_) => _load(showLoader: false)),
                      ),
                      _quickAction(
                        icon: Icons.bar_chart_rounded,
                        label: context.tr('qa_video_analytics'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalyticsScreen())),
                      ),
                      _quickAction(
                        icon: Icons.auto_awesome_rounded,
                        label: context.tr('qa_ai_ideas'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiIdeasScreen())),
                      ),
                      _quickAction(
                        icon: Icons.notes_rounded,
                        label: context.tr('qa_description_ideas'),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const AiTitleDescriptionScreen(startInDescriptionMode: true))),
                      ),
                      _quickAction(
                        icon: Icons.fact_check_rounded,
                        label: context.tr('qa_channel_audit'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChannelAuditScreen())),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ---------------- Upcoming Schedule ----------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('upcoming_schedule'),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UpcomingScreen())),
                        child: Text(context.tr('see_all'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (upcomingEvents.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
                      child: Text(context.tr('no_upcoming_publishes'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                    )
                  else
                    ...upcomingEvents.map((e) => _mediaRow(
                          context,
                          thumbnailUrl: e['thumbnailUrl'],
                          title: e['title'] ?? '',
                          platform: e['platform'],
                          badgeLabel: e['status'] == 'pending' ? context.tr('status_scheduled') : context.tr('status_queued'),
                          dateLabel: e['scheduledAt'] != null ? formatDateTime(e['scheduledAt']) : context.tr('publishing_now'),
                          onTap: () => _openPreview(e),
                        )),
                  const SizedBox(height: 14),

                  // ---------------- Recent Activity (real uploaded videos) ----------------
                  Text(context.tr('recent_activity_home'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  if (recentVideos.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
                      child: Text(context.tr('no_recent_activity'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                    )
                  else
                    ...recentVideos.map((e) => _mediaRow(
                          context,
                          thumbnailUrl: e['thumbnailUrl'],
                          title: e['title'] ?? '',
                          platform: e['platform'],
                          badgeLabel: context.tr('status_published'),
                          dateLabel: formatDate(e['publishedAt'] ?? e['scheduledAt']),
                        )),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _quickAction({required IconData icon, required String label, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _mediaRow(
    BuildContext context, {
    required String? thumbnailUrl,
    required String title,
    required String? platform,
    required String badgeLabel,
    required String dateLabel,
    VoidCallback? onTap,
  }) {
    final meta = _platformMeta(context, platform);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                  ? Image.network(
                      thumbnailUrl,
                      width: 56, height: 56, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _thumbnailFallback(meta.color),
                    )
                  : _thumbnailFallback(meta.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _platformBadgeIcon(platform),
                      const SizedBox(width: 5),
                      Text(meta.label, style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(dateLabel, style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppBadge(label: badgeLabel, color: meta.color),
          ],
        ),
      ),
    );
  }

  Widget _thumbnailFallback(Color color) {
    return Container(
      width: 56, height: 56,
      alignment: Alignment.center,
      color: color.withValues(alpha: 0.14),
      child: Icon(Icons.movie_outlined, color: color, size: 22),
    );
  }

  Widget _platformBadgeIcon(String? platform) {
    switch (platform) {
      case 'youtube':
        return const YoutubeIcon(size: 13);
      case 'facebook':
        return const FacebookIcon(size: 13);
      default:
        return const Icon(Icons.movie_outlined, size: 13);
    }
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;
  const _MetricCard({required this.icon, required this.label, required this.value, this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // ⚠️ TIGHTENED (Boss's overflow fix, alongside the 1.3 aspect
        // ratio above): vertical padding 10 → 8, plus the internal gaps
        // below, so there's extra breathing room even on smaller screens.
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.surfaces.card2,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.purple.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: AppColors.purple, size: 14),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: context.surfaces.textDim, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 1),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              Text(subtitle!, style: TextStyle(color: context.surfaces.textDim, fontSize: 9.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// AI Idea popup — Boss request: after signup's channel-connect step (see
// username_setup_screen.dart) AND again every 24 hours from the dashboard
// (see _maybeShowIdeaPopup above), show 3 real ideas from POST /api/ai/ideas,
// personalized to the connected channel's niche when known, plus a Skip
// option.
// Public (not private to this file) so username_setup_screen.dart can call
// showIdeaPopup() directly without duplicating this widget.
//
// ⚠️ UPDATED AGAIN (Boss request — "ideas card ko fanned/stacked photo
// look banao jaise reference image, aur copy button ka background bilkul
// kuch nahi/transparent hona chahiye"): the peek cards behind the active
// card are now rotated (fanned outward from the bottom, like a spread hand
// of photos) instead of just scaled straight-on rectangles — see
// _peekCard's `angle` param. The Copy button was switched from an
// OutlinedButton (which still paints a visible border/box) to a bare
// TextButton.icon with no border and an explicitly transparent background,
// so nothing renders around it at rest.
// =============================================================================

Future<void> showIdeaPopup(BuildContext context, {String? channelNiche}) async {
  List<Map<String, dynamic>> ideas = [];
  try {
    final res = await ApiService.instance.aiIdeas(
      niche: channelNiche ?? 'Tech',
      platform: 'youtube',
      count: 3,
    );
    ideas = (res['ideas'] as List? ?? []).cast<Map<String, dynamic>>();
  } catch (_) {
    // Silent failure — this is a soft nudge popup, not a core flow, so a
    // failed fetch just means no popup rather than blocking the user.
  }
  if (ideas.isEmpty || !context.mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _IdeaPopupDialog(ideas: ideas.take(3).toList()),
  );
}

// Tiny data holder for one in-flight "reaction flew up" animation. Each tap
// gets its own instance + key so multiple fast taps can animate at once
// without interrupting each other.
class _FlyingEmoji {
  final Key id;
  final String emoji;
  _FlyingEmoji(this.id, this.emoji);
}

class _IdeaPopupDialog extends StatefulWidget {
  final List<Map<String, dynamic>> ideas;
  const _IdeaPopupDialog({required this.ideas});
  @override
  State<_IdeaPopupDialog> createState() => _IdeaPopupDialogState();
}

class _IdeaPopupDialogState extends State<_IdeaPopupDialog> {
  late final PageController _pageController;
  int _index = 0;
  static const _reactions = ['🔥', '😍', '🤔', '👎'];

  final List<_FlyingEmoji> _flyingEmojis = [];
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Tapping a reaction (or reaching the end of a swipe past the last card)
  // moves straight to the next idea; on the last idea it closes the popup
  // — same "auto-advance" behavior Boss asked for, just now driven by the
  // PageController instead of a plain index bump.
  void _goNext() {
    if (_index < widget.ideas.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      Navigator.of(context).pop();
    }
  }

  // Boss request: "reaction pe click karo to reaction upar jaake usi idea
  // pe gayab ho jaaye". Kicks off a floating emoji (see _buildFlyingEmoji)
  // and fades/shrinks the current card out, THEN advances to the next idea
  // once both finish.
  Future<void> _onReactionTap(String emoji) async {
    final flyId = UniqueKey();
    setState(() {
      _flyingEmojis.add(_FlyingEmoji(flyId, emoji));
      _dismissing = true;
    });

    // Card fade+shrink duration — advance once it's fully faded.
    await Future.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    setState(() => _dismissing = false);
    _goNext();

    // Let the flying emoji finish its own (longer) rise-and-fade before
    // removing it from the tree.
    await Future.delayed(const Duration(milliseconds: 360));
    if (mounted) setState(() => _flyingEmojis.removeWhere((f) => f.id == flyId));
  }

  // Copy button handler. Uses Flutter's built-in Clipboard API
  // (package:flutter/services.dart) — no new pubspec dependency needed.
  Future<void> _copyIdea(Map<String, dynamic> idea) async {
    final title = (idea['title'] ?? '').toString();
    final desc = (idea['description'] ?? idea['hook'] ?? '').toString();
    final text = desc.isNotEmpty ? '$title\n\n$desc' : title;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(context, context.tr('idea_popup_copied_toast'), isSuccess: true);
  }

  // ⚠️ REDESIGNED — purely decorative "peeking card" behind the active
  // card, now rotated + pivoted from the bottom so the stack reads as a
  // fanned-out spread of photos (per the reference image) instead of a
  // flat scaled rectangle sitting directly behind the front card.
  Widget _peekCard({required double angle, required double top, required double opacity, required double scale}) {
    return Positioned(
      top: top,
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.bottomCenter,
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 230,
              height: 178,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.purple.withValues(alpha: 0.18)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ideaCard(Map<String, dynamic> idea, int idx) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.surfaces.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.lightbulb_rounded, color: AppColors.purple, size: 15),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('idea_popup_card_label').replaceAll('%d', '${idx + 1}'),
                    style: TextStyle(color: context.surfaces.textDim, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(idea['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            Text(idea['description'] ?? idea['hook'] ?? '', style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, height: 1.35)),
          ],
        ),
      ),
    );
  }

  // One floating reaction emoji: starts at the reaction row, rises ~90px
  // while fading out, using a single TweenAnimationBuilder so no extra
  // AnimationController lifecycle to manage per tap.
  Widget _buildFlyingEmoji(_FlyingEmoji f) {
    return Positioned.fill(
      key: f.id,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOut,
          builder: (context, t, child) {
            return Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -90 * t),
                child: Align(
                  alignment: const Alignment(0, 0.72),
                  child: Transform.scale(
                    scale: 1 + (0.4 * (1 - t)),
                    child: Text(f.emoji, style: const TextStyle(fontSize: 28)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      // Wraps everything so the flying-emoji overlay can sit on top of the
      // reaction row / copy button, not just the card area.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome_rounded, color: AppColors.purple, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.tr('idea_popup_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  Text('${_index + 1}/${widget.ideas.length}', style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                ]),
                const SizedBox(height: 18),

                // ---- Swipeable fanned card stack ----
                // Left/right swipe on the PageView moves between the 3 ideas
                // (Boss's "scroll se ideas badalte rahen" requirement) — no
                // extra gesture wiring needed, PageView handles that natively.
                // The two cards behind are rotated outward from the bottom
                // (Boss's "fanned photo stack" reference image) so they peek
                // out on alternating sides of the straight, front-facing
                // active card.
                SizedBox(
                  height: 232,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.none,
                    children: [
                      if (_index < widget.ideas.length - 2)
                        _peekCard(angle: -0.15, top: 18, opacity: 0.45, scale: 0.92),
                      if (_index < widget.ideas.length - 1)
                        _peekCard(angle: 0.11, top: 10, opacity: 0.7, scale: 0.96),
                      // Active card fades + shrinks slightly whenever a
                      // reaction is tapped (Boss's "card bhi gayab ho" ask),
                      // instead of just snapping to the next page.
                      AnimatedOpacity(
                        opacity: _dismissing ? 0 : 1,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: AnimatedScale(
                          scale: _dismissing ? 0.88 : 1,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: widget.ideas.length,
                            onPageChanged: (i) => setState(() => _index = i),
                            itemBuilder: (_, i) => Center(child: _ideaCard(widget.ideas[i], i)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr('idea_popup_swipe_hint'),
                  style: TextStyle(color: context.surfaces.textDim, fontSize: 10.5, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 14),

                // Emoji reactions — tapping any of them flies the emoji up
                // (see _buildFlyingEmoji), dismisses the current card, then
                // advances to the next idea automatically (or closes the
                // dialog on the last one).
                Container(
                  color: Colors.transparent,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _reactions.map((e) => GestureDetector(
                      onTap: () => _onReactionTap(e),
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 14),

                // ⚠️ FIX (Boss request — "copy button ke background me
                // kuch nahi, bilkul transparent"): swapped OutlinedButton
                // (which still paints a visible border box around itself)
                // for a bare TextButton.icon — no border, no fill, nothing
                // rendered at rest besides the icon + label themselves.
                Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    ),
                    onPressed: () => _copyIdea(widget.ideas[_index]),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: Text(context.tr('idea_popup_copy_btn')),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.tr('skip')),
                ),
              ],
            ),
          ),
          ..._flyingEmojis.map(_buildFlyingEmoji),
        ],
      ),
    );
  }
}