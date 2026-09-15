import '../config.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import 'diamond_store_screen.dart';

/// ⚠️ NEW (Boss request): shows EVERY video the creator has — TubePilot's
/// own queued/uploaded records AND real videos already live on the
/// connected YouTube channel — combined via GET /videos/library (backend
/// merges duplicates: a TubePilot-uploaded video that's already live on
/// YouTube is shown once, using the live YouTube copy as the source of
/// truth).
class MyVideosScreen extends StatefulWidget {
  // ⚠️ NEW — set when opened from a share deep link
  // (tubepilot://video/<id>, see main.dart's _handleVideoDeepLink). When
  // present, the matching card is auto-scrolled-to and briefly
  // highlighted once the list finishes loading.
  final String? highlightVideoId;
  const MyVideosScreen({super.key, this.highlightVideoId});
  @override
  State<MyVideosScreen> createState() => _MyVideosScreenState();
}

class _MyVideosScreenState extends State<MyVideosScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _videos = [];
  // Whether AI-assist (spark icon) is usable — active subscription OR any
  // diamond balance. Loaded once from the dashboard, same data source the
  // rest of the app already uses for this. NOTE: this is a FRONTEND gate —
  // if backend-level enforcement is also wanted, the AI endpoints
  // themselves (routes/ai.js — not reviewed here) would need the same
  // check added server-side.
  bool _aiEligible = false;

  // ---------------- Highlight-on-open (deep link) ----------------
  // One GlobalKey per card, keyed by the same id used to match
  // widget.highlightVideoId, so we can locate + scroll to the right card
  // after the list is built (ListView.builder items don't have a fixed
  // height, so we can't just compute an offset from the index).
  final Map<String, GlobalKey> _cardKeys = {};
  String? _highlightedId;
  bool _highlightHandled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _idOf(Map<String, dynamic> item) {
    final id = item['ytVideoId'] ?? item['dbId'];
    return id?.toString();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.getVideoLibrary(),
        ApiService.instance.dashboard(),
      ]);
      final dash = results[1]['data'];
      final sub = dash?['subscription'];
      final isPremiumActive = sub != null && sub['isActive'] == true;
      final diamondBalance = (dash?['diamondBalance'] ?? 0) as num;
      setState(() {
        _videos = (results[0]['videos'] as List? ?? []).cast<Map<String, dynamic>>();
        _aiEligible = isPremiumActive || diamondBalance > 0;
      });
      _maybeScrollToHighlighted();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Only runs once per screen instance (e.g. pull-to-refresh afterwards
  // shouldn't keep re-scrolling/re-highlighting the same card).
  void _maybeScrollToHighlighted() {
    final targetId = widget.highlightVideoId;
    if (targetId == null || _highlightHandled) return;
    final match = _videos.any((v) => _idOf(v) == targetId);
    if (!match) return;
    _highlightHandled = true;

    // Wait for the frame where the matching card (and its GlobalKey) has
    // actually been built by ListView.builder before trying to scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _cardKeys[targetId];
      final cardContext = key?.currentContext;
      if (cardContext == null || !mounted) return;

      Scrollable.ensureVisible(
        cardContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );

      setState(() => _highlightedId = targetId);
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted && _highlightedId == targetId) {
          setState(() => _highlightedId = null);
        }
      });
    });
  }

  void _goToUpgrade() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen()));
  }

  // ---------------- 3-dot menu ----------------
  Future<void> _showCardMenu(Map<String, dynamic> item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: context.surfaces.border, borderRadius: BorderRadius.circular(999))),
            ListTile(leading: const Icon(Icons.edit_outlined), title: Text(context.tr('myvideos_edit')), onTap: () => Navigator.pop(sheetContext, 'edit')),
            ListTile(leading: const Icon(Icons.share_outlined), title: Text(context.tr('myvideos_share')), onTap: () => Navigator.pop(sheetContext, 'share')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded, color: AppColors.red), title: Text(context.tr('myvideos_delete'), style: const TextStyle(color: AppColors.red)), onTap: () => Navigator.pop(sheetContext, 'delete')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'edit') _openEditSheet(item);
    if (action == 'share') _shareVideo(item);
    if (action == 'delete') _confirmDelete(item);
  }

  void _shareVideo(Map<String, dynamic> item) {
    final videoId = item['ytVideoId'];
    if (videoId == null) {
      showToast(context, context.tr('myvideos_share_unavailable'), isError: true);
      return;
    }
    // Points at the backend's smart-link redirector (routes/share.js) —
    // opens the app via its custom URL scheme if installed, else falls
    // back to the Play Store listing.
    final shareUrl = '${AppConfig.shareBaseUrl}/v/$videoId';
    Share.share('${item['title'] ?? ''}\n$shareUrl');
  }

  // ---------------- Delete (double confirmation, both DB + YouTube) ----------------
  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('myvideos_delete_confirm_title')),
        content: Text(context.tr('myvideos_delete_confirm_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('myvideos_delete'), style: const TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (firstConfirm != true || !mounted) return;

    // Second confirmation — Boss specifically asked for a repeat prompt
    // before an actual (irreversible, cross-platform) delete happens.
    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('myvideos_delete_final_title')),
        content: Text(context.tr('myvideos_delete_final_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('myvideos_delete_final_confirm')),
          ),
        ],
      ),
    );
    if (secondConfirm != true || !mounted) return;

    try {
      if (item['dbId'] != null) {
        // Backend cascades this to YouTube too when a live target exists.
        await ApiService.instance.cancelVideo(item['dbId']);
      } else if (item['ytVideoId'] != null) {
        await ApiService.instance.deleteYoutubeOnlyVideo(item['ytVideoId']);
      }
      if (mounted) {
        showToast(context, context.tr('myvideos_deleted_toast'), isSuccess: true);
        _load();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  // ---------------- Edit bottom sheet ----------------
  void _openEditSheet(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EditVideoSheet(
        item: item,
        aiEligible: _aiEligible,
        onNeedsUpgrade: _goToUpgrade,
        onSaved: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ⚠️ FIX (Boss request — "top me jo likha hai use hata ke likho My
      // Videos"): the header was showing the raw translation key
      // ('myvideos_title') because that key isn't set up in the
      // translation files yet. Hardcoded to "My Videos" so it always
      // reads correctly regardless of translation-file status — swap
      // back to context.tr('myvideos_title') once that key is added.
      appBar: AppBar(title: const Text('My Videos')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.purple,
        child: _loading
            ? const LoadingView()
            : _videos.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 80),
                    EmptyView(message: context.tr('myvideos_empty'), icon: Icons.video_library_outlined),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _videos.length,
                    itemBuilder: (_, i) => _videoCard(_videos[i]),
                  ),
      ),
    );
  }

  // ⚠️ REDESIGNED (Boss request — "square/grid card ko horizontal me
  // karo"): was thumbnail-on-top / title-below / menu-below (a tall
  // square-ish stacked card). Now a horizontal row — a fixed-width
  // thumbnail on the left, title + the 3-dot menu on the right — matching
  // the reference layout.
  Widget _videoCard(Map<String, dynamic> item) {
    final thumb = (item['thumbnail'] ?? '').toString();
    final id = _idOf(item);
    final isHighlighted = id != null && id == _highlightedId;
    final cardKey = id != null ? (_cardKeys[id] ??= GlobalKey()) : null;
    final title = (item['title'] ?? '').toString().isNotEmpty ? item['title'].toString() : context.tr('apply_to_video_untitled');

    return AnimatedContainer(
      key: cardKey,
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(
          color: isHighlighted ? AppColors.purple : context.surfaces.border,
          width: isHighlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: isHighlighted
            ? [BoxShadow(color: AppColors.purple.withOpacity(0.25), blurRadius: 12, spreadRadius: 1)]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openEditSheet(item),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 118,
                height: 74,
                child: thumb.isNotEmpty
                    ? Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2, child: const Icon(Icons.movie_outlined, size: 26)))
                    : Container(color: context.surfaces.card2, child: const Icon(Icons.movie_outlined, size: 26)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => _openEditSheet(item),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ),
          // 3-dot menu — now top-right of the row instead of centered
          // below a square card.
          GestureDetector(
            onTap: () => _showCardMenu(item),
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.more_horiz_rounded, color: context.surfaces.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

/// Half-page bottom sheet: title/description/tags editing + thumbnail
/// change + per-field AI-generate (spark icon), gated behind subscription
/// or diamond balance.
class _EditVideoSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool aiEligible;
  final VoidCallback onNeedsUpgrade;
  final VoidCallback onSaved;
  const _EditVideoSheet({required this.item, required this.aiEligible, required this.onNeedsUpgrade, required this.onSaved});

  @override
  State<_EditVideoSheet> createState() => _EditVideoSheetState();
}

class _EditVideoSheetState extends State<_EditVideoSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _tagsCtrl;
  File? _newThumbnail;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.item['title'] ?? '');
    _descCtrl = TextEditingController(text: widget.item['description'] ?? '');
    final tags = (widget.item['tags'] as List? ?? []).cast<String>();
    _tagsCtrl = TextEditingController(text: tags.join(', '));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickThumbnail() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img != null) setState(() => _newThumbnail = File(img.path));
  }

  // ---------------- AI generate, gated ----------------
  Future<void> _generate(String field) async {
    if (!widget.aiEligible) {
      Navigator.of(context).pop();
      widget.onNeedsUpgrade();
      return;
    }
    final topic = _titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : (widget.item['title'] ?? '').toString();
    if (topic.isEmpty) {
      showToast(context, context.tr('myvideos_ai_needs_topic'), isError: true);
      return;
    }
    try {
      if (field == 'title') {
        final res = await ApiService.instance.aiTitle(topic);
        setState(() => _titleCtrl.text = res['title'] ?? '');
      } else if (field == 'description') {
        final res = await ApiService.instance.aiDescription(topic);
        setState(() => _descCtrl.text = res['description'] ?? '');
      } else {
        final res = await ApiService.instance.aiTags(topic);
        setState(() => _tagsCtrl.text = (res['tags'] as List).join(', '));
      }
      if (mounted) showToast(context, context.tr('up_ai_content_generated'), isSuccess: true);
    } catch (e) {
      if (mounted) showAiError(context, e);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final tagsList = _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

      if (_newThumbnail != null) {
        if (widget.item['ytVideoId'] != null) {
          await ApiService.instance.updateYoutubeThumbnail(widget.item['ytVideoId'], _newThumbnail!.path);
        } else if (widget.item['dbId'] != null) {
          await ApiService.instance.updateDbVideoThumbnail(widget.item['dbId'], _newThumbnail!.path);
        }
      }

      if (widget.item['ytVideoId'] != null) {
        // Already live (or matched to a live YouTube video) — write
        // straight to YouTube, the actual source of truth.
        await ApiService.instance.updateYoutubeVideoMetadata(
          widget.item['ytVideoId'],
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text,
          tags: tagsList,
        );
      } else if (widget.item['dbId'] != null) {
        // Still queued in TubePilot, not live yet.
        await ApiService.instance.updateVideoMetadata(
          widget.item['dbId'],
          platform: 'youtube',
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text,
          tags: _tagsCtrl.text,
        );
      }

      if (mounted) {
        showToast(context, context.tr('myvideos_saved_toast'), isSuccess: true);
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ⚠️ SIMPLIFIED (Boss request — "myvideos_ai_generate jaha jaha hai use
  // hata ke box ke neeche right me karo"): this used to render the field
  // label AND the AI-generate link side-by-side in one row above the
  // TextField. Now it's just the plain label — the AI-generate control
  // moved to its own widget (_aiGenerateRow below), placed AFTER each
  // TextField instead of above it.
  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(text, style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
    );
  }

  // ⚠️ NEW — the AI-generate control itself, now right-aligned directly
  // under its field's box instead of sitting next to the label above it.
  Widget _aiGenerateRow(String field) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: GestureDetector(
          onTap: () => _generate(field),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: widget.aiEligible ? AppColors.purpleLight : context.surfaces.textDim),
              const SizedBox(width: 4),
              Text(context.tr('myvideos_ai_generate'), style: TextStyle(color: widget.aiEligible ? AppColors.purpleLight : context.surfaces.textDim, fontSize: 12, fontWeight: FontWeight.w600)),
              if (!widget.aiEligible) ...[
                const SizedBox(width: 4),
                Icon(Icons.lock_rounded, size: 12, color: context.surfaces.textDim),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentThumb = (widget.item['thumbnail'] ?? '').toString();
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => SafeArea(
        child: SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: context.surfaces.border, borderRadius: BorderRadius.circular(999))),
              ),
              Text(context.tr('myvideos_edit_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),

              // ---------------- Thumbnail ----------------
              GestureDetector(
                onTap: _pickThumbnail,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _newThumbnail != null
                        ? Image.file(_newThumbnail!, fit: BoxFit.cover)
                        : (currentThumb.isNotEmpty
                            ? Image.network(currentThumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2))
                            : Container(color: context.surfaces.card2, child: const Icon(Icons.image_outlined, size: 28))),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(context.tr('myvideos_change_thumbnail'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
              ),

              // ---- Title ----
              _fieldLabel(context.tr('up_title_label')),
              TextField(controller: _titleCtrl, maxLength: 100, decoration: InputDecoration(hintText: context.tr('up_title_hint'))),
              _aiGenerateRow('title'),

              // ---- Description ----
              _fieldLabel(context.tr('up_description_label')),
              TextField(controller: _descCtrl, maxLines: 4, maxLength: 5000, decoration: InputDecoration(hintText: context.tr('up_description_hint'))),
              _aiGenerateRow('description'),

              // ---- Tags ----
              _fieldLabel(context.tr('up_tags_label')),
              TextField(controller: _tagsCtrl, decoration: InputDecoration(hintText: context.tr('up_tags_hint'))),
              _aiGenerateRow('tags'),

              const SizedBox(height: 20),
              GradientButton(label: context.tr('save_btn'), loading: _saving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}