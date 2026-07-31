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
  });

  final IconData icon;
  final String title;

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
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: scheme.onSurfaceVariant),
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
