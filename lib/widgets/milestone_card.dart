import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

String formatMilestone(num n) {
  String trim(double v) => v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  if (n >= 1000000) return '${trim(n / 1000000)}M';
  if (n >= 1000) return '${trim(n / 1000)}K';
  return n.toString();
}

// Local palette for the card (vidIQ-style: deep canvas + dark card + gold hero).
class _C {
  static const canvasTop = Color(0xFF26262E);
  static const canvasMid = Color(0xFF0C0C10);
  static const canvasBottom = Color(0xFF000000);
  static const cardBg = Color(0xFF0F0F14);
  static const gold = Color(0xFFF2B531);
  static const goldDeep = Color(0xFFB9831A);
  static const goldSoft = Color(0xFFFFE08A);
  static const textDim = Color(0xFFB4B0C4);
  static const textFaint = Color(0xFF7E7A92);
}

/// The shareable achievement card. Wrap in RepaintBoundary to export as PNG.
///
/// [channelAvatarUrl] is optional. If it is null or fails to load, a letter
/// badge (first letter of the channel name) is shown instead.
class MilestoneCard extends StatelessWidget {
  final String type; // 'subscribers' | 'views'
  final int value;
  final String channelTitle;
  final String? videoTitle;
  final String? channelAvatarUrl;

  const MilestoneCard({
    super.key,
    required this.type,
    required this.value,
    required this.channelTitle,
    this.videoTitle,
    this.channelAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final v = formatMilestone(value);
    final isSubs = type == 'subscribers';

    return Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_C.canvasTop, _C.canvasMid, _C.canvasBottom],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- Title with trophy "laurels" ----
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.workspace_premium_rounded, color: _C.goldSoft, size: 22),
              const SizedBox(width: 8),
              Text(
                isSubs ? 'Subscriber Milestone' : 'Views Milestone',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.workspace_premium_rounded, color: _C.goldSoft, size: 22),
            ],
          ),
          const SizedBox(height: 10),
          // ---- Channel line with tiny avatar ----
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Avatar(url: channelAvatarUrl, name: channelTitle, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  isSubs ? '$channelTitle has $v subscribers' : '$channelTitle hit $v views',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ---- Inner dark card ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
            decoration: BoxDecoration(
              color: _C.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Text-only brand mark (no logo)
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Tube', style: TextStyle(color: Colors.white)),
                    TextSpan(text: 'Pilot', style: TextStyle(color: _C.gold)),
                  ]),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                ),
                const SizedBox(height: 20),

                // Hero ring + avatar badge
                SizedBox(
                  width: 172,
                  height: 172,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: Container(
                          width: 152,
                          height: 152,
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const SweepGradient(
                              colors: [_C.goldSoft, _C.goldDeep, _C.gold, _C.goldSoft],
                            ),
                            boxShadow: [
                              BoxShadow(color: _C.gold.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: 1),
                            ],
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [Color(0xFF2B2440), Color(0xFF17121F)],
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  v,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 50,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: const BoxDecoration(color: _C.cardBg, shape: BoxShape.circle),
                          child: _Avatar(url: channelAvatarUrl, name: channelTitle, size: 44, ring: true),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Headline (level 1)
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: isSubs ? 'You reached ' : 'Your latest video hit '),
                    TextSpan(
                      text: v,
                      style: const TextStyle(color: _C.gold, fontStyle: FontStyle.italic),
                    ),
                    TextSpan(text: isSubs ? ' subscribers' : ' views'),
                  ]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),

                // Level 2
                Text(
                  isSubs ? 'Congratulations! Your community is growing.' : 'Congratulations on this milestone!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _C.textDim, fontSize: 14, fontWeight: FontWeight.w500),
                ),

                // Level 3
                if (!isSubs && (videoTitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    videoTitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _C.textFaint, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 18),

                // Bottom pill: YouTube icon + channel name
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 22,
                        height: 16,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0000),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 13),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
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

/// Channel avatar. Falls back to a gold letter badge when there is no photo.
class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final bool ring;

  const _Avatar({required this.url, required this.name, required this.size, this.ring = false});

  Widget _fallback() {
    final letter = name.trim().isEmpty ? 'T' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [_C.goldSoft, _C.goldDeep]),
      ),
      child: Text(
        letter,
        style: TextStyle(color: Colors.black, fontSize: size * 0.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = (url ?? '').isNotEmpty;
    final child = hasUrl
        ? ClipOval(
            child: CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => _fallback(),
              errorWidget: (_, __, ___) => _fallback(),
            ),
          )
        : _fallback();
    if (!ring) return child;
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: const BoxDecoration(shape: BoxShape.circle, color: _C.gold),
      child: child,
    );
  }
}