import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

String formatMilestone(num n) {
  String trim(double v) => v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  if (n >= 1000000) return '${trim(n / 1000000)}M';
  if (n >= 1000) return '${trim(n / 1000)}K';
  return n.toString();
}

// Palette taken from the approved design: cream canvas, plum purple, gold.
class _C {
  static const creamTop = Color(0xFFFCEFD9);
  static const creamBottom = Color(0xFFF9E4C6);
  static const cardBg = Color(0xFFFEF4E4);
  static const cardBorder = Color(0xFFF1DFC2);

  static const purpleDark = Color(0xFF4B1A5E);
  static const purple = Color(0xFF7A2C8C);
  static const purpleDeep = Color(0xFF5A1F6E);
  static const mauve = Color(0xFF9B6F94);

  static const goldLight = Color(0xFFF6D98A);
  static const gold = Color(0xFFD9A441);
  static const goldDeep = Color(0xFFB57F25);
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        width: 340,
        child: Stack(
          children: [
            // Cream canvas + purple/gold corner swooshes
            const Positioned.fill(child: CustomPaint(painter: _BackgroundPainter())),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 30, 16, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ---- Title with laurels ----
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _Laurel(width: 26, height: 48),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Creator Milestone',
                            style: TextStyle(
                              color: _C.purpleDark,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const _Laurel(width: 26, height: 48, mirrored: true),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ---- Channel line with avatar ----
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Avatar(url: channelAvatarUrl, name: channelTitle, size: 30),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: channelTitle,
                              style: const TextStyle(color: _C.purpleDark, fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text: isSubs ? ' has reached $v subscribers' : ' hit $v views',
                              style: const TextStyle(color: _C.mauve, fontWeight: FontWeight.w500),
                            ),
                          ]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ---- Inner card ----
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 22, 14, 22),
                    decoration: BoxDecoration(
                      color: _C.cardBg.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: _C.cardBorder, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: _C.goldDeep.withValues(alpha: 0.14),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Text-only brand mark (with the small play accent over the "e")
                        Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            const Text.rich(
                              TextSpan(children: [
                                TextSpan(text: 'Tube', style: TextStyle(color: Color(0xFF1A1A1A))),
                                TextSpan(text: 'Pilot', style: TextStyle(color: _C.purple)),
                              ]),
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                            ),
                            const Positioned(
                              top: -7,
                              left: 74,
                              child: Icon(Icons.play_arrow_rounded, color: _C.purple, size: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Hero: laurels + gold ring + purple disc + avatar badge
                        SizedBox(
                          width: 258,
                          height: 176,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Positioned(left: 0, bottom: 14, child: _Laurel(width: 52, height: 118, big: true)),
                              const Positioned(right: 0, bottom: 14, child: _Laurel(width: 52, height: 118, big: true, mirrored: true)),
                              Align(
                                alignment: const Alignment(0, -0.35),
                                child: Container(
                                  width: 150,
                                  height: 150,
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const SweepGradient(
                                      colors: [_C.goldLight, _C.gold, _C.goldDeep, _C.goldLight, _C.gold, _C.goldLight],
                                    ),
                                    boxShadow: [
                                      BoxShadow(color: _C.gold.withValues(alpha: 0.35), blurRadius: 22, spreadRadius: 1),
                                    ],
                                  ),
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        center: Alignment(-0.2, -0.3),
                                        radius: 0.95,
                                        colors: [Color(0xFF7B2E8E), Color(0xFF4F1B62)],
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Text(
                                          v,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 56,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -1,
                                            shadows: [Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Avatar badge overlapping the ring (bottom-right)
                              Positioned(
                                right: 36,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [_C.goldLight, _C.goldDeep],
                                    ),
                                  ),
                                  child: _Avatar(url: channelAvatarUrl, name: channelTitle, size: 46),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Headline
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: isSubs ? 'You reached ' : 'Your latest video hit '),
                            TextSpan(text: v, style: const TextStyle(color: _C.purple)),
                            TextSpan(text: isSubs ? ' subscribers' : ' views'),
                          ]),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _C.purpleDark,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.18,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),

                        Text(
                          isSubs ? 'Congratulations! Your community is growing.' : 'Congratulations on this milestone!',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _C.mauve, fontSize: 14, fontWeight: FontWeight.w500, height: 1.3),
                        ),
                        if (!isSubs && (videoTitle ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            videoTitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _C.mauve.withValues(alpha: 0.85), fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 18),

                        // Pill: YouTube icon + channel name
                        Container(
                          constraints: const BoxConstraints(minWidth: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: const LinearGradient(colors: [_C.purpleDeep, _C.purple]),
                            boxShadow: [
                              BoxShadow(color: _C.purpleDark.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 26,
                                height: 19,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF0000),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 15),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  channelTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
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
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cream canvas with purple swooshes + gold lines (top-left / bottom-right)
// ---------------------------------------------------------------------------
class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_C.creamTop, _C.creamBottom],
        ).createShader(rect),
    );

    // faint decorative leaves
    final faint = Paint()..color = _C.gold.withValues(alpha: 0.14);
    _leaf(canvas, Offset(w * 0.86, h * 0.07), 46, 14, -0.9, faint);
    _leaf(canvas, Offset(w * 0.08, h * 0.62), 54, 16, -0.6, faint);
    _leaf(canvas, Offset(w * 0.04, h * 0.72), 40, 12, -1.0, faint);

    // top-left purple swoosh
    final top = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.44, 0)
      ..quadraticBezierTo(w * 0.12, h * 0.025, 0, h * 0.115)
      ..close();
    canvas.drawPath(
      top,
      Paint()
        ..shader = const LinearGradient(colors: [_C.purpleDark, _C.purple]).createShader(Rect.fromLTWH(0, 0, w * 0.5, h * 0.12)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.5, 0)
        ..quadraticBezierTo(w * 0.15, h * 0.035, 0, h * 0.14),
      Paint()
        ..color = _C.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // bottom-right purple swoosh
    final bottom = Path()
      ..moveTo(w, h)
      ..lineTo(w * 0.52, h)
      ..quadraticBezierTo(w * 0.88, h * 0.975, w, h * 0.87)
      ..close();
    canvas.drawPath(
      bottom,
      Paint()
        ..shader = const LinearGradient(colors: [_C.purple, _C.purpleDark]).createShader(Rect.fromLTWH(w * 0.5, h * 0.85, w * 0.5, h * 0.15)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.46, h)
        ..quadraticBezierTo(w * 0.86, h * 0.985, w, h * 0.84),
      Paint()
        ..color = _C.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _leaf(Canvas canvas, Offset at, double len, double wid, double angle, Paint paint) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    final p = Path()
      ..quadraticBezierTo(len * 0.5, -wid, len, 0)
      ..quadraticBezierTo(len * 0.5, wid, 0, 0);
    canvas.drawPath(p, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Laurel branch (alternating gold / purple leaves along a curved stem)
// ---------------------------------------------------------------------------
class _Laurel extends StatelessWidget {
  final double width;
  final double height;
  final bool mirrored;
  final bool big;
  const _Laurel({required this.width, required this.height, this.mirrored = false, this.big = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _LaurelPainter(mirrored: mirrored, leaves: big ? 7 : 5)),
    );
  }
}

class _LaurelPainter extends CustomPainter {
  final bool mirrored;
  final int leaves;
  _LaurelPainter({required this.mirrored, required this.leaves});

  @override
  void paint(Canvas canvas, Size size) {
    if (mirrored) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final w = size.width;
    final h = size.height;

    // stem: bottom (slightly right) curving up to top (left)
    final p0 = Offset(w * 0.78, h);
    final p1 = Offset(w * 1.05, h * 0.45);
    final p2 = Offset(w * 0.30, 0);

    Offset at(double t) {
      final mt = 1 - t;
      return Offset(
        mt * mt * p0.dx + 2 * mt * t * p1.dx + t * t * p2.dx,
        mt * mt * p0.dy + 2 * mt * t * p1.dy + t * t * p2.dy,
      );
    }

    double angleAt(double t) {
      final mt = 1 - t;
      final dx = 2 * mt * (p1.dx - p0.dx) + 2 * t * (p2.dx - p1.dx);
      final dy = 2 * mt * (p1.dy - p0.dy) + 2 * t * (p2.dy - p1.dy);
      return math.atan2(dy, dx);
    }

    canvas.drawPath(
      Path()
        ..moveTo(p0.dx, p0.dy)
        ..quadraticBezierTo(p1.dx, p1.dy, p2.dx, p2.dy),
      Paint()
        ..color = _C.purple.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    final leafLen = h * 0.2;
    final leafWid = h * 0.055;
    for (var i = 0; i < leaves; i++) {
      final t = 0.1 + 0.8 * i / (leaves - 1);
      final pos = at(t);
      final a = angleAt(t);
      final scale = 1.0 - 0.35 * (i / leaves); // smaller towards the tip
      for (final side in [-1.0, 1.0]) {
        final isGold = (i + (side > 0 ? 1 : 0)) % 2 == 0;
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(a + side * 0.75);
        final path = Path()
          ..quadraticBezierTo(leafLen * scale * 0.5, -leafWid * scale, leafLen * scale, 0)
          ..quadraticBezierTo(leafLen * scale * 0.5, leafWid * scale, 0, 0);
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              colors: isGold ? [_C.goldLight, _C.goldDeep] : [_C.purple, _C.purpleDark],
            ).createShader(Rect.fromLTWH(0, -leafWid, leafLen, leafWid * 2)),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Channel avatar. Falls back to a purple letter badge when there is no photo.
// ---------------------------------------------------------------------------
class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;

  const _Avatar({required this.url, required this.name, required this.size});

  Widget _fallback() {
    final letter = name.trim().isEmpty ? 'T' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [_C.purple, _C.purpleDark]),
      ),
      child: Text(
        letter,
        style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = (url ?? '').isNotEmpty;
    final img = hasUrl
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
    // thin gold rim like the design
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: const BoxDecoration(shape: BoxShape.circle, color: _C.gold),
      child: img,
    );
  }
}