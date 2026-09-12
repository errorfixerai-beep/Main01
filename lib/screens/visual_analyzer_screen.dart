import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import 'diamond_store_screen.dart';

/// Screen 5/7 — thumbnail mockup previewer + on-device contrast analysis.
///
/// The "Visual Score" is computed for real, on-device, from the picked
/// image's actual pixels (luminance standard deviation = contrast proxy,
/// mean luminance = brightness) — not a placeholder/random number. There's
/// no ML-based composition/face-detection scoring here (that would need a
/// vision model this app doesn't have access to); this is a genuine but
/// simple contrast+brightness heuristic, labelled as such.
class VisualAnalyzerScreen extends StatefulWidget {
  const VisualAnalyzerScreen({super.key});
  @override
  State<VisualAnalyzerScreen> createState() => _VisualAnalyzerScreenState();
}

enum _MockupTab { instagram, youtube, facebook }

class _VisualAnalyzerScreenState extends State<VisualAnalyzerScreen> {
  File? _image;
  final _titleCtrl = TextEditingController(text: 'Your Video Title Here');
  // ⚠️ UPDATE (Boss request — "Facebook/Instagram verification pending,
  // YouTube verification complete, sirf YouTube launch kar rahe hain"):
  // default tab changed from instagram -> youtube, since Instagram/
  // Facebook are no longer selectable below (the SegmentedButton selector
  // itself has now been removed entirely — see next comment). The
  // _MockupTab enum and every mockupFrame() case for instagram/facebook
  // are UNCHANGED — adding the selector UI back below with all three
  // segments brings this all back instantly.
  final _MockupTab _tab = _MockupTab.youtube;
  bool _analyzing = false;
  double? _contrastScore; // 0-100
  double? _brightness; // 0-255

  // ⚠️ NEW (Boss request — Gemini AI-fix prompt card, diamond-gated):
  // null while loading, then the user's current diamond balance from
  // GET /api/wallet. `_isUnlocked` gates both the full prompt text and
  // the direct Gemini-app open action. On fetch failure, defaults to 0
  // (locked) — safest default, never silently unlocks a paid feature.
  int? _diamondBalance;
  static const int _previewWordCount = 13; // "10-15 words" — used for both the locked-state preview and the locked-state partial copy.

  bool get _isUnlocked => (_diamondBalance ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _loadDiamondBalance();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDiamondBalance() async {
    try {
      final res = await ApiService.instance.getWallet();
      if (!mounted) return;
      setState(() {
        _diamondBalance = (res['wallet']?['diamondBalance'] as int?) ?? 0;
      });
    } catch (_) {
      // Silent fail — if balance can't be fetched, treat as locked (0)
      // rather than risk unlocking a paid feature on an error.
      if (mounted) setState(() => _diamondBalance = 0);
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    setState(() {
      _image = File(picked.path);
      _contrastScore = null;
      _brightness = null;
    });
    await _analyze();
  }

  Future<void> _analyze() async {
    if (_image == null) return;
    setState(() => _analyzing = true);
    try {
      final bytes = await _image!.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 120); // downscale for a fast, cheap sample
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;

      final pixels = byteData.buffer.asUint8List();
      final luminances = <double>[];
      for (int i = 0; i < pixels.length; i += 4) {
        final r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
        luminances.add(0.299 * r + 0.587 * g + 0.114 * b);
      }
      final mean = luminances.reduce((a, b) => a + b) / luminances.length;
      final variance = luminances.map((l) => (l - mean) * (l - mean)).reduce((a, b) => a + b) / luminances.length;
      final stdDev = math.sqrt(variance.abs());
      final normalizedContrast = (stdDev / 128 * 100).clamp(0, 100).toDouble();

      setState(() {
        _brightness = mean;
        _contrastScore = normalizedContrast;
      });
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Color _scoreColor(double score) {
    if (score >= 60) return AppColors.green;
    if (score >= 35) return const Color(0xFFF5A623);
    return AppColors.red;
  }

  String _readabilityNote() {
    if (_contrastScore == null || _brightness == null) return '';
    if (_contrastScore! < 35) return context.tr('visual_note_low_contrast');
    if (_brightness! < 60) return context.tr('visual_note_dark_overall');
    if (_brightness! > 200) return context.tr('visual_note_bright_overall');
    return context.tr('visual_note_good_balance');
  }

  // ⚠️ NEW: builds the Gemini fix-it prompt text matching whichever issue
  // _readabilityNote() detected. Returns '' when there's no issue (i.e.
  // the thumbnail is already well balanced) — used as the signal for
  // whether to show the AI-fix card at all.
  String _generateGeminiPrompt() {
    if (_contrastScore == null || _brightness == null) return '';
    if (_contrastScore! < 35) {
      return 'Redesign this YouTube thumbnail to significantly increase the contrast between the background and the foreground subject/text. Make any title text pop with a bold outline or shadow, and rebalance the color palette so the key details are still easy to read even as a tiny mobile thumbnail (about 120x67px). Keep the same overall theme and composition — just fix the low contrast.';
    }
    if (_brightness! < 60) {
      return 'This YouTube thumbnail looks too dark overall. Brighten it while keeping the same mood, and make sure the main subject and any text are clearly visible against the background — this matters most on a small mobile thumbnail. Keep the same theme and layout, just fix the exposure.';
    }
    if (_brightness! > 200) {
      return 'This YouTube thumbnail looks overexposed and washed out. Reduce the brightness slightly, add richer shadows and contrast so the subject stands out, and keep any text clearly legible. Keep the same theme and layout, just fix the exposure.';
    }
    return '';
  }

  Future<void> _openGeminiApp() async {
    // Universal link — routes to the installed Gemini app on Android/iOS
    // if it's set up as the verified app link, otherwise falls back to
    // opening it in the browser. Safer than guessing an unconfirmed
    // custom URL scheme for the native app.
    final uri = Uri.parse('https://gemini.google.com/app');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      // Swallow — worst case the user just doesn't get redirected, but
      // the prompt is already on their clipboard by this point.
    }
  }

  Future<void> _handleCopyPrompt(String fullPrompt, String partialPrompt) async {
    if (_isUnlocked) {
      await Clipboard.setData(ClipboardData(text: fullPrompt));
      if (mounted) showToast(context, 'Prompt copied to clipboard', isSuccess: true);
    } else {
      await Clipboard.setData(ClipboardData(text: partialPrompt));
      if (mounted) showToast(context, 'Sample copied — upgrade to copy the full prompt', isError: false);
    }
  }

  Future<void> _handleGeminiTap(String fullPrompt) async {
    if (!_isUnlocked) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DiamondStoreScreen()));
      return;
    }
    await Clipboard.setData(ClipboardData(text: fullPrompt));
    if (mounted) showToast(context, 'Prompt copied — opening Gemini…', isSuccess: true);
    await _openGeminiApp();
  }

  Widget _geminiFixCard() {
    final fullPrompt = _generateGeminiPrompt();
    if (fullPrompt.isEmpty) return const SizedBox.shrink();

    final words = fullPrompt.split(' ');
    final previewText = words.take(_previewWordCount).join(' ');
    final remainingText = words.length > _previewWordCount ? ' ${words.skip(_previewWordCount).join(' ')}' : '';
    final partialCopyText = previewText;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_fix_high_rounded, color: AppColors.purple, size: 18),
            const SizedBox(width: 6),
            const Text('Fix it with AI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          // Preview text (first _previewWordCount words) is always shown
          // in the clear. The rest of the prompt is only shown in the
          // clear once unlocked — while locked, it's rendered blurred via
          // ImageFiltered so the words underneath aren't actually readable.
          Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12.5, height: 1.4, color: context.surfaces.textDim),
              children: [
                TextSpan(text: previewText),
                if (remainingText.isNotEmpty)
                  WidgetSpan(
                    child: _isUnlocked
                        ? Text(remainingText, style: TextStyle(fontSize: 12.5, height: 1.4, color: context.surfaces.textDim))
                        : ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                            child: Text(remainingText, style: TextStyle(fontSize: 12.5, height: 1.4, color: context.surfaces.textDim)),
                          ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!_isUnlocked) ...[
            Text(
              context.tr('audit_prompt_locked_label'),
              style: const TextStyle(color: AppColors.purple, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _handleCopyPrompt(fullPrompt, partialCopyText),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(context.tr('audit_copy_prompt_btn')),
                ),
              ),
              const SizedBox(width: 10),
              // ⚠️ Real transparent Gemini icon — assets/gemini_icon.png,
              // no background/container behind it (registered in
              // pubspec.yaml under flutter > assets).
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _handleGeminiTap(fullPrompt),
                  child: Tooltip(
                    message: context.tr('audit_open_gemini_btn'),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset('assets/gemini_icon.png', width: 28, height: 28),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mockupFrame() {
    final title = _titleCtrl.text.trim().isEmpty ? 'Your Video Title Here' : _titleCtrl.text.trim();
    switch (_tab) {
      case _MockupTab.instagram:
        return _phoneFrame(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                const CircleAvatar(radius: 14, backgroundColor: AppColors.purple),
                const SizedBox(width: 8),
                Text(context.tr('visual_your_channel_handle'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
            AspectRatio(aspectRatio: 1, child: _imageBox()),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            ),
          ]),
        );
      case _MockupTab.youtube:
        return _phoneFrame(
          child: Column(children: [
            AspectRatio(aspectRatio: 16 / 9, child: _imageBox()),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const CircleAvatar(radius: 16, backgroundColor: AppColors.purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 3),
                    Text(context.tr('visual_your_channel_views'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
          ]),
        );
      case _MockupTab.facebook:
        return _phoneFrame(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                const CircleAvatar(radius: 14, backgroundColor: AppColors.purple),
                const SizedBox(width: 8),
                Text(context.tr('visual_your_page'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 12.5)))),
            const SizedBox(height: 8),
            AspectRatio(aspectRatio: 1.3, child: _imageBox()),
          ]),
        );
    }
  }

  Widget _phoneFrame({required Widget child}) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _imageBox() {
    if (_image == null) {
      return Container(color: context.surfaces.card2, child: const Center(child: Icon(Icons.image_outlined, size: 40)));
    }
    return Image.file(_image!, fit: BoxFit.cover, width: double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('visual_analyzer_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 140,
              decoration: BoxDecoration(border: Border.all(color: AppColors.purple, style: BorderStyle.solid), borderRadius: BorderRadius.circular(16)),
              child: _image == null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.add_photo_alternate_rounded, color: AppColors.purple, size: 30),
                        const SizedBox(height: 8),
                        Text(context.tr('visual_tap_to_pick'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    )
                  : ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(_image!, fit: BoxFit.cover, width: double.infinity)),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(controller: _titleCtrl, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: context.tr('visual_preview_title_hint'))),
          const SizedBox(height: 20),
          // ⚠️ REMOVED (Boss request — "YouTube Mobile ko permanent kar do,
          // frontend se selector hata do"): the SegmentedButton that used
          // to let the user pick a platform tab has been removed entirely.
          // `_tab` above is now a `final` locked to `_MockupTab.youtube` —
          // there is no way left in the UI to change it. The _MockupTab
          // enum and every mockupFrame() case for instagram/facebook are
          // still UNCHANGED above; to restore platform switching, make
          // `_tab` non-final again and add back:
          //   SegmentedButton<_MockupTab>(
          //     segments: [
          //       ButtonSegment(value: _MockupTab.instagram, label: Text(context.tr('visual_tab_instagram'))),
          //       ButtonSegment(value: _MockupTab.youtube, label: Text(context.tr('visual_tab_youtube'))),
          //       ButtonSegment(value: _MockupTab.facebook, label: Text(context.tr('visual_tab_facebook'))),
          //     ],
          //     selected: {_tab},
          //     onSelectionChanged: (s) => setState(() => _tab = s.first),
          //   ),
          _mockupFrame(),
          if (_image != null) ...[
            const SizedBox(height: 24),
            Text(context.tr('visual_score_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (_analyzing)
              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: LoadingView())
            else if (_contrastScore != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.contrast_rounded, color: _scoreColor(_contrastScore!), size: 20),
                      const SizedBox(width: 8),
                      Text('${context.tr('visual_contrast_label')}: ${_contrastScore!.toStringAsFixed(0)}/100', style: TextStyle(fontWeight: FontWeight.w800, color: _scoreColor(_contrastScore!))),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(value: _contrastScore! / 100, minHeight: 6, backgroundColor: context.surfaces.border, valueColor: AlwaysStoppedAnimation(_scoreColor(_contrastScore!))),
                    ),
                    const SizedBox(height: 12),
                    Text(_readabilityNote(), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
                  ],
                ),
              ),
              // ⚠️ NEW: only rendered when _generateGeminiPrompt() returns
              // non-empty (i.e. an actual issue was detected) — a
              // well-balanced thumbnail shows no fix-it card at all.
              _geminiFixCard(),
            ],
          ],
        ],
      ),
    );
  }
}