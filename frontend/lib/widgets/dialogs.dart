import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/api_error.dart';

Future<bool?> confirmDelete(BuildContext context, String name) {
  return confirmAction(
    context,
    title: 'ยืนยันการลบ',
    message: 'ต้องการลบ "$name" ใช่หรือไม่?',
    detail: 'ลบแล้วไม่สามารถกู้คืนได้',
    confirmLabel: 'ลบ',
    icon: Icons.delete_outline,
    destructive: true,
  );
}

/// Dialog ยืนยันการทำรายการสำคัญ (สมัคร / ยกเลิก / ลบ) — คืนค่า true เมื่อผู้ใช้ยืนยัน
///
/// แสดงสรุปสิ่งที่กำลังจะเกิดขึ้นให้ชัดก่อนกด: [message] คือสิ่งที่ทำ,
/// [detail] คือผลที่ตามมา (เช่น "ลบแล้วกู้คืนไม่ได้")
Future<bool?> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String? detail,
  String confirmLabel = 'ยืนยัน',
  IconData? icon,
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final accent = destructive ? theme.colorScheme.error : theme.colorScheme.primary;

      return AlertDialog(
        icon: Icon(icon ?? (destructive ? Icons.warning_amber_rounded : Icons.help_outline),
            color: accent),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: theme.textTheme.bodyLarge),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: destructive ? accent : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

void showErrorSnackbar(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(friendlyError(error)),
      backgroundColor: Colors.red,
    ),
  );
}

void showInfoSnackbar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String? requiredValidator(String? value) =>
    (value == null || value.trim().isEmpty) ? 'กรอกข้อมูล' : null;
