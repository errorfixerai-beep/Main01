import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'milestone_card.dart';

class MilestonePopup {
  static bool _busy = false;

  /// Call from the home page (DashboardScreen.initState, after first frame).
  /// Shows the pending milestone card, if any. Safe to call many times.
  /// Returns true if a milestone card was actually shown.
  static Future<bool> checkAndShow(BuildContext context) async {
    if (_busy) return false;
    _busy = true;
    try {
      final res = await ApiService.instance.getPendingMilestone();
      final m = res['milestone'];
      if (m == null || !context.mounted) return false;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MilestoneDialog(data: Map<String, dynamic>.from(m)),
      );
      return true;
    } catch (_) {
      // Popup is a bonus feature — never break the home page because of it.
      return false;
    } finally {
      _busy = false;
    }
  }
}

class _MilestoneDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  const _MilestoneDialog({required this.data});
  @override
  State<_MilestoneDialog> createState() => _MilestoneDialogState();
}

class _MilestoneDialogState extends State<_MilestoneDialog> {
  final _cardKey = GlobalKey();
  bool _working = false;

  @override
  void initState() {
    super.initState();
    // Mark as seen the moment it is shown, so the same milestone never pops up twice.
    ApiService.instance.markMilestoneSeen('${widget.data['id']}').catchError((_) => <String, dynamic>{});
  }

  Future<Uint8List> _capturePng() async {
    final boundary = _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  Future<void> _download() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final png = await _capturePng();
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(png, album: 'TubePilot', name: 'tubepilot_milestone_${widget.data['value']}');
      if (mounted) showToast(context, 'Saved to your gallery', isSuccess: true);
    } catch (e) {
      if (mounted) showToast(context, 'Could not save image', isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _share() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final png = await _capturePng();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tubepilot_milestone_${widget.data['value']}.png');
      await file.writeAsBytes(png);
      await Share.shareXFiles([XFile(file.path)], text: 'Milestone unlocked with TubePilot 🚀');
    } catch (e) {
      if (mounted) showToast(context, 'Could not share image', isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          RepaintBoundary(
            key: _cardKey,
            child: MilestoneCard(
              type: '${d['type']}',
              value: (d['value'] as num).toInt(),
              channelTitle: '${d['channelTitle'] ?? ''}',
              videoTitle: d['videoTitle'] as String?,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _working ? null : _download,
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.diamond, foregroundColor: Colors.black),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _working ? null : _share,
                  icon: const Icon(Icons.share_rounded, size: 20),
                  label: const Text('Share'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.purpleLight),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}