import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../providers/language_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> notifications = [];
  bool loading = true;

  // Real Material icons per notification type, replacing the previous
  // emoji-only icons — each gets its own color too, so the icon itself
  // communicates status (green = success, red = failure, amber = pending/
  // expiring, purple = informational) at a glance without reading the text.
  static const _typeIcons = <String, (IconData, Color)>{
    'payment_approved': (Icons.check_circle_rounded, AppColors.green),
    'payment_rejected': (Icons.cancel_rounded, AppColors.red),
    'upload_completed': (Icons.cloud_done_rounded, AppColors.green),
    'upload_failed': (Icons.error_rounded, AppColors.red),
    'schedule_started': (Icons.hourglass_top_rounded, AppColors.diamond),
    'schedule_finished': (Icons.movie_creation_rounded, AppColors.purple),
    'subscription_expiring': (Icons.alarm_rounded, AppColors.diamond),
    'free_upload_reset': (Icons.card_giftcard_rounded, AppColors.purpleLight),
    'milestone': (Icons.emoji_events_rounded, AppColors.diamond),
  };
  static const _defaultIcon = (Icons.notifications_rounded, AppColors.purple);

  @override
  void initState() {
    super.initState();
    _load();
    // ⚠️ FIX (companion to the main.dart / push_service.dart notification
    // fix): this screen previously only ever refreshed on initial load or
    // a manual pull-to-refresh. Even once push delivery itself started
    // working, a notification that arrived while this screen was already
    // open wouldn't show up until the user thought to swipe down — easy to
    // mistake for "it still isn't arriving". Now it listens for
    // PushService's signal and reloads the instant a push comes in.
    PushService.newNotificationSignal.addListener(_load);
  }

  @override
  void dispose() {
    PushService.newNotificationSignal.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final res = await ApiService.instance.getNotifications();
      setState(() => notifications = res['notifications']);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ApiService.instance.markAllNotificationsRead();
      if (mounted) showToast(context, context.tr('all_marked_read'), isSuccess: true);
      _load();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  // Single-notification delete — used by the swipe-to-dismiss gesture below.
  // Removes it from the local list immediately (optimistic) and calls the
  // backend; if the backend call fails, reloads the real list so the UI
  // doesn't show a stale "deleted" state.
  Future<void> _deleteOne(String id, int index) async {
    final removed = notifications[index];
    setState(() => notifications.removeAt(index));
    try {
      await ApiService.instance.deleteNotification(id);
      if (mounted) showToast(context, context.tr('notification_deleted'), isSuccess: true);
    } catch (e) {
      // Roll back the optimistic removal and show the real error.
      if (mounted) {
        setState(() => notifications.insert(index, removed));
        showApiError(context, e);
      }
    }
  }

  Future<void> _deleteAll() async {
    if (notifications.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_all_confirm_title')),
        content: Text(context.tr('delete_all_confirm_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('delete'), style: const TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.instance.deleteAllNotifications();
      if (mounted) {
        setState(() => notifications = []);
        showToast(context, context.tr('all_notifications_deleted'), isSuccess: true);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('notifications')),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: context.tr('mark_all_read_tooltip'),
            onPressed: _markAllRead,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: context.tr('delete_all_tooltip'),
            onPressed: notifications.isEmpty ? null : _deleteAll,
          ),
        ],
      ),
      body: loading
          ? const LoadingView()
          : notifications.isEmpty
              ? Center(child: EmptyView(message: context.tr('no_notifications_yet'), icon: Icons.notifications_none))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: notifications.length,
                    itemBuilder: (_, i) {
                      final n = notifications[i];
                      final id = (n['_id'] ?? n['id'] ?? '').toString();
                      final (icon, iconColor) = _typeIcons[n['type']] ?? _defaultIcon;

                      return Dismissible(
                        key: ValueKey(id.isNotEmpty ? id : i),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.delete_rounded, color: Colors.white),
                        ),
                        onDismissed: id.isEmpty ? null : (_) => _deleteOne(id, i),
                        child: Opacity(
                          opacity: n['isRead'] == true ? 0.6 : 1,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(14)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                                  child: Icon(icon, color: iconColor, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Text(n['message'] ?? '', style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
                                      const SizedBox(height: 4),
                                      Text(formatDateTime(n['createdAt']), style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
                                    ],
                                  ),
                                ),
                                if (id.isNotEmpty)
                                  IconButton(
                                    icon: Icon(Icons.close_rounded, size: 18, color: context.surfaces.textDim),
                                    tooltip: context.tr('delete'),
                                    onPressed: () => _deleteOne(id, i),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}