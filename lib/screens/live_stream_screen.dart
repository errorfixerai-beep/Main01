import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'live_plans_screen.dart';

/// Live Streaming ka main screen — video select karna, upload karna
/// (ImageKit ke through backend), aur "Go Live" dabana. Ek baar live ho
/// jaye to yahi screen status/timer/stop dikhati hai.
///
/// ⚠️ NOTE: video pick karne ke liye "image_picker" package use kiya hai
/// (ImagePicker().pickVideo). Agar aapki app mein video-upload screen
/// pehle se koi doosra package use karta hai (jaise file_picker), usi ko
/// consistency ke liye yahan bhi use kar lena — logic same rahega.
class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({super.key});
  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

enum _LiveStage { idle, uploading, uploaded, starting, live }

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _titleController = TextEditingController();

  _LiveStage _stage = _LiveStage.idle;
  String? _pickedVideoPath;
  String? _uploadedVideoUrl;
  String? _streamId;
  String? _watchUrl;
  bool _isFreeTrial = false;
  int _secondsAllowed = 0;
  int _secondsElapsed = 0;
  Timer? _tickTimer;

  @override
  void dispose() {
    _tickTimer?.cancel();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    setState(() {
      _pickedVideoPath = video.path;
      _uploadedVideoUrl = null;
      _stage = _LiveStage.idle;
    });
  }

  Future<void> _uploadVideo() async {
    if (_pickedVideoPath == null) return;
    setState(() => _stage = _LiveStage.uploading);

    try {
      final res = await ApiService.instance.uploadLiveVideo(_pickedVideoPath!);
      setState(() {
        _uploadedVideoUrl = res['videoUrl'];
        _stage = _LiveStage.uploaded;
      });
      if (mounted) showToast(context, 'Video upload ho gaya ✅', isSuccess: true);
    } catch (e) {
      setState(() => _stage = _LiveStage.idle);
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _goLive() async {
    if (_uploadedVideoUrl == null) return;
    setState(() => _stage = _LiveStage.starting);

    try {
      final res = await ApiService.instance.startLiveStream(
        videoUrl: _uploadedVideoUrl!,
        title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
      );

      setState(() {
        _streamId = res['streamId'];
        _watchUrl = res['watchUrl'];
        _isFreeTrial = res['isFreeTrial'] ?? false;
        _secondsAllowed = res['secondsAllowed'] ?? 0;
        _secondsElapsed = 0;
        _stage = _LiveStage.live;
      });

      _tickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _secondsElapsed++);
        if (_secondsElapsed >= _secondsAllowed) {
          timer.cancel();
          _handleAutoEnded();
        }
      });

      if (mounted) {
        showToast(context, _isFreeTrial ? 'Free trial live shuru! (5 minute)' : 'Live stream shuru ho gaya! 🎉', isSuccess: true);
      }
    } catch (e) {
      setState(() => _stage = _LiveStage.uploaded);
      if (mounted) showApiError(context, e);
    }
  }

  void _handleAutoEnded() {
    if (!mounted) return;
    showToast(context, 'Aapka allotted time khatam ho gaya — stream automatically band ho gaya.', isError: false);
    _resetToIdle();
  }

  Future<void> _stopLive() async {
    if (_streamId == null) return;
    try {
      await ApiService.instance.stopLiveStream(_streamId!);
      if (mounted) showToast(context, 'Stream band ho gaya.', isSuccess: true);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      _tickTimer?.cancel();
      _resetToIdle();
    }
  }

  void _resetToIdle() {
    if (!mounted) return;
    setState(() {
      _stage = _LiveStage.idle;
      _pickedVideoPath = null;
      _uploadedVideoUrl = null;
      _streamId = null;
      _watchUrl = null;
      _secondsElapsed = 0;
      _secondsAllowed = 0;
      _titleController.clear();
    });
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Stream'),
        actions: [
          IconButton(
            icon: const Icon(Icons.workspace_premium_rounded),
            tooltip: 'Plans',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LivePlansScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _stage == _LiveStage.live ? _buildLiveView() : _buildSetupView(),
        ),
      ),
    );
  }

  Widget _buildSetupView() {
    return ListView(
      children: [
        Text('Video Select Karein', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Ye video 24/7 loop hoke YouTube par live chalegi. Max size: 2GB.',
          style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5),
        ),
        const SizedBox(height: 16),

        // Video picker box
        InkWell(
          onTap: _stage == _LiveStage.uploading ? null : _pickVideo,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            height: 140,
            decoration: BoxDecoration(
              color: context.surfaces.card2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.surfaces.border),
            ),
            child: _pickedVideoPath == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.video_call_rounded, size: 36, color: context.surfaces.textDim),
                        const SizedBox(height: 8),
                        Text('Tap to select video', style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                      ],
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 36, color: AppColors.green),
                        const SizedBox(height: 8),
                        Text(
                          _pickedVideoPath!.split('/').last,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),

        if (_pickedVideoPath != null && _stage != _LiveStage.uploaded) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _stage == _LiveStage.uploading ? null : _uploadVideo,
              icon: _stage == _LiveStage.uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: Text(_stage == _LiveStage.uploading ? 'Uploading...' : 'Upload Video'),
            ),
          ),
        ],

        if (_stage == _LiveStage.uploaded) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Stream Title (optional)',
              hintText: 'e.g. 24/7 Lofi Music',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _stage == _LiveStage.starting ? null : _goLive,
              icon: _stage == _LiveStage.starting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.podcasts_rounded, size: 18),
              label: Text(_stage == _LiveStage.starting ? 'Starting...' : 'Go Live'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLiveView() {
    final remaining = (_secondsAllowed - _secondsElapsed).clamp(0, _secondsAllowed);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                ],
              ),
              const SizedBox(height: 16),
              Text(_formatDuration(_secondsElapsed), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                '${_formatDuration(remaining)} remaining${_isFreeTrial ? ' (Free Trial)' : ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_watchUrl != null)
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(_watchUrl!), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Watch on YouTube'),
          ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: _stopLive,
            icon: const Icon(Icons.stop_circle_rounded, size: 18),
            label: const Text('Stop Live Stream'),
          ),
        ),
      ],
    );
  }
}