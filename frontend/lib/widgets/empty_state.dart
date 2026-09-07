import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/api_error.dart';

/// หน้าจอ/ส่วนที่ "ยังไม่มีข้อมูล" — ใช้ไอคอน + ข้อความแทนพื้นที่ว่างเปล่า
///
/// เดิมแต่ละหน้าเขียน `Center(child: Text('ไม่พบข้อมูล'))` เองซึ่งดูเหมือนหน้าพัง
/// มากกว่าจะสื่อว่า "ยังไม่มีรายการ"
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.palette = StatusPalette.info,
  });

  final IconData icon;
  final String title;

  /// สีของวงกลมไอคอน — ปกติเป็นฟ้าอ่อน ส่วนกรณีผิดพลาดใช้โทนแดง
  final StatusPalette palette;

  /// คำอธิบายเพิ่ม เช่น บอกว่าต้องทำอะไรต่อ
  final String? message;

  /// ปุ่มลัด (เช่น "เพิ่มรายการแรก") ถ้ามี
  final Widget? action;

  /// ไม่พบข้อมูลเพราะ "ตัวกรอง/คำค้น" ไม่ตรง — ต่างจากยังไม่มีข้อมูลเลย
  factory EmptyState.noResults({String? message}) => EmptyState(
        icon: Icons.search_off,
        title: 'ไม่พบรายการที่ค้นหา',
        message: message ?? 'ลองเปลี่ยนคำค้นหรือล้างตัวกรองดู',
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: palette.background,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: palette.foreground),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// ข้อความแสดงข้อผิดพลาดแบบเดียวกันทั้งแอป (เดิมใช้ `Text(style: red)` กระจายทุกหน้า)
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return EmptyState(
      icon: Icons.error_outline,
      title: 'โหลดข้อมูลไม่สำเร็จ',
      palette: StatusPalette.rejected,
      message: friendlyError(message),
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
            ),
    );
  }
}

/// สถานะ "กำลังโหลด" แบบเดียวกันทั้งแอป — วงหมุน + ข้อความไทยบอกว่ากำลังทำอะไร
///
/// เดิมแต่ละหน้าใช้ `Center(child: CircularProgressIndicator())` เปล่า ๆ ซึ่ง
/// ไม่บอกผู้ใช้ว่ากำลังรออะไรอยู่
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message = 'กำลังโหลดข้อมูล...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.sub),
            ),
          ],
        ),
      ),
    );
  }
}
