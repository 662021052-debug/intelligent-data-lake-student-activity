import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// โครง dialog ของฟอร์มทุกตัวในแอป — ขนาด/ระยะขอบ/ปุ่มเหมือนกันหมด
///
/// ปุ่ม "ยกเลิก" เป็น text button และ "บันทึก" เป็น primary (FilledButton) ชิดขวาเสมอ
/// พร้อม spinner ตอนกำลังบันทึก และช่องแสดง error ใต้ฟอร์ม
/// หัวข้อย่อยคั่นกลุ่มช่องกรอกใน [AppFormDialog]
///
/// ใช้เมื่อฟอร์มยาวจนอ่านเป็นพืดเดียวไม่ไหว เช่น "ข้อมูลนิสิต" กับ
/// "บัญชีเข้าใช้งาน" — เส้นคั่นบาง ๆ ใต้หัวข้อทำหน้าที่แบ่งสายตา
class FormSectionHeader extends StatelessWidget {
  const FormSectionHeader(this.title, {super.key, this.note, this.first = false});

  final String title;

  /// คำอธิบายเล็ก ๆ ใต้หัวข้อ เช่น บอกว่าเครื่องหมาย * แปลว่าอะไร
  final String? note;

  /// หัวข้อแรกของฟอร์มไม่ต้องเว้นด้านบน (ชิดกับ title ของ dialog อยู่แล้ว)
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                note!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          const Divider(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

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
          // ปิดโดยไม่ส่งค่ากลับ — ผู้เรียกทุกที่เช็ก "สำเร็จหรือไม่" จาก
          // ค่าที่ฝั่งบันทึกส่งมาเท่านั้น การ pop(false) ตายตัวจะพังกับ dialog
          // ที่ประกาศชนิดผลลัพธ์เป็นอย่างอื่น (เช่น StudentSaveResult)
          onPressed: saving ? null : () => Navigator.pop(context),
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
