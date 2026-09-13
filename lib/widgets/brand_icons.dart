import 'package:flutter/material.dart';

/// Real brand icons (drawn with CustomPainter, no external asset/package
/// dependency needed) — used everywhere we previously used emoji (📺 📘 📁)
/// for platform logos, so YouTube / Facebook / Drive always render as their
/// actual brand mark instead of a generic emoji glyph.
///
/// ⚠️ UPDATE (Boss request): added TwitterIcon (current "X" wordmark, since
/// that's the platform's real current logo) and LinkedinIcon, so the About
/// screen's social-links row can use real brand marks for all four
/// platforms (YouTube, Instagram, Twitter/X, LinkedIn) instead of generic
/// Material icons.

class YoutubeIcon extends StatelessWidget {
  final double size;
  const YoutubeIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _YoutubePainter()),
    );
  }
}

class _YoutubePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, h * 0.14, w, h * 0.72),
      Radius.circular(h * 0.22),
    );
    final bgPaint = Paint()..color = const Color(0xFFFF0000);
    canvas.drawRRect(rrect, bgPaint);

    final playPath = Path()
      ..moveTo(w * 0.40, h * 0.32)
      ..lineTo(w * 0.40, h * 0.68)
      ..lineTo(w * 0.68, h * 0.50)
      ..close();
    canvas.drawPath(playPath, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FacebookIcon extends StatelessWidget {
  final double size;
  const FacebookIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _FacebookPainter()),
    );
  }
}

// Stroked-skeleton "f" (see previous rewrite note) — this pass just tunes
// proportions: the stem is centered a touch more to the left (closer to
// the real wordmark, which isn't perfectly centered in the circle), the
// hook curve is rounder and reaches further up, the crossbar sits closer
// to true middle, and the stroke is slightly thinner so the glyph reads
// cleanly at small icon sizes instead of looking heavy/blobby.
class _FacebookPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    // Circle background
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF1877F2));

    final strokeWidth = w * 0.13;
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Stem + top hook as ONE continuous path — no seam to misalign.
    // Stem sits at x=0.52 (near-center, slightly left) and runs from
    // just above the bottom to just below the top, then curves into a
    // rounder hook that reaches up to y=0.18 before turning right.
    final stemAndHook = Path()
      ..moveTo(w * 0.52, h * 0.79)
      ..lineTo(w * 0.52, h * 0.32)
      ..quadraticBezierTo(w * 0.52, h * 0.18, w * 0.66, h * 0.18)
      ..lineTo(w * 0.71, h * 0.18);
    canvas.drawPath(stemAndHook, strokePaint);

    // Crossbar — short horizontal stroke right through the stem's
    // midpoint, matching the real wordmark's proportions.
    final crossbar = Path()
      ..moveTo(w * 0.38, h * 0.50)
      ..lineTo(w * 0.60, h * 0.50);
    canvas.drawPath(crossbar, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Instagram's glyph — rounded-square gradient background (the real IG
/// wordmark uses a purple->pink->orange radial gradient) with a camera
/// ring + lens dot + shutter highlight drawn on top.
class InstagramIcon extends StatelessWidget {
  final double size;
  const InstagramIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _InstagramPainter()),
    );
  }
}

class _InstagramPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);

    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.28));
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFEDA77), Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF), Color(0xFF515BD4)],
        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, bgPaint);

    final strokeWidth = w * 0.09;
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Camera body (rounded square outline)
    final bodyRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.20, h * 0.20, w * 0.60, h * 0.60),
      Radius.circular(w * 0.16),
    );
    canvas.drawRRect(bodyRRect, strokePaint);

    // Lens (center circle)
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.15, strokePaint);

    // Shutter/flash dot (top-right)
    canvas.drawCircle(Offset(w * 0.68, h * 0.32), w * 0.045, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DriveIcon extends StatelessWidget {
  final double size;
  const DriveIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DrivePainter()),
    );
  }
}

class _DrivePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Left triangle (yellow) — top-left arm of the Drive logomark.
    final left = Path()
      ..moveTo(w * 0.32, h * 0.06)
      ..lineTo(w * 0.02, h * 0.58)
      ..lineTo(w * 0.22, h * 0.94)
      ..lineTo(w * 0.52, h * 0.42)
      ..close();
    canvas.drawPath(left, Paint()..color = const Color(0xFFFFC107));

    // Right triangle (green).
    final right = Path()
      ..moveTo(w * 0.68, h * 0.06)
      ..lineTo(w * 0.98, h * 0.58)
      ..lineTo(w * 0.78, h * 0.94)
      ..lineTo(w * 0.48, h * 0.42)
      ..close();
    canvas.drawPath(right, Paint()..color = const Color(0xFF4CAF50));

    // Bottom triangle (blue).
    final bottom = Path()
      ..moveTo(w * 0.22, h * 0.94)
      ..lineTo(w * 0.78, h * 0.94)
      ..lineTo(w * 0.63, h * 0.68)
      ..lineTo(w * 0.37, h * 0.68)
      ..close();
    canvas.drawPath(bottom, Paint()..color = const Color(0xFF2196F3));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Twitter / X — current real wordmark is the black square with a white
/// "X" mark (Twitter's own current branding, not the legacy bird), drawn
/// as two crossing strokes so it matches the platform's actual present-day
/// logo rather than an outdated one.
class TwitterIcon extends StatelessWidget {
  final double size;
  const TwitterIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TwitterPainter()),
    );
  }
}

class _TwitterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w * 0.24),
    );
    canvas.drawRRect(rrect, Paint()..color = Colors.black);

    final strokeWidth = w * 0.11;
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(w * 0.30, h * 0.28), Offset(w * 0.70, h * 0.72), strokePaint);
    canvas.drawLine(Offset(w * 0.70, h * 0.28), Offset(w * 0.30, h * 0.72), strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// LinkedIn — the real mark is a rounded-square "LinkedIn blue" background
/// with the white "in" lettermark (a dot-topped stem for the "i" and a
/// rounded-leg "n") — drawn geometrically rather than as text so it stays
/// crisp at any icon size.
class LinkedinIcon extends StatelessWidget {
  final double size;
  const LinkedinIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LinkedinPainter()),
    );
  }
}

class _LinkedinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w * 0.18),
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF0A66C2));

    final fillPaint = Paint()..color = Colors.white;

    // "i" — dot + stem
    canvas.drawCircle(Offset(w * 0.30, h * 0.32), w * 0.07, fillPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.24, h * 0.44, w * 0.12, h * 0.32),
        Radius.circular(w * 0.03),
      ),
      fillPaint,
    );

    // "n" — left stem + rounded hump + right leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.48, h * 0.44, w * 0.11, h * 0.32),
        Radius.circular(w * 0.03),
      ),
      fillPaint,
    );
    final hump = Path()
      ..moveTo(w * 0.48, h * 0.52)
      ..cubicTo(w * 0.48, h * 0.40, w * 0.78, h * 0.40, w * 0.78, h * 0.54)
      ..lineTo(w * 0.78, h * 0.76)
      ..lineTo(w * 0.67, h * 0.76)
      ..lineTo(w * 0.67, h * 0.56)
      ..cubicTo(w * 0.67, h * 0.50, w * 0.59, h * 0.50, w * 0.59, h * 0.56)
      ..lineTo(w * 0.59, h * 0.76)
      ..lineTo(w * 0.48, h * 0.76)
      ..close();
    canvas.drawPath(hump, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}