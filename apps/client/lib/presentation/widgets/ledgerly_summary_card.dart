import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../design/ledgerly_theme.dart';
import 'ledgerly_finance.dart';

class LedgerlySummaryCard extends StatelessWidget {
  const LedgerlySummaryCard({
    super.key,
    required this.title,
    required this.balanceMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    this.balanceLabel,
    this.showFlow = true,
  });

  final String title;
  final String? balanceLabel;
  final BigInt balanceMinor;
  final BigInt incomeMinor;
  final BigInt expenseMinor;
  final bool showFlow;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final resolvedBalanceLabel = balanceLabel ?? l10n.thisMonthBalance;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxWidth / 2.15).clamp(176.0, 220.0);
        return SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const CustomPaint(painter: _LedgerCoverPainter()),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const Spacer(),
                      Text(
                        resolvedBalanceLabel,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatDisplayMinor(balanceMinor, symbol: false),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (showFlow) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            Text(
                              l10n.incomeAmount(
                                formatDisplayMinor(incomeMinor, symbol: false),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              l10n.expenseAmount(
                                formatDisplayMinor(expenseMinor, symbol: false),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LedgerCoverPainter extends CustomPainter {
  const _LedgerCoverPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF8DB6B2));
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.22),
      size.shortestSide * 0.12,
      Paint()..color = LedgerlyColors.action,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * 0.70)
        ..lineTo(size.width * 0.46, size.height * 0.42)
        ..lineTo(size.width * 0.68, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = const Color(0xFF123E48),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.62,
        size.height * 0.34,
        size.width * 0.38,
        size.height * 0.66,
      ),
      Paint()..color = const Color(0xFFECE9E0),
    );
    final line = Paint()
      ..color = const Color(0xFF887E70)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final x = size.width * 0.78;
    canvas.drawLine(
      Offset(x - 8, size.height * 0.50),
      Offset(x - 24, size.height),
      line,
    );
    canvas.drawLine(
      Offset(x + 12, size.height * 0.50),
      Offset(x + 2, size.height),
      line,
    );
    for (var index = 0; index < 5; index++) {
      final y = size.height * (0.56 + index * 0.08);
      canvas.drawLine(
          Offset(x - 10, y), Offset(x + 9, y), line..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
