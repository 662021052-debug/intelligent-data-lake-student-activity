import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/app_data_table.dart';

/// จุดเดียวที่กำหนดหน้าตาของทั้งแอป — ทุกหน้าดึงค่าจาก `Theme.of(context)`
/// ห้าม hardcode สี/มุมโค้ง/ระยะห่างในแต่ละหน้า (ยกเว้นค่าที่มาจากที่นี่)

/// สีหลักของระบบ (indigo) ใช้เป็น seed ให้ M3 สร้าง ColorScheme ทั้งชุด
const Color kSeedColor = Color(0xFF4F46E5);

/// ระยะห่างมาตรฐาน 8 / 12 / 16 / 24 — ใช้แทนตัวเลขลอย ๆ ในหน้าต่าง ๆ
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// มุมโค้งมาตรฐาน
abstract final class AppRadius {
  static const double card = 14;
  static const double field = 12;
  static const double chip = 8;
}

/// สีสื่อความหมายของ "สถานะ" ที่ใช้ร่วมกันทั้งระบบ
///
/// อนุมัติ = เขียว, รอตรวจ = เหลือง/ส้ม, ไม่อนุมัติ = แดง, รออนุมัติ(กิจกรรม) = เทา
/// เก็บเป็นคู่ (พื้นหลังอ่อน / สีตัวอักษรเข้ม) เพื่อให้ contrast อ่านง่ายเสมอ
class StatusPalette {
  const StatusPalette(this.background, this.foreground);

  final Color background;
  final Color foreground;

  static const StatusPalette approved = StatusPalette(Color(0xFFDCFCE7), Color(0xFF166534));
  static const StatusPalette pending = StatusPalette(Color(0xFFFEF3C7), Color(0xFF92400E));
  static const StatusPalette rejected = StatusPalette(Color(0xFFFEE2E2), Color(0xFF991B1B));
  static const StatusPalette neutral = StatusPalette(Color(0xFFE7E5E4), Color(0xFF44403C));
  static const StatusPalette info = StatusPalette(Color(0xFFE0E7FF), Color(0xFF3730A3));
}

abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(seedColor: kSeedColor);
    // ฟอนต์ไทยอ่านง่าย ใช้เป็น default ทั้งแอป (ตัวเลข/ภาษาไทยคมกว่าฟอนต์ระบบ)
    final baseText = GoogleFonts.notoSansThaiTextTheme(
      ThemeData(colorScheme: colorScheme).textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      // ระลอกคลื่นตอนกดแบบเดียวกันทุกแพลตฟอร์ม (ค่าเริ่มต้นของ M3 บนบางแพลตฟอร์ม
      // ใช้ InkSparkle ที่ต้องโหลด shader ทำให้เอฟเฟกต์ไม่เหมือนกันบนเว็บ)
      splashFactory: InkRipple.splashFactory,
      textTheme: baseText.copyWith(
        titleLarge: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        color: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        // ชิปสถานะกำหนดสีเองผ่าน StatusChip; ค่านี้คุมรูปทรงให้เหมือนกันทั้งแอป
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
        side: BorderSide.none,
        labelStyle: baseText.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      ),
      dataTableTheme: appDataTableTheme(colorScheme, baseText),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant, space: 1),
    );
  }
}
