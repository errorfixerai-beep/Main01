import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
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
/// ⚠️ UPDATE (live limits):
///   • Ek time par sirf 1 live — live chalte hue naya video select/upload/start band.
///   • Pichli live ke START se 1 ghanta gap — countdown banner mein dikhta hai.
///   • Rolling 24 ghante mein max 3 live.
///   • Screen dobara kholne par agar live chal rahi hai to live view wapas aa jata hai.
///   • "Purani video se live" button — LiveOldVideosScreen (neeche isi file mein).
/// Asli rules backend enforce karta hai; app sirf buttons disable karke countdown dikhati hai.
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

  LiveLimits _limits = const LiveLimits();
  int _waitSeconds = 0;
  Timer? _ticker;

  bool get _blocked => !_limits.canStart;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
    _refreshLimits();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _titleController.dispose();
    super.dispose();
  }

  // Ek hi 1-second ticker: live ka elapsed time + agle live ka countdown.
  void _onTick(Timer _) {
    if (!mounted) return;
    var changed = false;
    var autoEnded = false;
    var waitDone = false;

    if (_stage == _LiveStage.live) {
      _secondsElapsed++;
      changed = true;
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

  Future<void> _refreshLimits() async {
    try {
      final limits = await fetchLiveLimits();
      if (!mounted) return;
      setState(() {
        _limits = limits;
        _waitSeconds = limits.retryAfterSeconds;
      });
      // Agar server par live chal rahi hai (screen band karke dobara khola) to live view wapas.
      if (limits.activeStream != null && _stage != _LiveStage.live && _stage != _LiveStage.starting) {
        _restoreLive(limits.activeStream!);
      }
    } catch (_) {
      // Offline/temporary error: limits open maan lo — backend har haal mein rok dega.
    }
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
    });
  }

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
    setState(() => _stage = _LiveStage.uploading);

    try {
      final res = await ApiService.instance.uploadLiveVideo(_pickedVideoPath!);
      setState(() {
        _uploadedVideoUrl = res['videoUrl'];
        _stage = _LiveStage.uploaded;
      });
      if (mounted) showToast(context, 'Video upload ho gaya ✅', isSuccess: true);
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
    final pickerDisabled = _blocked || _stage == _LiveStage.uploading;

    return ListView(
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
        const SizedBox(height: 20),

        if (_pickedVideoPath != null && _stage != _LiveStage.uploaded) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_stage == _LiveStage.uploading || _blocked) ? null : _uploadVideo,
              icon: _stage == _LiveStage.uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: Text(_stage == _LiveStage.uploading ? 'Uploading...' : 'Upload Video'),
            ),
          ),
        ],

        if (_stage == _LiveStage.uploaded || _stage == _LiveStage.starting) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Stream Title (optional)',
              hintText: 'e.g. 24/7 Lofi Music',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_stage == _LiveStage.starting || _blocked) ? null : _goLive,
              icon: _stage == _LiveStage.starting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.podcasts_rounded, size: 18),
              label: Text(_stage == _LiveStage.starting ? 'Starting...' : 'Go Live'),
            ),
          ),
        ],

        const SizedBox(height: 24),
        Divider(color: context.surfaces.border),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (_stage == _LiveStage.uploading || _stage == _LiveStage.starting)
                ? null
                : () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveOldVideosScreen()));
                    if (mounted) _refreshLimits();
                  },
            icon: const Icon(Icons.video_library_outlined, size: 18),
            label: const Text('Purani video se live karein'),
          ),
        ),
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
    );
  }
}

// =======================================================================
// ⚠️ NEW: Purani video se live — My Videos wali library (TubePilot ke apne
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
                  if (_limits.activeStream != null) ...[
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