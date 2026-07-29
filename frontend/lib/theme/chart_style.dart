import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// สไตล์กลางของกราฟทุกตัวในแดชบอร์ด — เส้นกริด/แกน/ทูลทิปมาจากที่นี่ที่เดียว
///
/// หลักที่ยึด: ข้อมูลเป็นสิ่งเดียวที่เด่น ส่วนกริดกับแกนต้องจางและบาง (hairline)
/// สีของ "ตัวหนังสือ" ใช้สีตัวอักษรเสมอ ไม่ใช้สีของชุดข้อมูล — ตัวที่บอกว่าเป็นชุดไหน
/// คือจุดสี/แท่งสีที่อยู่ข้าง ๆ ข้อความ
abstract final class ChartStyle {
  /// ความหนาสูงสุดของแท่ง (ปล่อยที่ว่างรอบแท่งไว้ ไม่เต็มช่อง)
  static const double barWidth = 22;

  /// ความหนาเส้นกราฟเส้น
  static const double lineWidth = 2;

  static Color gridColor(ColorScheme scheme) => scheme.outlineVariant;

  static Color axisLabelColor(ColorScheme scheme) => scheme.onSurfaceVariant;

  /// เส้นกริดแนวนอนอย่างเดียว บาง ทึบ (ไม่ประ) และจาง
  static FlGridData grid(ColorScheme scheme) => FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: gridColor(scheme),
          strokeWidth: 1,
        ),
      );

  /// ป้ายแกน: สีตัวอักษรรอง ขนาดเล็ก ตัวเลขเรียงตรงกัน (tabular)
  static TextStyle axisLabel(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodySmall!.copyWith(
      color: axisLabelColor(theme.colorScheme),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// ทูลทิปพื้นหลังสีพื้นผิว + ขอบบาง อ่านง่ายกว่าสีดำทึบแบบค่าเริ่มต้น
  static BarTouchTooltipData barTooltip(
    ColorScheme scheme, {
    required GetBarTooltipItem getTooltipItem,
  }) =>
      BarTouchTooltipData(
        getTooltipColor: (_) => scheme.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(AppRadius.chip),
        tooltipPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        getTooltipItem: getTooltipItem,
      );

  static LineTouchTooltipData lineTooltip(
    ColorScheme scheme, {
    required GetLineTooltipItems getTooltipItems,
  }) =>
      LineTouchTooltipData(
        getTooltipColor: (_) => scheme.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(AppRadius.chip),
        tooltipPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        getTooltipItems: getTooltipItems,
      );

  /// สไตล์ตัวอักษรในทูลทิป (บนพื้น inverseSurface)
  static TextStyle tooltipText(ColorScheme scheme) => TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 12,
        height: 1.4,
      );
}

/// คีย์อธิบายชุดข้อมูล: จุดสี/แถบสี + ข้อความ (ข้อความไม่ทาสีของชุดข้อมูล)
class ChartLegendKey extends StatelessWidget {
  const ChartLegendKey({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
