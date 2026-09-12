import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ระดับความหมายของตัวเลข KPI — ใช้เฉพาะตัวเลขที่ "ดี/แย่" มีความหมายจริง ๆ
///
/// ตัวเลขกลาง ๆ อย่าง "จำนวนนิสิต" ให้ใช้ [KpiTone.neutral] เสมอ
/// จะได้ไม่แย่งสายตากับตัวที่ต้องเตือน
enum KpiTone { neutral, good, warning, critical }

/// การ์ดตัวเลขสรุปบนแดชบอร์ด: ไอคอน + ตัวเลขใหญ่ + label (+ แถบความคืบหน้า)
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.tone = KpiTone.neutral,
    this.progress,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final KpiTone tone;

  /// 0..1 ถ้าใส่มาจะมีแถบความคืบหน้าใต้ตัวเลข
  final double? progress;

  /// ตัวเลขหลักของหน้า (ตัวใหญ่กว่าใบอื่น) — ควรมีใบเดียวต่อหน้า
  final bool emphasized;

  StatusPalette _palette(ColorScheme scheme) => switch (tone) {
        KpiTone.good => StatusPalette.approved,
        KpiTone.warning => StatusPalette.pending,
        KpiTone.critical => StatusPalette.rejected,
        KpiTone.neutral => StatusPalette.info,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = _palette(scheme);
    // เลขกลาง ๆ ใช้สีตัวอักษรปกติ ให้สีสื่อความหมายเหลือไว้กับตัวที่ต้องสื่อจริง
    final valueColor = tone == KpiTone.neutral ? scheme.onSurface : palette.foreground;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ตาม mockup: ป้ายชื่อกับตัวเลขอยู่ซ้าย ไอคอนเป็นวงกลมสีชิดขวา
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        value,
                        style: (emphasized
                                ? theme.textTheme.displaySmall
                                : theme.textTheme.headlineMedium)
                            ?.copyWith(fontWeight: FontWeight.w700, color: valueColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: palette.background, shape: BoxShape.circle),
                  child: Icon(icon, size: 21, color: palette.foreground),
                ),
              ],
            ),
            if (sub != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                sub!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: AppSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    tone == KpiTone.neutral ? scheme.primary : palette.foreground,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
