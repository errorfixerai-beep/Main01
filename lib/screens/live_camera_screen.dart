import 'dart:async';
import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// ⚠️ NEW: Phone ke camera se seedha YouTube par live.
///
/// Flow: backend (POST /live-stream/start-camera) YouTube par broadcast + stream key banata hai
/// (limits + plan hours check karke) -> app camera/mic ko RTMP se seedha YouTube ko bhejti hai.
/// EC2 beech mein NAHI aata. Wahi rules lagte hain: 1 at a time, 1 ghanta gap,
/// 24 ghante mein max 3, aur plan ke hours kat-te hain.
///
/// Dhyan: live ke dauraan app khuli rehni chahiye (background mein camera Android band kar deta hai).
class LiveCameraScreen extends StatefulWidget {
  /// Camera live chal rahi ho to true — LiveStreamScreen is flag se pehchanta hai ki
  /// server par dikhne wali camera session "adhoori" (app band hui thi) hai ya abhi chal rahi hai.
  static bool active = false;

  const LiveCameraScreen({super.key});
  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

enum _CamStage { loading, error, ready, starting, live }

class _LiveCameraScreenState extends State<LiveCameraScreen> with WidgetsBindingObserver {
  ApiVideoLiveStreamController? _controller;
  final TextEditingController _titleCtrl = TextEditingController();

  _CamStage _stage = _CamStage.loading;
  String _errorText = '';
  bool _permanentlyDenied = false;

  LiveLimits _limits = const LiveLimits();
  int _waitSeconds = 0;
  Timer? _ticker;

  String? _streamId;
  String? _watchUrl;
  bool _isFreeTrial = false;
  int _secondsAllowed = 0;
  int _secondsElapsed = 0;
  bool _muted = false;
  bool _connected = false;
  bool _stopping = false;

  bool get _blocked => !_limits.canStart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
    _initCamera();
    _refreshLimits();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _titleCtrl.dispose();

    // App kill/screen destroy hone par bhi server session chhodna nahi hai.
    final id = _streamId;
    if (id != null && !_stopping) {
      ApiService.instance.stopLiveStream(id).catchError((_) => <String, dynamic>{});
    }
    LiveCameraScreen.active = false;
    WakelockPlus.disable();
    _controller?.stop();
    _controller?.dispose();
    super.dispose();
  }

  // ---------------- lifecycle ----------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    if (state == AppLifecycleState.paused) {
      if (_stage == _CamStage.live || _stage == _CamStage.starting) {
        // Android background mein camera chalne nahi deta — saaf tareeke se live band karo.
        _endSession(message: 'App background mein gayi, isliye camera live band ho gayi.', isError: true);
      } else {
        c.stopPreview();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_stage == _CamStage.ready) c.startPreview();
    }
  }

  // ---------------- timers / limits ----------------
  void _onTick(Timer _) {
    if (!mounted) return;
    var changed = false;
    var autoEnded = false;
    var waitDone = false;

    if (_stage == _CamStage.live) {
      _secondsElapsed++;
      changed = true;
      if (_secondsAllowed > 0 && _secondsElapsed >= _secondsAllowed) autoEnded = true;
    }
    if (_waitSeconds > 0) {
      _waitSeconds--;
      changed = true;
      if (_waitSeconds == 0 && _stage != _CamStage.live) waitDone = true;
    }

    if (changed) setState(() {});
    if (autoEnded) _endSession(message: 'Aapka allotted time khatam ho gaya — live band ho gayi.');
    if (waitDone) _refreshLimits();
  }

  Future<void> _refreshLimits() async {
    try {
      final res = await ApiService.instance.startLiveStream(videoUrl: LiveLimits.checkToken, title: null);
      final limits = LiveLimits.fromJson(Map<String, dynamic>.from(res as Map));
      if (!mounted) return;
      setState(() {
        _limits = limits;
        _waitSeconds = limits.retryAfterSeconds;
      });
    } catch (_) {
      // Offline/temporary error: backend har haal mein rok dega.
    }
  }

  // ---------------- camera init ----------------
  Future<void> _initCamera() async {
    setState(() {
      _stage = _CamStage.loading;
      _errorText = '';
      _permanentlyDenied = false;
    });

    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      if (!mounted) return;
      setState(() {
        _permanentlyDenied = cam.isPermanentlyDenied || mic.isPermanentlyDenied;
        _errorText = 'Camera aur Microphone ki permission chahiye.';
        _stage = _CamStage.error;
      });
      return;
    }

    try {
      final controller = ApiVideoLiveStreamController(
        initialAudioConfig: AudioConfig(),
        initialVideoConfig: VideoConfig.withDefaultBitrate(),
        onConnectionSuccess: () {
          if (mounted) setState(() => _connected = true);
        },
        onConnectionFailed: (String error) => _handleConnectionProblem('YouTube se connect nahi ho paya: $error'),
        onDisconnection: () => _handleConnectionProblem('Live connection toot gaya.'),
        onError: (Exception e) => _handleConnectionProblem('Camera error: $e'),
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _stage = _CamStage.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Camera start nahi ho paya: $e';
        _stage = _CamStage.error;
      });
    }
  }

  // ---------------- go live / stop ----------------
  Future<void> _goLive() async {
    final controller = _controller;
    if (controller == null || _blocked || _stage != _CamStage.ready) return;
    setState(() {
      _stage = _CamStage.starting;
      _connected = false;
    });

    String? createdStreamId;
    try {
      final title = _titleCtrl.text.trim();
      final res = await ApiService.instance.startCameraLive(title: title.isEmpty ? null : title);

      createdStreamId = res['streamId']?.toString();
      final rtmpUrl = res['rtmpUrl']?.toString();
      final streamKey = res['streamKey']?.toString();
      if (createdStreamId == null || rtmpUrl == null || streamKey == null) {
        throw ApiException('Server se camera live ki details nahi mili.');
      }

      // ⚠️ url bina trailing "/" ke — package khud url/streamKey jodta hai.
      await controller.startStreaming(streamKey: streamKey, url: rtmpUrl);

      if (!mounted) return;
      LiveCameraScreen.active = true;
      WakelockPlus.enable(); // live ke dauraan screen band na ho
      setState(() {
        _streamId = createdStreamId;
        _watchUrl = res['watchUrl']?.toString();
        _isFreeTrial = res['isFreeTrial'] == true;
        _secondsAllowed = (res['secondsAllowed'] as num?)?.toInt() ?? 0;
        _secondsElapsed = 0;
        _stage = _CamStage.live;
      });
      showToast(context, _isFreeTrial ? 'Free trial camera live shuru! (5 minute)' : 'Camera live shuru ho gayi! 🎉', isSuccess: true);
      _refreshLimits();
    } catch (e) {
      // Server par session ban chuka ho to release karo (slot wapas mil sakta hai).
      if (createdStreamId != null) {
        try {
          await controller.stopStreaming();
        } catch (_) {}
        try {
          await ApiService.instance.stopLiveStream(createdStreamId);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _stage = _CamStage.ready);
      showApiError(context, e);
      _refreshLimits();
    }
  }

  void _handleConnectionProblem(String message) {
    if (!mounted || _stopping) return;
    if (_stage == _CamStage.live || _stage == _CamStage.starting) {
      _endSession(message: message, isError: true);
    }
  }

  Future<void> _endSession({String? message, bool isError = false}) async {
    if (_stopping) return;
    _stopping = true;
    final id = _streamId;

    try {
      await _controller?.stopStreaming();
    } catch (_) {}
    if (id != null) {
      try {
        await ApiService.instance.stopLiveStream(id);
      } catch (_) {}
    }
    LiveCameraScreen.active = false;
    WakelockPlus.disable();

    if (!mounted) return;
    setState(() {
      _stage = _CamStage.ready;
      _streamId = null;
      _watchUrl = null;
      _secondsElapsed = 0;
      _secondsAllowed = 0;
      _connected = false;
      _stopping = false;
    });
    if (message != null) showToast(context, message, isError: isError, isSuccess: !isError);
    _refreshLimits();
  }

  Future<bool> _confirmStop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Live band karein?'),
        content: const Text('Camera live abhi chal rahi hai. Bahar jaane par live band ho jayegi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nahi')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Live band karo', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _switchCamera() async {
    try {
      await _controller?.switchCamera();
    } catch (e) {
      if (mounted) showToast(context, 'Camera badal nahi paya.', isError: true);
    }
  }

  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.toggleMute();
      final muted = await c.isMuted;
      if (mounted) setState(() => _muted = muted);
    } catch (_) {}
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final busy = _stage == _CamStage.live || _stage == _CamStage.starting;

    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_stage == _CamStage.starting) return; // start ke beech mein bahar nahi
        final stop = await _confirmStop();
        if (!stop) return;
        await _endSession(message: 'Camera live band ho gayi.');
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Camera se Live')),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _CamStage.loading:
        return const LoadingView();
      case _CamStage.error:
        return _buildError();
      case _CamStage.ready:
      case _CamStage.starting:
        return _buildReady();
      case _CamStage.live:
        return _buildLive();
    }
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded, size: 44, color: context.surfaces.textDim),
            const SizedBox(height: 12),
            Text(_errorText, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 18),
            if (_permanentlyDenied)
              ElevatedButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Settings kholein'),
              )
            else
              ElevatedButton.icon(
                onPressed: _initCamera,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Dobara try karein'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview({required Widget overlay}) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          ApiVideoCameraPreview(controller: c, fit: BoxFit.cover),
          overlay,
        ],
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap, {Color? color}) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color ?? Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildReady() {
    final starting = _stage == _CamStage.starting;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LiveLimitBanner(limits: _limits, waitSeconds: _waitSeconds),
              const SizedBox(height: 14),
              AspectRatio(
                aspectRatio: 3 / 4,
                child: _preview(
                  overlay: Positioned(
                    top: 10,
                    right: 10,
                    child: _roundButton(Icons.cameraswitch_rounded, _switchCamera),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _titleCtrl,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Stream Title (optional)',
                  hintText: 'e.g. Meri Live Stream',
                ),
              ),
              Text(
                'Camera aur mic seedha YouTube par jayenge. Live ke dauraan app khuli rakhein aur internet accha rakhein (720p ke liye lagbhag 3 Mbps upload).',
                style: TextStyle(color: context.surfaces.textDim, fontSize: 12),
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
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (starting || _blocked) ? null : _goLive,
              icon: starting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.podcasts_rounded, size: 18),
              label: Text(starting ? 'Starting...' : 'Go Live'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLive() {
    final remaining = (_secondsAllowed - _secondsElapsed).clamp(0, _secondsAllowed);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _preview(
              overlay: Stack(
                children: [
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(color: _connected ? Colors.redAccent : Colors.orange, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _connected ? 'LIVE  ${formatCountdown(_secondsElapsed)}' : 'Connecting...',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Column(
                      children: [
                        _roundButton(Icons.cameraswitch_rounded, _switchCamera),
                        const SizedBox(height: 8),
                        _roundButton(_muted ? Icons.mic_off_rounded : Icons.mic_rounded, _toggleMute,
                            color: _muted ? Colors.redAccent : Colors.white),
                        if (_watchUrl != null) ...[
                          const SizedBox(height: 8),
                          _roundButton(
                            Icons.open_in_new_rounded,
                            () => launchUrl(Uri.parse(_watchUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
              Text(
                '${formatCountdown(remaining)} remaining${_isFreeTrial ? ' (Free Trial)' : ''}'
                '${_waitSeconds > 0 ? '  •  Agla live ${formatCountdown(_waitSeconds)} baad' : ''}',
                style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                  onPressed: _stopping ? null : () => _endSession(message: 'Camera live band ho gayi.'),
                  icon: const Icon(Icons.stop_circle_rounded, size: 18),
                  label: const Text('Stop Live'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}