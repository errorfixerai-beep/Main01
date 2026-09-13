import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart' as custom_tabs;
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../providers/language_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/brand_icons.dart';
import 'wallet_screen.dart';
import 'diamond_store_screen.dart';
import 'gift_code_screen.dart';
import 'notifications_screen.dart';
import 'admin_screen.dart';
import 'refer_earn_screen.dart';
import 'about_screen.dart';
import 'privacy_policy_screen.dart';
import 'rate_us_screen.dart';
import 'settings_screen.dart';
import 'ai_ideas_screen.dart';
import 'ai_title_description_screen.dart';
import 'seo_optimizer_screen.dart';
import 'competitor_radar_screen.dart';
import 'smart_scheduler_screen.dart';
import 'visual_analyzer_screen.dart';
import 'channel_audit_screen.dart';
import 'wallet_refund_logs_screen.dart';
import 'my_videos_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool embedded;
  const ProfileScreen({super.key, this.embedded = false});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ⚠️ These are now KEYS into app_strings.dart, not display text — the
  // label shown to the user (and passed back to _sendSupportEmail) is
  // resolved via context.tr(key) at render time, so this list follows the
  // selected app language everywhere it's used.
  static const _supportCategoryKeys = [
    'support_cat_payment',
    'support_cat_upload_failed',
    'support_cat_youtube_connection',
    'support_cat_facebook_connection',
    'support_cat_account_login',
    'support_cat_app_bug',
    'support_cat_other',
  ];

  Map<String, dynamic>? _metaStatus; // { facebook: {...}|null }
  bool _loadingMeta = true;

  // Live YouTube channel info (subscriber count etc.) — fetched separately
  // from AuthProvider's cached user object, because GET /youtube/channel
  // now refreshes the subscriber count live from the YouTube API on every
  // call (see routes/youtube.js) instead of returning a value that was only
  // ever set once at OAuth-connect time. AuthProvider's user['youtubeChannel']
  // is still used as the "is a channel connected at all" source of truth and
  // as an instant-paint fallback while this live fetch is in flight.
  Map<String, dynamic>? _liveChannel;
  bool _loadingChannel = false;

  // DIAGNOSTIC: if the live fetch silently fails (network error, expired
  // token that also fails to refresh, backend error, etc.) the UI used to
  // just fall back to the stale cached count with zero visibility into why.
  // This flag surfaces that failure state so the subscriber card can show
  // a small "tap to retry" hint instead of quietly showing a wrong number.
  bool _liveChannelFetchFailed = false;

  @override
  void initState() {
    super.initState();
    // IMPORTANT: refreshUser() and _loadLiveChannel() both read
    // AuthProvider's cached user. Previously refreshUser() was fired via
    // addPostFrameCallback (fire-and-forget) while _loadLiveChannel() ran
    // immediately after on the OLD cached user — meaning if the cached
    // 'youtubeChannel' was stale/null at that exact moment, the live fetch
    // could silently no-op. Now we await refreshUser() first, THEN run
    // _loadLiveChannel(), so it always reads the freshest possible cached
    // user before deciding whether a channel is connected.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AuthProvider>().refreshUser();
      if (mounted) _loadLiveChannel();
    });
    _loadMetaStatus();
  }

  Future<void> _loadMetaStatus() async {
    try {
      final res = await ApiService.instance.getMetaStatus();
      setState(() => _metaStatus = res);
    } catch (_) {
      setState(() => _metaStatus = null);
    } finally {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  Future<void> _loadLiveChannel() async {
    final user = context.read<AuthProvider>().user ?? {};
    if (user['youtubeChannel'] == null) return; // nothing connected, skip the call
    setState(() {
      _loadingChannel = true;
      _liveChannelFetchFailed = false;
    });
    try {
      final res = await ApiService.instance.getYoutubeChannel();
      if (mounted) {
        setState(() {
          _liveChannel = res['channel'];
          _liveChannelFetchFailed = false;
        });
      }
      // DIAGNOSTIC: log so you can confirm in `flutter run` / adb logcat
      // output whether the live fetch actually returned fresh data, and
      // what subscriberCount it came back with.
      debugPrint('✅ [Profile] Live YouTube channel fetched: subscriberCount=${res['channel']?['subscriberCount']}, stale=${res['stale']}');
    } catch (e) {
      // Previously this failed completely silently — you'd just see the
      // stale cached count with no indication anything went wrong. Now it
      // logs the real error and flags the UI so you can tell "0 subscribers"
      // apart from "fetch is failing".
      debugPrint('❌ [Profile] Live YouTube channel fetch FAILED: $e');
      if (mounted) setState(() => _liveChannelFetchFailed = true);
    } finally {
      if (mounted) setState(() => _loadingChannel = false);
    }
  }

  Future<void> _openSupport() async {
    final categoryKey = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: context.surfaces.border, borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(context.tr('support_sheet_title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                ..._supportCategoryKeys.map((k) => ListTile(
                      title: Text(context.tr(k), style: const TextStyle(fontSize: 14)),
                      trailing: Icon(Icons.chevron_right, color: context.surfaces.textDim, size: 18),
                      onTap: () => Navigator.pop(sheetContext, k),
                    )),
              ],
            ),
          ),
        );
      },
    );

    if (categoryKey == null || !mounted) return;
    await _sendSupportEmail(categoryKey);
  }

  Future<void> _sendSupportEmail(String categoryKey) async {
    final category = context.tr(categoryKey);
    final user = context.read<AuthProvider>().user ?? {};
    final uri = Uri(
      scheme: 'mailto',
      path: 'anikkesharwani37@gmail.com',
      query: 'subject=${Uri.encodeComponent('TubePilot Support: $category')}'
          '&body=${Uri.encodeComponent('User ID: ${user['userId'] ?? '-'}\nEmail: ${user['email'] ?? '-'}\nCategory: $category\n\nDescribe your issue below:\n')}',
    );
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        showToast(context, '${context.tr('no_email_app_found')} anikkesharwani37@gmail.com', isError: true);
      }
    } catch (_) {
      if (mounted) showToast(context, '${context.tr('no_email_app_found')} anikkesharwani37@gmail.com', isError: true);
    }
  }

  Future<void> _launchOAuth(String url) async {
    await custom_tabs.launchUrl(
      Uri.parse(url),
      customTabsOptions: custom_tabs.CustomTabsOptions(
        shareState: custom_tabs.CustomTabsShareState.off,
        urlBarHidingEnabled: true,
        showTitle: true,
      ),
      safariVCOptions: const custom_tabs.SafariViewControllerOptions(
        barCollapsingEnabled: true,
        dismissButtonStyle: custom_tabs.SafariViewControllerDismissButtonStyle.close,
      ),
    );
  }

  Future<void> _connectYoutube() async {
    try {
      final res = await ApiService.instance.getYoutubeOAuthUrl();
      if (res['url'] != null) await _launchOAuth(res['url']);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _openYoutubeOptions(Map<String, dynamic> channel) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: context.surfaces.border, borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    channel['thumbnail'] != null && channel['thumbnail'].toString().isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              channel['thumbnail'],
                              width: 36, height: 36, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const YoutubeIcon(size: 20),
                            ),
                          )
                        : const YoutubeIcon(size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(channel['channelTitle'] ?? context.tr('up_youtube_label'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${channel['subscriberCount'] ?? 0} ${context.tr('subscribers_label')}', style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Divider(color: context.surfaces.border, height: 1),
                ListTile(
                  leading: const Icon(Icons.link_off_rounded, color: AppColors.red),
                  title: Text(context.tr('disconnect_action'), style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(sheetContext, 'disconnect'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == 'disconnect') await _disconnectYoutube();
  }

  Future<void> _disconnectYoutube() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('disconnect_youtube_title')),
        content: Text(context.tr('disconnect_youtube_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('disconnect_action'), style: const TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.instance.disconnectYoutube();
      if (mounted) {
        showToast(context, context.tr('youtube_disconnected_toast'), isSuccess: true);
        setState(() => _liveChannel = null);
        context.read<AuthProvider>().refreshUser();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _connectMeta() async {
    try {
      final res = await ApiService.instance.getMetaOAuthUrl();
      if (res['url'] != null) await _launchOAuth(res['url']);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _disconnectFacebook() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('disconnect_facebook_title')),
        content: Text(context.tr('disconnect_facebook_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('disconnect_action'), style: const TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.instance.disconnectFacebook();
      if (mounted) {
        showToast(context, context.tr('facebook_disconnected_toast'), isSuccess: true);
        _loadMetaStatus();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _connectTile({
    required Widget icon,
    required String label,
    required String status,
    required bool connected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (connected ? AppColors.green : context.surfaces.textDim).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: icon,
              ),
              const SizedBox(height: 8),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: connected ? AppColors.green : context.surfaces.textDim, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  /// Instagram is never connected independently — the backend auto-attaches
  /// whichever Instagram Business Account is linked to the chosen Facebook
  /// Page (see routes/meta.js). This tile just reflects that: shows the
  /// linked @username + a green [Connected] chip when present, or a "Linked
  /// automatically with Facebook" hint when Facebook is connected but the
  /// Page has no Instagram account attached.
  Widget _instagramTile(Map<String, dynamic>? instagram, bool facebookIsConnected) {
    final connected = instagram != null;
    final username = instagram?['igUsername'] as String?;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            connected
                ? CircleAvatar(
                    radius: 20,
                    backgroundColor: (AppColors.green).withValues(alpha: 0.14),
                    backgroundImage: (instagram['igProfilePicture'] ?? '').toString().isNotEmpty
                        ? NetworkImage(instagram['igProfilePicture'])
                        : null,
                    child: (instagram['igProfilePicture'] ?? '').toString().isEmpty
                        ? const InstagramIcon(size: 20)
                        : null,
                  )
                : Container(
                    width: 40, height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: context.surfaces.textDim.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                    child: const InstagramIcon(size: 20),
                  ),
            const SizedBox(height: 8),
            Text(
              connected ? '@${username ?? ''}' : context.tr('instagram_label'),
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            if (connected)
              AppBadge(label: context.tr('connected_label'), color: AppColors.green)
            else
              Text(
                facebookIsConnected ? context.tr('no_ig_on_page') : context.tr('auto_linked_facebook'),
                maxLines: 2, textAlign: TextAlign.center,
                style: TextStyle(color: context.surfaces.textDim, fontSize: 10, fontWeight: FontWeight.w600, height: 1.2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _youtubeSubscriberCard(Map<String, dynamic>? cachedChannel) {
    final channel = _liveChannel ?? cachedChannel;

    if (channel == null) {
      return GestureDetector(
        onTap: _connectYoutube,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: context.surfaces.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: context.surfaces.textDim.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: const YoutubeIcon(size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('connect_youtube_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(context.tr('connect_youtube_subtitle'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.surfaces.textDim),
            ],
          ),
        ),
      );
    }

    final subs = channel['subscriberCount']?.toString() ?? '0';
    final title = channel['channelTitle'] ?? context.tr('up_youtube_label');
    final thumbnail = (channel['thumbnail'] ?? '').toString();

    return GestureDetector(
      onTap: () => _openYoutubeOptions(channel),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.red.withValues(alpha: 0.10), AppColors.red.withValues(alpha: 0.02)]),
          border: Border.all(color: context.surfaces.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            thumbnail.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      thumbnail,
                      width: 48, height: 48, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.14), shape: BoxShape.circle),
                        child: const YoutubeIcon(size: 24),
                      ),
                    ),
                  )
                : Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.14), shape: BoxShape.circle),
                    child: const YoutubeIcon(size: 24),
                  ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _formatSubscriberCount(subs),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.red),
                      ),
                      const SizedBox(width: 6),
                      Text(context.tr('subscribers_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12, fontWeight: FontWeight.w600)),
                      if (_loadingChannel) ...[
                        const SizedBox(width: 8),
                        SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6, color: context.surfaces.textDim)),
                      ],
                      // DIAGNOSTIC: small tap-to-retry hint if the live fetch
                      // failed, so a stale/wrong count is never shown without
                      // any indication that something's off.
                      if (_liveChannelFetchFailed && !_loadingChannel) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _loadLiveChannel,
                          child: Icon(Icons.refresh_rounded, size: 14, color: context.surfaces.textDim),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.more_horiz_rounded, color: context.surfaces.textDim),
          ],
        ),
      ),
    );
  }

  String _formatSubscriberCount(String raw) {
    final n = int.tryParse(raw);
    if (n == null) return raw;
    if (n >= 10000000) return '${(n / 10000000).toStringAsFixed(1)}Cr';
    if (n >= 100000) return '${(n / 100000).toStringAsFixed(1)}L';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    // Watching LanguageProvider here (even though this screen doesn't call
    // context.tr() everywhere yet) makes the whole ProfileScreen rebuild
    // when the language changes, so the menu labels below — which DO use
    // context.tr() — actually update live instead of needing a re-navigate.
    context.watch<LanguageProvider>();

    final auth = context.watch<AuthProvider>();
    final user = auth.user ?? {};
    final channel = user['youtubeChannel'];

    final facebook = _metaStatus?['facebook'];
    final instagram = _metaStatus?['instagram'];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile_settings_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
        children: [
          _youtubeSubscriberCard(channel),
          const SizedBox(height: 16),

          // ⚠️ [ANIK REQUEST - YouTube-only launch]: entire "Connected
          // Accounts" section hidden — Meta business verification pending.
          // Untouched below, uncomment to restore.
          //
          // Text(context.tr('connected_accounts'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
          // const SizedBox(height: 8),
          // if (_loadingMeta)
          //   const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(color: AppColors.purple)))
          // else
          //   Row(
          //     crossAxisAlignment: CrossAxisAlignment.start,
          //     children: [
          //       _connectTile(
          //         icon: const FacebookIcon(size: 20),
          //         label: facebook?['pageName'] ?? 'Facebook',
          //         status: facebook == null ? context.tr('disconnect_action') : context.tr('connected_label'),
          //         connected: facebook != null,
          //         onTap: facebook == null ? _connectMeta : _disconnectFacebook,
          //       ),
          //       const SizedBox(width: 10),
          //       _instagramTile(instagram, facebook != null),
          //     ],
          //   ),
          // const SizedBox(height: 20),

          // ---------------- Creator OS (VidIQ-style tools) ----------------
          Text(context.tr('creator_os_section'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              _menuRow(Icons.auto_awesome_rounded, context.tr('menu_ai_ideas'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiIdeasScreen()))),
              _divider(),
              _menuRow(Icons.title_rounded, context.tr('menu_ai_title_desc'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiTitleDescriptionScreen()))),
              _divider(),
              _menuRow(Icons.query_stats_rounded, context.tr('menu_seo_optimizer'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeoOptimizerScreen()))),
              _divider(),
              _menuRow(Icons.radar_rounded, context.tr('menu_competitor_radar'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompetitorRadarScreen()))),
              _divider(),
              _menuRow(Icons.calendar_month_rounded, context.tr('menu_smart_scheduler'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SmartSchedulerScreen()))),
              _divider(),
              _menuRow(Icons.image_search_rounded, context.tr('menu_visual_analyzer'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VisualAnalyzerScreen()))),
              _divider(),
              _menuRow(Icons.fact_check_rounded, context.tr('menu_channel_audit'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChannelAuditScreen()))),
              _divider(),
              // ⚠️ NEW (Boss request — "My Videos" screen was missing an
              // entry point in Profile entirely, so nobody could open it).
              _menuRow(Icons.video_collection_rounded, context.tr('menu_my_videos'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyVideosScreen()))),
              _divider(),
              _menuRow(Icons.receipt_long_rounded, context.tr('menu_wallet_refund_logs'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletRefundLogsScreen()))),
            ]),
          ),
          const SizedBox(height: 20),

          Container(
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              _menuRow(Icons.shopping_bag_rounded, context.tr('buy_diamonds'), AppColors.diamond,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen()))),
              _divider(),
              _menuRow(Icons.card_giftcard_rounded, context.tr('menu_gift_code'), AppColors.diamond,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GiftCodeScreen()))),
              _divider(),
              _menuRow(Icons.diamond_rounded, context.tr('subscription_wallet'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen()))),
              _divider(),
              _menuRow(Icons.card_giftcard_rounded, context.tr('refer_earn'), AppColors.green,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferEarnScreen()))),
              _divider(),
              _menuRow(Icons.notifications_rounded, context.tr('notifications'), AppColors.purpleLight,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
              _divider(),
              _menuRow(Icons.help_rounded, context.tr('help_support'), AppColors.purple, _openSupport),
              if (auth.isAdmin) ...[
                _divider(),
                _menuRow(Icons.admin_panel_settings_rounded, context.tr('admin_panel'), AppColors.red,
                    () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen()))),
              ],
            ]),
          ),
          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              _menuRow(Icons.info_rounded, context.tr('about'), AppColors.purpleLight,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()))),
              _divider(),
              _menuRow(Icons.privacy_tip_rounded, context.tr('privacy_policy'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()))),
              _divider(),
              _menuRow(Icons.star_rounded, context.tr('rate_us'), AppColors.diamond,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RateUsScreen()))),
              _divider(),
              _menuRow(Icons.settings_rounded, context.tr('settings_menu'), AppColors.purple,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
            ]),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 17),
      ),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: Icon(Icons.chevron_right, color: context.surfaces.textDim),
      onTap: onTap,
    );
  }

  Widget _divider() => Divider(height: 1, color: context.surfaces.border);
}