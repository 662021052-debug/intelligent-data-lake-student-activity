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

/// กล่องหัวข้อ + คำอธิบายที่ครอบกลุ่มช่องกรอก — หน้าตาเดียวกับบล็อก "นับเข้าเกณฑ์ชั่วโมง"
/// ของฟอร์มกิจกรรม
///
/// [hero] = บล็อกพระเอกของฟอร์ม (พื้นฟ้ามีกรอบ) ใช้กับช่องที่กำหนดผลลัพธ์หลัก
/// ส่วนบล็อกธรรมดาเป็นพื้นขาวเส้นบาง — ผู้ใช้เห็นทันทีว่าช่องไหนสำคัญกว่า
class FormBlock extends StatelessWidget {
  const FormBlock({
    super.key,
    required this.title,
    this.description,
    this.hero = false,
    required this.children,
  });

  final String title;
  final String? description;
  final bool hero;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md + 2, AppSpacing.md + 2, AppSpacing.md + 2, AppSpacing.md),
      decoration: BoxDecoration(
        color: hero ? AppColors.blueBg : AppColors.surface,
        border: Border.all(
          color: hero ? AppColors.blue.withValues(alpha: 0.3) : AppColors.line,
          width: hero ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.blueDark),
          ),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              description!,
              style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.sub),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// ช่องกรอกวางคู่กันในแถวเดียว — จอแคบ (< 600) เรียงลงเป็นคอลัมน์
///
/// ตัดสินจากความกว้างจอ ไม่ใช่ LayoutBuilder: AlertDialog วัดขนาดแบบ intrinsic ซึ่ง
/// LayoutBuilder ไม่รองรับ (assert ล้มเมื่อไดอะล็อกอยู่ในพื้นที่สูงไม่จำกัด) ส่วนไดอะล็อกฟอร์ม
/// กว้างคงที่อยู่แล้ว ความกว้างจอจึงบอกได้พอว่ามีที่วางสองช่องไหม
class FormFieldRow extends StatelessWidget {
  const FormFieldRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            children[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

class AppFormDialog extends StatelessWidget {
  const AppFormDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.fields,
    required this.onSubmit,
    this.formKey,
    this.saving = false,
    this.error,
    this.submitLabel = 'บันทึก',
    this.width = 440,
  });

  final String title;

  /// คำอธิบายสั้น ๆ ใต้หัวข้อ dialog (ไม่ใส่ก็ได้)
  final String? subtitle;

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
      title: subtitle == null
          ? Text(title)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
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
