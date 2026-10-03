import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'live_camera_screen.dart';
import 'live_plans_screen.dart';

/// Backend se live limits poochta hai (stream start NAHI hoti).
/// ApiService.startLiveStream ko special videoUrl dene par backend sirf
/// { canStart, code, retryAfterSeconds, activeStream, ... } wapas deta hai.
Future<LiveLimits> fetchLiveLimits() async {
  final res = await ApiService.instance.startLiveStream(videoUrl: LiveLimits.checkToken, title: null);
  return LiveLimits.fromJson(Map<String, dynamic>.from(res as Map));
}

/// Live Streaming ka main screen — video select karna, upload karna
/// (ImageKit ke through backend), aur "Go Live" dabana. Ek baar live ho
/// jaye to yahi screen status/timer/stop dikhati hai.
///
/// ⚠️ UPDATE (is version mein):
///   • Upload ke dauraan progress bar (percentage + MB), 100% ke baad "Processing...".
///   • Upload Video / Go Live buttons screen ke BOTTOM mein fixed.
///   • Live chalte waqt app ke andar YouTube ka live preview (jo viewers dekh rahe hain wahi).
///     YouTube stream pakadne mein 20-30 sec lagte hain, isliye preview 25 sec baad shuru hota hai.
///   • "Camera se live karein" — LiveCameraScreen (live_camera_screen.dart).
///   • Live limits: ek time par 1, 1 ghanta gap, 24 ghante mein max 3 (backend enforce karta hai).
///
/// ⚠️ NOTE: video pick karne ke liye "image_picker" package use kiya hai
/// (ImagePicker().pickVideo).
class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({super.key});
  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

enum _LiveStage { idle, uploading, uploaded, starting, live }

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  static const int _previewDelaySeconds = 25;

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

  // Upload progress
  double _uploadProgress = 0;
  int _uploadSent = 0;
  int _uploadTotal = 0;

  // In-app YouTube preview
  YoutubePlayerController? _ytController;

  LiveLimits _limits = const LiveLimits();
  int _waitSeconds = 0;
  Timer? _ticker;

  bool get _blocked => !_limits.canStart;

  String? get _videoId {
    final url = _watchUrl;
    if (url == null) return null;
    return Uri.tryParse(url)?.queryParameters['v'];
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
    _refreshLimits();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ytController?.close();
    _titleController.dispose();
    super.dispose();
  }

  // ---------------- ticker ----------------
  // Ek hi 1-second ticker: live ka elapsed time + agle live ka countdown + preview shuru karna.
  void _onTick(Timer _) {
    if (!mounted) return;
    var changed = false;
    var autoEnded = false;
    var waitDone = false;

    if (_stage == _LiveStage.live) {
      _secondsElapsed++;
      changed = true;
      _maybeStartPreview();
      if (_secondsElapsed >= _secondsAllowed) autoEnded = true;
    }
    if (_waitSeconds > 0) {
      _waitSeconds--;
      changed = true;
      if (_waitSeconds == 0 && _stage != _LiveStage.live) waitDone = true;
    }

    if (changed) setState(() {});
    if (autoEnded) _handleAutoEnded();
    if (waitDone) _refreshLimits();
  }

  // ---------------- live preview ----------------
  YoutubePlayerController _createPreviewController(String videoId) {
    return YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(mute: true, showFullscreenButton: true),
    );
  }

  void _maybeStartPreview() {
    if (_ytController != null) return;
    final id = _videoId;
    if (id == null || _secondsElapsed < _previewDelaySeconds) return;
    _ytController = _createPreviewController(id);
  }

  void _reloadPreview() {
    final id = _videoId;
    if (id == null) return;
    _ytController?.close();
    setState(() => _ytController = _createPreviewController(id));
  }

  void _disposePreview() {
    _ytController?.close();
    _ytController = null;
  }

  // ---------------- limits / restore ----------------
  Future<void> _refreshLimits() async {
    try {
      final limits = await fetchLiveLimits();
      if (!mounted) return;
      setState(() {
        _limits = limits;
        _waitSeconds = limits.retryAfterSeconds;
      });

      // Server par live chal rahi hai (screen band karke dobara khola) to live view wapas.
      final active = limits.activeStream;
      if (active != null && _stage != _LiveStage.live && _stage != _LiveStage.starting) {
        if (active['source'] == 'camera') {
          // Camera live sirf camera screen se chal sakti hai. Agar wo screen abhi live nahi hai
          // to ye adhoori session hai (app band hui thi) — band kar do.
          if (!LiveCameraScreen.active) _closeStaleCameraSession(active['streamId']?.toString());
        } else {
          _restoreLive(active);
        }
      }
    } catch (_) {
      // Offline/temporary error: limits open maan lo — backend har haal mein rok dega.
    }
  }

  Future<void> _closeStaleCameraSession(String? streamId) async {
    if (streamId == null) return;
    try {
      await ApiService.instance.stopLiveStream(streamId);
      if (mounted) showToast(context, 'Pichli camera live adhoori thi, band kar di.');
    } catch (_) {
      return; // band nahi ho payi to loop mat banao
    }
    if (mounted) _refreshLimits();
  }

  void _restoreLive(Map<String, dynamic> a) {
    final allowed = (a['secondsAllowed'] as num?)?.toInt() ?? 0;
    final remaining = (a['secondsRemaining'] as num?)?.toInt() ?? 0;
    setState(() {
      _streamId = a['streamId']?.toString();
      _watchUrl = a['watchUrl']?.toString();
      _isFreeTrial = a['isFreeTrial'] == true;
      _secondsAllowed = allowed;
      _secondsElapsed = (allowed - remaining).clamp(0, allowed);
      _stage = _LiveStage.live;
      _maybeStartPreview();
    });
  }

  // ---------------- pick / upload / go live ----------------
  Future<void> _pickVideo() async {
    if (_blocked) return;
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    setState(() {
      _pickedVideoPath = video.path;
      _uploadedVideoUrl = null;
      _stage = _LiveStage.idle;
    });
  }

  Future<void> _uploadVideo() async {
    if (_pickedVideoPath == null || _blocked) return;
    setState(() {
      _stage = _LiveStage.uploading;
      _uploadProgress = 0;
      _uploadSent = 0;
      _uploadTotal = 0;
    });

    try {
      final res = await ApiService.instance.uploadLiveVideo(
        _pickedVideoPath!,
        onProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          final double p = (sent / total).clamp(0.0, 1.0).toDouble();
          // Har chhote chunk par rebuild nahi — 1% badalne par hi.
          if (p - _uploadProgress >= 0.01 || p >= 1) {
            setState(() {
              _uploadProgress = p;
              _uploadSent = sent;
              _uploadTotal = total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _uploadedVideoUrl = res['videoUrl'];
        _stage = _LiveStage.uploaded;
      });
      showToast(context, 'Video upload ho gaya ✅', isSuccess: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = _LiveStage.idle);
      showApiError(context, e);
      _refreshLimits(); // limit ki wajah se fail hua ho to banner/countdown turant aa jaye
    }
  }

  Future<void> _goLive() async {
    if (_uploadedVideoUrl == null || _blocked) return;
    setState(() => _stage = _LiveStage.starting);

    try {
      final res = await ApiService.instance.startLiveStream(
        videoUrl: _uploadedVideoUrl!,
        title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
      );

      if (!mounted) return;
      _disposePreview();
      setState(() {
        _streamId = res['streamId'];
        _watchUrl = res['watchUrl'];
        _isFreeTrial = res['isFreeTrial'] ?? false;
        _secondsAllowed = res['secondsAllowed'] ?? 0;
        _secondsElapsed = 0;
        _stage = _LiveStage.live;
      });

      showToast(context, _isFreeTrial ? 'Free trial live shuru! (5 minute)' : 'Live stream shuru ho gaya! 🎉', isSuccess: true);
      _refreshLimits(); // agle live ka 1-ghante wala countdown
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = _LiveStage.uploaded);
      showApiError(context, e);
      _refreshLimits();
    }
  }

  void _handleAutoEnded() {
    if (!mounted) return;
    showToast(context, 'Aapka allotted time khatam ho gaya — stream automatically band ho gaya.', isError: false);
    _resetToIdle();
    _refreshLimits();
  }

  Future<void> _stopLive() async {
    if (_streamId == null) return;
    try {
      await ApiService.instance.stopLiveStream(_streamId!);
      if (mounted) showToast(context, 'Stream band ho gaya.', isSuccess: true);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      _resetToIdle();
      _refreshLimits();
    }
  }

  void _resetToIdle() {
    if (!mounted) return;
    _disposePreview();
    setState(() {
      _stage = _LiveStage.idle;
      _pickedVideoPath = null;
      _uploadedVideoUrl = null;
      _streamId = null;
      _watchUrl = null;
      _secondsElapsed = 0;
      _secondsAllowed = 0;
      _uploadProgress = 0;
      _uploadSent = 0;
      _uploadTotal = 0;
      _titleController.clear();
    });
  }

  // ---------------- formatting ----------------
  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  // ---------------- build ----------------
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
        child: _stage == _LiveStage.live ? _buildLiveView() : _buildSetupView(),
      ),
    );
  }

  // ---------------- setup view (buttons bottom mein) ----------------
  Widget _buildSetupView() {
    final busy = _stage == _LiveStage.uploading || _stage == _LiveStage.starting;
    final pickerDisabled = _blocked || busy;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              LiveLimitBanner(limits: _limits, waitSeconds: _waitSeconds),
              const SizedBox(height: 18),

              Text('Video Select Karein', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Ye video 24/7 loop hoke YouTube par live chalegi. Max size: 2GB.',
                style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5),
              ),
              const SizedBox(height: 16),

              // Video picker box
              Opacity(
                opacity: _blocked ? 0.5 : 1,
                child: InkWell(
                  onTap: pickerDisabled ? null : _pickVideo,
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
                                Text(
                                  _blocked ? 'Abhi naya live shuru nahi ho sakta' : 'Tap to select video',
                                  style: TextStyle(color: context.surfaces.textDim, fontSize: 13),
                                ),
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
              ),

              // Upload progress bar
              if (_stage == _LiveStage.uploading) ...[
                const SizedBox(height: 16),
                _buildUploadProgress(),
              ],

              // Title (upload ke baad)
              if (_stage == _LiveStage.uploaded || _stage == _LiveStage.starting) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Stream Title (optional)',
                    hintText: 'e.g. 24/7 Lofi Music',
                  ),
                ),
              ],

              // Doosre tareeke
              const SizedBox(height: 20),
              Divider(color: context.surfaces.border),
              const SizedBox(height: 12),
              Text('Ya doosre tareeke se live karein', style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveOldVideosScreen()));
                          if (mounted) _refreshLimits();
                        },
                  icon: const Icon(Icons.video_library_outlined, size: 18),
                  label: const Text('Purani video se live karein'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveCameraScreen()));
                          if (mounted) _refreshLimits();
                        },
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: const Text('Camera se live karein'),
                ),
              ),
            ],
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildUploadProgress() {
    final processing = _uploadProgress >= 1;
    final pct = (_uploadProgress * 100).clamp(0, 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaces.card2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.surfaces.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  processing ? 'Server par process ho raha hai...' : 'Uploading...',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
              if (!processing)
                Text('$pct%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.purple)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: processing ? null : _uploadProgress,
              minHeight: 8,
              color: AppColors.purple,
              backgroundColor: context.surfaces.border,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            processing
                ? 'Video storage par save ho rahi hai — thoda ruko.'
                : '${_fmtBytes(_uploadSent)} / ${_fmtBytes(_uploadTotal)}  •  Screen band mat karein',
            style: TextStyle(color: context.surfaces.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Upload Video / Go Live — hamesha screen ke bottom mein.
  Widget _buildBottomBar() {
    Widget? button;

    if (_pickedVideoPath != null && _stage != _LiveStage.uploaded && _stage != _LiveStage.starting) {
      final uploading = _stage == _LiveStage.uploading;
      final processing = uploading && _uploadProgress >= 1;
      final pct = (_uploadProgress * 100).clamp(0, 100).toStringAsFixed(0);
      button = ElevatedButton.icon(
        onPressed: (uploading || _blocked) ? null : _uploadVideo,
        icon: uploading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.cloud_upload_rounded, size: 18),
        label: Text(uploading ? (processing ? 'Processing...' : 'Uploading $pct%') : 'Upload Video'),
      );
    } else if (_stage == _LiveStage.uploaded || _stage == _LiveStage.starting) {
      final starting = _stage == _LiveStage.starting;
      button = ElevatedButton.icon(
        onPressed: (starting || _blocked) ? null : _goLive,
        icon: starting
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.podcasts_rounded, size: 18),
        label: Text(starting ? 'Starting...' : 'Go Live'),
      );
    }

    if (button == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: context.surfaces.border)),
      ),
      child: SizedBox(width: double.infinity, child: button),
    );
  }

  // ---------------- live view (preview + stop bottom mein) ----------------
  Widget _buildPreviewBox() {
    final controller = _ytController;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: controller != null
            ? YoutubePlayer(controller: controller, aspectRatio: 16 / 9)
            : Container(
                color: Colors.black,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
                    SizedBox(height: 12),
                    Text(
                      'Preview YouTube se connect ho raha hai...\n(20-30 second lagte hain)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLiveView() {
    final remaining = (_secondsAllowed - _secondsElapsed).clamp(0, _secondsAllowed);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
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
                    const SizedBox(height: 12),
                    Text(_formatDuration(_secondsElapsed), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDuration(remaining)} remaining${_isFreeTrial ? ' (Free Trial)' : ''}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_watchUrl != null)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(_watchUrl!), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Watch on YouTube'),
                ),
              const SizedBox(height: 14),
              Text('Live Preview', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _buildPreviewBox(),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Jo viewers YouTube par dekh rahe hain wahi yahan dikhta hai (15-30 sec delay). Preview mute shuru hota hai.',
                      style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _videoId == null ? null : _reloadPreview,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reload'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: context.surfaces.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_waitSeconds > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Agla live ${formatCountdown(_waitSeconds)} baad ho sakta hai',
                    style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5),
                  ),
                ),
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
          ),
        ),
      ],
    );
  }
}

// =======================================================================
// ⚠️ Purani video se live — My Videos wali library (TubePilot ke apne
// records + YouTube channel ki videos) mein se koi bhi video live karo.
// Wahi limits lagti hain (1 at a time, 1 ghanta gap, 24 ghante mein max 3).
// `initialItem` diya ho (My Videos ke menu se "Live karein") to us video ka
// Go Live sheet seedha khul jata hai.
// =======================================================================
class LiveOldVideosScreen extends StatefulWidget {
  final Map<String, dynamic>? initialItem;
  const LiveOldVideosScreen({super.key, this.initialItem});
  @override
  State<LiveOldVideosScreen> createState() => _LiveOldVideosScreenState();
}

class _LiveOldVideosScreenState extends State<LiveOldVideosScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _videos = [];
  LiveLimits _limits = const LiveLimits();
  int _waitSeconds = 0;
  String? _startingRef;
  bool _initialHandled = false;
  Timer? _ticker;

  bool get _blocked => !_limits.canStart;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _waitSeconds <= 0) return;
      setState(() => _waitSeconds--);
      if (_waitSeconds == 0) _refreshLimits();
    });
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String? _refOf(Map<String, dynamic> item) {
    final db = item['dbId'];
    final yt = item['ytVideoId'];
    if (db != null) return 'library://db/$db';
    if (yt != null) return 'library://yt/$yt';
    return null;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        ApiService.instance.getVideoLibrary(),
        fetchLiveLimits().catchError((_) => const LiveLimits()),
      ]);
      final lib = results[0] as Map;
      final limits = results[1] as LiveLimits;
      if (!mounted) return;
      setState(() {
        _videos = (lib['videos'] as List? ?? []).cast<Map<String, dynamic>>();
        _limits = limits;
        _waitSeconds = limits.retryAfterSeconds;
      });
      _maybeOpenInitial();
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshLimits() async {
    try {
      final limits = await fetchLiveLimits();
      if (!mounted) return;
      setState(() {
        _limits = limits;
        _waitSeconds = limits.retryAfterSeconds;
      });
    } catch (_) {}
  }

  void _maybeOpenInitial() {
    final item = widget.initialItem;
    if (item == null || _initialHandled) return;
    _initialHandled = true;
    if (_blocked) return; // banner mein countdown dikh raha hai
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openStartSheet(item);
    });
  }

  Future<void> _openStartSheet(Map<String, dynamic> item) async {
    if (_blocked) {
      showToast(context, 'Abhi live shuru nahi ho sakta. Upar countdown dekhein.', isError: true);
      return;
    }
    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _StartLiveSheet(
        initialTitle: (item['title'] ?? '').toString(),
        thumbnail: (item['thumbnail'] ?? '').toString(),
      ),
    );
    if (title == null || !mounted) return; // cancel
    _start(item, title);
  }

  Future<void> _start(Map<String, dynamic> item, String title) async {
    final ref = _refOf(item);
    if (ref == null) {
      showToast(context, 'Is video ko live nahi kar sakte.', isError: true);
      return;
    }
    setState(() => _startingRef = ref);
    try {
      await ApiService.instance.startLiveStream(videoUrl: ref, title: title.isEmpty ? null : title);
      if (!mounted) return;
      showToast(context, 'Live stream shuru ho gaya! 🎉', isSuccess: true);
      // Live screen server se active stream dekhkar live view khud dikha degi.
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LiveStreamScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() => _startingRef = null);
      showApiError(context, e);
      _refreshLimits();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purani Video Live')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.purple,
        child: _loading
            ? const LoadingView()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  LiveLimitBanner(limits: _limits, waitSeconds: _waitSeconds),
                  const SizedBox(height: 14),
                  if (_limits.activeStream != null && _limits.activeStream!['source'] != 'camera') ...[
                    _liveNowCard(),
                    const SizedBox(height: 14),
                  ],
                  if (_videos.isEmpty)
                    const EmptyView(message: 'Abhi koi purani video nahi hai.', icon: Icons.video_library_outlined)
                  else
                    ..._videos.map(_videoCard),
                ],
              ),
      ),
    );
  }

  Widget _liveNowCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.gradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.podcasts_rounded, color: Colors.white),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Aapki live chal rahi hai', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LiveStreamScreen())),
            child: const Text('Kholein'),
          ),
        ],
      ),
    );
  }

  Widget _videoCard(Map<String, dynamic> item) {
    final thumb = (item['thumbnail'] ?? '').toString();
    final title = (item['title'] ?? '').toString().isNotEmpty ? item['title'].toString() : 'Untitled video';
    final ref = _refOf(item);
    final isStarting = ref != null && ref == _startingRef;
    final canTap = ref != null && !_blocked && _startingRef == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 118,
              height: 74,
              child: thumb.isNotEmpty
                  ? Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2, child: const Icon(Icons.movie_outlined, size: 26)),
                    )
                  : Container(color: context.surfaces.card2, child: const Icon(Icons.movie_outlined, size: 26)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: canTap ? () => _openStartSheet(item) : null,
                    icon: isStarting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.podcasts_rounded, size: 16),
                    label: Text(isStarting ? 'Starting...' : 'Go Live', style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Go Live confirm sheet — title edit karke "Go Live". Controller isi widget
/// ka hai taaki sheet band hote waqt dispose ki dikkat na aaye.
class _StartLiveSheet extends StatefulWidget {
  final String initialTitle;
  final String thumbnail;
  const _StartLiveSheet({required this.initialTitle, required this.thumbnail});

  @override
  State<_StartLiveSheet> createState() => _StartLiveSheetState();
}

class _StartLiveSheetState extends State<_StartLiveSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTitle;
    _ctrl = TextEditingController(text: t.length > 100 ? t.substring(0, 100) : t);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: context.surfaces.border, borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const Text('Live shuru karein', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: widget.thumbnail.isNotEmpty
                    ? Image.network(
                        widget.thumbnail,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2, child: const Icon(Icons.movie_outlined, size: 28)),
                      )
                    : Container(color: context.surfaces.card2, child: const Icon(Icons.movie_outlined, size: 28)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Stream Title (optional)'),
            ),
            Text(
              'Ye video 24/7 loop hoke YouTube par live chalegi.',
              style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: 'Go Live',
              icon: Icons.podcasts_rounded,
              onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
            ),
          ],
        ),
      ),
    );
  }
}