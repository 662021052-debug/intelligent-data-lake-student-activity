import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// สไตล์ปุ่มที่ไม่ใช่ปุ่มหลัก — ปุ่มหลัก (พื้นฟ้า) กับปุ่มรอง (ขอบเทาพื้นขาว)
/// มาจากธีมกลางอยู่แล้ว ใช้ [FilledButton] และ [OutlinedButton] ได้ตรง ๆ
abstract final class AppButtonStyles {
  /// ปุ่มสีเข้ม — ใช้กับงานเอกสาร/พิมพ์ เช่น "ใบประมวลผลกิจกรรม"
  ///
  /// แยกจากปุ่มหลักสีฟ้าเพื่อไม่ให้แย่งความสำคัญกับปุ่มลงมือทำหลักของหน้า
  static ButtonStyle dark(BuildContext context) => FilledButton.styleFrom(
        backgroundColor: AppColors.dark,
        foregroundColor: Colors.white,
        textStyle: Theme.of(context).textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      );

  /// ปุ่มทำลาย (ลบ/ยกเลิก) แบบมีขอบ — ตัวอักษรและขอบเป็นสีแดงสถานะ
  static ButtonStyle danger(BuildContext context) => OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.danger,
        side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
        textStyle: Theme.of(context).textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      );
}

/// ปุ่มไอคอนทรงกล่องขอบเทา (แก้ไข / ลบ / QR) ที่ใช้ในตารางและรายการ
///
/// เดิมแต่ละหน้าใช้ [IconButton] เปล่า ๆ ซึ่งไม่มีขอบเลยกลืนไปกับแถว
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
    this.size = 32,
  });

  final IconData icon;

  /// คำอธิบายปุ่ม — บังคับใส่ เพราะปุ่มมีแต่ไอคอนจึงต้องมีข้อความกำกับเสมอ
  final String tooltip;

  final VoidCallback? onPressed;

  /// ปุ่มทำลาย (ลบ) — ไอคอนแดงและขอบชมพูอ่อน
  final bool danger;

  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = danger ? AppColors.danger : AppColors.sub;
    final borderColor = danger ? const Color(0xFFF1CBC9) : AppColors.line;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: enabled ? borderColor : AppColors.line),
              borderRadius: BorderRadius.circular(AppRadius.field),
            ),
            child: Icon(
              icon,
              size: size * 0.5,
              color: enabled ? foreground : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
