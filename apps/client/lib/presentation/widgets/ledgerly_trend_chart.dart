import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/ledger_repository.dart';
import '../design/ledgerly_theme.dart';

class LedgerlyTrendChart extends StatelessWidget {
  const LedgerlyTrendChart({
    super.key,
    required this.month,
    required this.transactions,
  });

  final DateTime month;
  final List<TransactionSummary> transactions;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${month.year}年${month.month}月每日收支趋势图',
      image: true,
      child: Column(
        children: [
          SizedBox(
            height: 170,
            child: CustomPaint(
              painter: _TrendPainter(month: month, transactions: transactions),
              size: const Size(double.infinity, 170),
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: LedgerlyColors.income, label: '收入'),
              SizedBox(width: 20),
              _LegendDot(color: LedgerlyColors.chartTeal, label: '支出'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.month, required this.transactions});

  final DateTime month;
  final List<TransactionSummary> transactions;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 10.0;
    const bottom = 22.0;
    const left = 8.0;
    const right = 8.0;
    final chart =
        Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final gridPaint = Paint()
      ..color = LedgerlyColors.divider
      ..strokeWidth = 1;
    for (var index = 0; index <= 3; index++) {
      final y = chart.top + chart.height * index / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    final days = DateTime(month.year, month.month + 1, 0).day;
    final income = List<BigInt>.filled(days, BigInt.zero);
    final expense = List<BigInt>.filled(days, BigInt.zero);
    for (final transaction in transactions) {
      final local = transaction.occurredAt.toLocal();
      if (local.year != month.year || local.month != month.month) continue;
      final target = transaction.kind == TransactionSummaryKind.income
          ? income
          : transaction.kind == TransactionSummaryKind.expense
              ? expense
              : null;
      if (target != null) {
        target[local.day - 1] += transaction.amountMinor;
      }
    }

    var maxValue = 1.0;
    for (final value in [...income, ...expense]) {
      maxValue = math.max(maxValue, value.toDouble());
    }
    _drawSeries(canvas, chart, income, maxValue, LedgerlyColors.income);
    _drawSeries(canvas, chart, expense, maxValue, LedgerlyColors.chartTeal);
  }

  void _drawSeries(
    Canvas canvas,
    Rect chart,
    List<BigInt> values,
    double maxValue,
    Color color,
  ) {
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = chart.left + chart.width * index / (values.length - 1);
      final y =
          chart.bottom - chart.height * values[index].toDouble() / maxValue;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.month != month ||
        oldDelegate.transactions != transactions;
  }
}
