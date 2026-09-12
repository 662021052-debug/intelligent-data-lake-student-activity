import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/app_data_table.dart';

/// จุดเดียวที่กำหนดหน้าตาของทั้งแอป — ทุกหน้าดึงค่าจาก `Theme.of(context)`
/// ห้าม hardcode สี/มุมโค้ง/ระยะห่างในแต่ละหน้า (ยกเว้นค่าที่มาจากที่นี่)
///
/// ธีมประจำมหาวิทยาลัยทักษิณ: เทา–ฟ้า ฟอนต์ Sarabun ตาม mockup ที่อนุมัติแล้ว

/// สีดิบตาม design token ของ mockup — ใช้เมื่อ [ColorScheme] ไม่มี role ที่ตรงความหมาย
///
/// ปกติให้หยิบจาก `Theme.of(context).colorScheme` ก่อนเสมอ ค่าที่นี่มีไว้สำหรับ
/// จุดที่ M3 ไม่มีชื่อเรียก เช่น พื้นหลังหน้า หรือปุ่มสีเข้มของใบประมวลผล
abstract final class AppColors {
  /// ฟ้าหลักประจำมหาวิทยาลัย
  static const Color blue = Color(0xFF1C6EB4);

  /// ฟ้าเข้ม — สถานะ hover / เมนูที่เปิดอยู่
  static const Color blueDark = Color(0xFF155189);

  /// ฟ้าอ่อน — พื้นหลังอ่อน ๆ ของชิป/ไอคอน
  static const Color blueBg = Color(0xFFE8F1FA);

  /// ตัวอักษรบนพื้นน้ำเงินเข้มของเมนู sidebar — ขาวอมฟ้า อ่านสบายแต่ไม่แย่ง
  /// สายตากับเมนูที่เปิดอยู่ (ซึ่งเป็นพื้นขาวตัวฟ้า) ได้ contrast 6.6:1
  static const Color onNav = Color(0xFFDCE9F5);

  /// ตัวอักษรจางบนพื้นน้ำเงินเข้ม (หัวข้อกลุ่มเมนู) — 4.7:1 ยังผ่าน AA
  static const Color onNavMuted = Color(0xFFA9C7E4);

  /// เทารอง (secondary)
  static const Color grey = Color(0xFF5B6470);

  /// ตัวอักษรหลัก
  static const Color ink = Color(0xFF222831);

  /// ตัวอักษรรอง
  static const Color sub = Color(0xFF5B6470);

  /// ตัวอักษรจาง (หัวตาราง คำอธิบายย่อย placeholder)
  ///
  /// เข้มกว่าเทาจาง ๆ ของ mockup เล็กน้อย เพราะค่าเดิม (#98A0AB) ได้ contrast
  /// แค่ 2.6:1 บนการ์ดขาว ซึ่งตกเกณฑ์ WCAG AA สำหรับตัวอักษร — ค่านี้ได้ 4.7:1
  /// และยังจางกว่า [sub] อยู่ ลำดับความสำคัญของตัวอักษรจึงไม่เสีย
  static const Color muted = Color(0xFF6E747D);

  /// เส้นขอบ/เส้นแบ่ง (ตกแต่ง — การ์ดแยกจากพื้นหลังด้วยสีพื้นและเงาอยู่แล้ว)
  static const Color line = Color(0xFFE3E7EC);

  /// ขอบช่องกรอกข้อมูล — เข้มกว่าเส้นทั่วไปเพราะเป็นสิ่งเดียวที่บอกขอบเขตของช่อง
  /// (พื้นช่อง #F7F9FB ต่างจากการ์ดขาวแค่ 1.07:1 แทบมองไม่เห็น) ค่านี้ได้ 3.1:1
  /// ตามเกณฑ์ WCAG 1.4.11 สำหรับองค์ประกอบที่ต้องระบุตัวได้
  static const Color fieldBorder = Color(0xFF8A929C);

  /// พื้นหลังของ "หน้า" (การ์ดสีขาวลอยอยู่บนพื้นนี้)
  static const Color page = Color(0xFFEEF1F4);

  /// พื้นผิวการ์ด/แผง
  static const Color surface = Color(0xFFFFFFFF);

  /// พื้นของช่องกรอกข้อมูล/ช่องค้นหา
  static const Color fieldFill = Color(0xFFF7F9FB);

  /// ปุ่มสีเข้ม (เช่น ใบประมวลผลกิจกรรม)
  static const Color dark = Color(0xFF2A2F3A);

  static const Color success = Color(0xFF1F9D57);
  /// เข้มกว่าส้มของ mockup (#E0902B) เพราะสีเดิมได้แค่ 2.3:1 บนแถบพื้นเทา
  /// ซึ่งตกเกณฑ์ 3:1 ของกราฟิกที่สื่อความหมาย (แถบความคืบหน้า/แท่งกราฟ)
  static const Color warning = Color(0xFFBE7A1F);
  static const Color danger = Color(0xFFD6453D);
}

/// ระยะห่างมาตรฐาน 4 / 8 / 12 / 16 / 24 — ใช้แทนตัวเลขลอย ๆ ในหน้าต่าง ๆ
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// มุมโค้งมาตรฐาน
abstract final class AppRadius {
  /// การ์ด/แผง
  static const double card = 12;

  /// กรอบใหญ่ที่ห่อทั้งหน้า (frame ใน mockup)
  static const double frame = 14;

  /// ปุ่มและช่องกรอกข้อมูล
  static const double field = 8;

  /// กล่องเล็ก เช่น กรอบไอคอน แถบความคืบหน้า
  static const double chip = 8;

  /// ชิปสถานะทรงแคปซูล
  static const double pill = 999;
}

/// เงาบาง ๆ ใต้การ์ด (mockup: `0 6px 22px rgba(34,40,49,0.07)`)
const Color kCardShadowColor = Color(0x12222831);

/// สีสื่อความหมายของ "สถานะ" ที่ใช้ร่วมกันทั้งระบบ
///
/// อนุมัติ = เขียว, รอตรวจ = เหลือง/ส้ม, ไม่อนุมัติ = แดง, กลาง ๆ = เทา
/// เก็บเป็นชุดสามค่า:
/// - [background] พื้นอ่อนของชิป
/// - [foreground] สีตัวอักษรบนพื้นอ่อนนั้น (เข้มพอให้ contrast ผ่านเสมอ)
/// - [accent] สีทึบของแบรนด์สถานะนั้น สำหรับแถบ/จุด/กราฟที่ไม่มีตัวอักษรทับ
class StatusPalette {
  const StatusPalette(this.background, this.foreground, this.accent);

  final Color background;
  final Color foreground;
  final Color accent;

  static const StatusPalette approved =
      StatusPalette(Color(0xFFE4F5EC), Color(0xFF146B3A), AppColors.success);
  static const StatusPalette pending =
      StatusPalette(Color(0xFFFCF1DE), Color(0xFF8A5A11), AppColors.warning);
  static const StatusPalette rejected =
      StatusPalette(Color(0xFFFBE7E6), Color(0xFF9B2C27), AppColors.danger);
  // ตัวอักษรเข้มกว่าเทาของ mockup (#6B7280) เล็กน้อย — ค่าเดิมได้ 4.2:1
  // บนพื้นชิป ซึ่งยังไม่ถึง 4.5:1 ตามเกณฑ์ AA
  static const StatusPalette neutral =
      StatusPalette(Color(0xFFEEF0F3), Color(0xFF626976), AppColors.muted);
  static const StatusPalette info =
      StatusPalette(AppColors.blueBg, AppColors.blueDark, AppColors.blue);
}

/// สีหลักของระบบ ใช้เป็น seed ให้ M3 สร้าง ColorScheme ทั้งชุด
const Color kSeedColor = AppColors.blue;

abstract final class AppTheme {
  /// ColorScheme ของแอป — สร้างจาก seed แล้ว "ตรึง" role ที่ mockup กำหนดไว้ชัดเจน
  ///
  /// ที่ต้อง copyWith เพราะ M3 คำนวณโทนเองจาก seed ซึ่งจะเพี้ยนจากสีประจำ
  /// มหาวิทยาลัยไปเล็กน้อย role ที่เหลือ (เช่น tertiary) ปล่อยให้ M3 จัดการต่อ
  static ColorScheme get colorScheme => ColorScheme.fromSeed(
        seedColor: kSeedColor,
      ).copyWith(
        primary: AppColors.blue,
        onPrimary: Colors.white,
        primaryContainer: AppColors.blueBg,
        onPrimaryContainer: AppColors.blueDark,
        secondary: AppColors.grey,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.page,
        onSecondaryContainer: AppColors.ink,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        onSurfaceVariant: AppColors.sub,
        surfaceContainerLowest: AppColors.fieldFill,
        surfaceContainerLow: AppColors.fieldFill,
        surfaceContainer: AppColors.page,
        surfaceContainerHigh: AppColors.page,
        surfaceContainerHighest: AppColors.page,
        outline: AppColors.muted,
        outlineVariant: AppColors.line,
        error: AppColors.danger,
        onError: Colors.white,
        errorContainer: StatusPalette.rejected.background,
        onErrorContainer: StatusPalette.rejected.foreground,
      );

  static ThemeData get light {
    final colorScheme = AppTheme.colorScheme;
    final baseText = _textTheme(colorScheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // การ์ดสีขาวลอยอยู่บนพื้นเทาอ่อน — ไม่ใช่ขาวบนขาวแบบเดิม
      scaffoldBackgroundColor: AppColors.page,
      // ระลอกคลื่นตอนกดแบบเดียวกันทุกแพลตฟอร์ม (ค่าเริ่มต้นของ M3 บนบางแพลตฟอร์ม
      // ใช้ InkSparkle ที่ต้องโหลด shader ทำให้เอฟเฟกต์ไม่เหมือนกันบนเว็บ)
      splashFactory: InkRipple.splashFactory,
      textTheme: baseText,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: colorScheme.onSurface,
        // ไม่ให้ M3 ย้อมพื้นขาวเป็นฟ้าจาง ๆ ตอนเลื่อน — แถบบนต้องขาวสนิทตาม mockup
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: const Border(bottom: BorderSide(color: AppColors.line)),
        titleTextStyle: baseText.titleMedium?.copyWith(color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        color: AppColors.surface,
        shadowColor: kCardShadowColor,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fieldFill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: baseText.bodyMedium?.copyWith(color: AppColors.muted),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
        border: _fieldBorder(AppColors.fieldBorder),
        enabledBorder: _fieldBorder(AppColors.fieldBorder),
        focusedBorder: _fieldBorder(AppColors.blue, width: 1.6),
        errorBorder: _fieldBorder(AppColors.danger),
        focusedErrorBorder: _fieldBorder(AppColors.danger, width: 1.6),
      ),
      chipTheme: ChipThemeData(
        // ชิปสถานะกำหนดสีเองผ่าน StatusChip; ค่านี้คุมรูปทรงให้เหมือนกันทั้งแอป
        shape: const StadiumBorder(),
        side: BorderSide.none,
        labelStyle: baseText.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _primaryButtonStyle(baseText)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          textStyle: baseText.labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          textStyle: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.blue,
          textStyle: baseText.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.frame)),
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      ),
      dataTableTheme: appDataTableTheme(colorScheme, baseText),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
      dividerTheme: const DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.blue,
        linearTrackColor: AppColors.page,
      ),
      iconTheme: const IconThemeData(color: AppColors.sub),
    );
  }

  /// Sarabun ทั้งแอป (400/500/600/700) ขนาดกระชับกว่าค่าเริ่มต้นของ Material
  /// เล็กน้อยเพื่อให้ความหนาแน่นเท่า mockup
  static TextTheme _textTheme(ColorScheme colorScheme) {
    final base = GoogleFonts.sarabunTextTheme(
      ThemeData(colorScheme: colorScheme).textTheme,
    ).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

    return base.copyWith(
      titleLarge: base.titleLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      titleMedium: base.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 15),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 13.5),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12),
      labelLarge: base.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: base.labelSmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: color, width: width),
      );

  /// ปุ่มหลัก: พื้นฟ้า ตัวอักษรขาว มุมโค้ง 8
  static ButtonStyle _primaryButtonStyle(TextTheme text) => FilledButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.line,
        disabledForegroundColor: AppColors.muted,
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      );
}
