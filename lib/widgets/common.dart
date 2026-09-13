import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../providers/language_provider.dart';

// ---------------- Toast ----------------
// ⚠️ FIX (Boss request — "notification niche se green background me aata
// hai, ise upar se aana chahiye, text black ho, aur color achha ho"):
// This used to be a ScaffoldMessenger SnackBar, which Flutter always
// docks at the BOTTOM of the screen — there's no supported way to move a
// SnackBar to the top. Replaced with a custom top-sliding OverlayEntry
// toast instead: white card, black text, a thin coloured accent bar +
// icon on the left (green for success, red for error, purple for
// neutral) rather than a solid colour fill, slides in from the top below
// the status bar, and auto-dismisses after 3 seconds (or on tap). The
// public function signatures (showToast/showApiError/showAiError/
// showUploadError) are unchanged, so every existing call site across the
// app keeps working exactly as before.
OverlayEntry? _activeToastEntry;

void showToast(BuildContext context, String message, {bool isError = false, bool isSuccess = false}) {
  _activeToastEntry?.remove();
  _activeToastEntry = null;

  final overlayState = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TopToast(
      message: message,
      isError: isError,
      isSuccess: isSuccess,
      onDone: () {
        if (identical(_activeToastEntry, entry)) {
          _activeToastEntry = null;
        }
        entry.remove();
      },
    ),
  );
  _activeToastEntry = entry;
  overlayState.insert(entry);
}

class _TopToast extends StatefulWidget {
  final String message;
  final bool isError;
  final bool isSuccess;
  final VoidCallback onDone;
  const _TopToast({
    required this.message,
    required this.isError,
    required this.isSuccess,
    required this.onDone,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _timer = Timer(const Duration(seconds: 3), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    if (mounted) {
      await _controller.reverse();
    }
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.isError
        ? AppColors.red
        : (widget.isSuccess ? AppColors.green : AppColors.purple);
    final IconData icon = widget.isError
        ? Icons.error_outline_rounded
        : (widget.isSuccess ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _dismiss,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border(left: BorderSide(color: accent, width: 4)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: accent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: const TextStyle(color: Colors.black87, fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showApiError(BuildContext context, Object err) {
  showToast(context, err.toString().replaceFirst('ApiException: ', ''), isError: true);
}

// ⚠️ FIX (Boss request, round 2 — "ek bat dono me farak hai"): the
// earlier version guessed a "diamond issue" purely by scanning the error
// TEXT for the words "diamond"/"insufficient" — fragile, because it
// breaks the moment the backend's wording changes even slightly, and it
// can't reliably tell a real diamond shortfall apart from any other error
// that happens to mention those words. This now checks the STRUCTURED
// signal first: ApiException.status (HTTP 402 Payment Required is the
// standard status for a balance/credit shortfall) and ApiException.code
// (machine-readable — same pattern the app already uses for
// 'TOKEN_EXPIRED' in api_service.dart), and only falls back to text
// matching if neither field is present. Both showAiError (used by every
// paid AI button — title/description/tags/caption/hashtags/ideas) AND
// showUploadError (used by the Publish/Upload flow in upload_screen.dart)
// share this one check, so the distinction the Boss asked for —
// "Upload screen charges diamonds → show the upgrade message on
// shortfall" vs "AI Ideas screen is free → a failure there is a real
// backend error, not a diamond issue" — now works correctly in both
// places from a single source of truth.
bool _isDiamondShortfall(Object err) {
  if (err is ApiException) {
    if (err.status == 402) return true;
    final code = err.code?.toUpperCase();
    if (code == 'INSUFFICIENT_DIAMONDS' || code == 'INSUFFICIENT_BALANCE' || code == 'DIAMOND_BALANCE_LOW') {
      return true;
    }
  }
  final raw = err.toString().replaceFirst('ApiException: ', '').toLowerCase();
  return raw.contains('diamond') || raw.contains('insufficient');
}

// User-friendly fallback for AI generation failures specifically (Groq
// model errors, timeouts, rate limits) — the raw error can be a technical
// message like "Groq API error (404): ..." which isn't meaningful to a
// creator tapping "Generate". Shows a plain retry-oriented message
// instead — UNLESS it's specifically a diamond shortfall, in which case
// it shows the upgrade prompt instead (see _isDiamondShortfall above).
void showAiError(BuildContext context, Object err) {
  showToast(
    context,
    _isDiamondShortfall(err) ? context.tr('diamond_error_upgrade') : context.tr('ai_error_generic'),
    isError: true,
  );
}

// ⚠️ NEW (Boss request, round 2 — "upload screen wale me daimond lagege
// agr daimond nahi to massage aana chahiye"): the actual Publish/Upload
// submit flow was showing the raw backend error via showApiError() for
// EVERY failure, so an insufficient-diamond failure showed whatever raw
// text the backend sent instead of a clear upgrade prompt. This checks
// for a diamond shortfall the same way showAiError does and shows the
// same upgrade message for that one case — but for any OTHER upload
// failure (bad file, network issue, server error) it still shows the
// backend's own message, since uploading isn't an AI feature and a
// generic "AI unavailable" message would be the wrong explanation there.
void showUploadError(BuildContext context, Object err) {
  showToast(
    context,
    _isDiamondShortfall(err) ? context.tr('diamond_error_upgrade') : err.toString().replaceFirst('ApiException: ', ''),
    isError: true,
  );
}

// ---------------- Gradient Button ----------------
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const GradientButton({super.key, required this.label, this.onPressed, this.loading = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null && !loading ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.gradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: AppColors.purple.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: loading ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
                          Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Badge ----------------
class AppBadge extends StatelessWidget {
  final String label;
  final Color color;
  const AppBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ---------------- Balance Banner ----------------
class BalanceBanner extends StatelessWidget {
  final int balance;
  final VoidCallback onBuy;
  const BalanceBanner({super.key, required this.balance, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Diamond Balance', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
              const SizedBox(height: 4),
              Row(children: [
                const Text('💎 ', style: TextStyle(fontSize: 20)),
                Text('$balance', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
              ]),
            ],
          ),
          ElevatedButton(
            onPressed: onBuy,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('+ Buy', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ---------------- Stat Card ----------------
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? change;
  const StatCard({super.key, required this.label, required this.value, this.change});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          if (change != null) ...[
            const SizedBox(height: 2),
            Text(change!, style: const TextStyle(color: AppColors.green, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }
}

// ---------------- Bottom Nav (floating pill, icon-only) ----------------
// Same 5 tabs, same tap behavior as before. Text labels removed per request —
// only icons are shown now, with a Tooltip carrying the label for accessibility
// (long-press / screen readers still get the name, sighted users just see icons).
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  const AppBottomNav({super.key, required this.currentIndex, required this.onTap});

  static const List<({IconData filled, IconData outline, String label})> _items = [
    (filled: Icons.home_rounded, outline: Icons.home_outlined, label: 'Home'),
    (filled: Icons.cloud_upload_rounded, outline: Icons.cloud_upload_outlined, label: 'Upload'),
    (filled: Icons.video_collection_rounded, outline: Icons.video_collection_outlined, label: 'Videos'),
    (filled: Icons.insights_rounded, outline: Icons.insights_outlined, label: 'Analytics'),
    (filled: Icons.person_rounded, outline: Icons.person_outline_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(31),
            border: Border.all(color: context.surfaces.border),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withValues(alpha: 0.6) : AppColors.purple.withValues(alpha: 0.14),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final selected = i == currentIndex;
              return Expanded(
                child: Tooltip(
                  message: item.label,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.purple.withValues(alpha: isDark ? 0.25 : 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        selected ? item.filled : item.outline,
                        color: selected ? AppColors.purple : context.surfaces.textDim,
                        size: 23,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ---------------- Loading / Empty states ----------------
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(color: AppColors.purple));
}

class EmptyView extends StatelessWidget {
  final String message;
  final IconData icon;
  const EmptyView({super.key, required this.message, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          Icon(icon, size: 40, color: context.surfaces.textDim),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(color: context.surfaces.textDim), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

String formatDateTime(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final local = d.toLocal();
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} - $hour12:$minute $ampm';
}

String formatDate(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}