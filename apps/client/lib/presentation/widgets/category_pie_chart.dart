import 'dart:math';

import 'package:flutter/material.dart';

/// Lightweight donut-style pie chart for category spending.
///
/// Renders [slices] as a circular ring with each slice colored from
/// a deterministic palette. Slices are normalized to the total so the
/// chart always fills the ring. Empty input renders nothing.
class CategoryPieChart extends StatelessWidget {
  const CategoryPieChart({
    super.key,
    required this.slices,
    this.size = 120,
    this.thickness = 18,
    this.backgroundColor,
  });

  final List<CategorySlice> slices;
  final double size;
  final double thickness;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) return SizedBox(width: size, height: size);
    final total = slices.fold<BigInt>(
      BigInt.zero,
      (sum, slice) => sum + slice.amountMinor,
    );
    if (total <= BigInt.zero) {
      return SizedBox(width: size, height: size);
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PiePainter(
          slices: slices,
          thickness: thickness,
          background:
              backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
          emptyColor: Theme.of(context).dividerColor,
        ),
      ),
    );
  }
}

class CategorySlice {
  CategorySlice({required this.label, required this.amountMinor});
  final String label;
  final BigInt amountMinor;
}

class _PiePainter extends CustomPainter {
  _PiePainter({
    required this.slices,
    required this.thickness,
    required this.background,
    required this.emptyColor,
  });

  final List<CategorySlice> slices;
  final double thickness;
  final Color background;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background ring.
    final bgPaint = Paint()
      ..color = background
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;
    canvas.drawCircle(center, radius - thickness / 2, bgPaint);

    final total = slices.fold<double>(
      0,
      (sum, slice) => sum + slice.amountMinor.abs().toDouble(),
    );
    if (total <= 0) return;

    var startAngle = -pi / 2; // start at top
    for (final slice in slices) {
      final amount = slice.amountMinor.abs().toDouble();
      if (amount <= 0) continue;
      final sweep = (amount / total) * 2 * pi;
      final paint = Paint()
        ..color = _colorFor(slice.label)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }

    // Inner hole highlight
    final holePaint = Paint()..color = emptyColor.withValues(alpha: 0.0);
    canvas.drawCircle(center, radius - thickness, holePaint);
  }

  static Color _colorFor(String label) {
    // Deterministic hue derived from the label's hash.
    final hash = label.codeUnits.fold<int>(0, (a, b) => (a + b) & 0xffffff);
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.55, 0.55).toColor();
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) {
    if (old.slices.length != slices.length) return true;
    for (var i = 0; i < slices.length; i++) {
      if (old.slices[i].label != slices[i].label) return true;
      if (old.slices[i].amountMinor != slices[i].amountMinor) return true;
    }
    if (old.thickness != thickness) return true;
    if (old.background != background) return true;
    return false;
  }
}
