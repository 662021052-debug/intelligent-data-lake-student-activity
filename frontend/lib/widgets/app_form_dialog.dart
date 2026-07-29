import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// โครง dialog ของฟอร์มทุกตัวในแอป — ขนาด/ระยะขอบ/ปุ่มเหมือนกันหมด
///
/// ปุ่ม "ยกเลิก" เป็น text button และ "บันทึก" เป็น primary (FilledButton) ชิดขวาเสมอ
/// พร้อม spinner ตอนกำลังบันทึก และช่องแสดง error ใต้ฟอร์ม
class AppFormDialog extends StatelessWidget {
  const AppFormDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.onSubmit,
    this.formKey,
    this.saving = false,
    this.error,
    this.submitLabel = 'บันทึก',
    this.width = 440,
  });

  final String title;

  /// ช่องกรอกของฟอร์ม เรียงบนลงล่าง (คั่นระยะห่างให้อัตโนมัติ)
  final List<Widget> fields;
  final GlobalKey<FormState>? formKey;
  final VoidCallback onSubmit;
  final bool saving;
  final String? error;
  final String submitLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(title),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      content: SizedBox(
        width: width,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final field in fields) ...[
                  field,
                  const SizedBox(height: AppSpacing.md),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline,
                            size: 18, color: theme.colorScheme.error),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            error!,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: saving ? null : onSubmit,
          child: saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(submitLabel),
        ),
      ],
    );
  }
}
