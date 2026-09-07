import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ตารางมาตรฐานของแอป — หัวตารางตัวเล็กสีจาง เส้นแบ่งบาง แถวโปร่ง
///
/// ทุกหน้าที่มีตารางให้ใช้ตัวนี้แทน [DataTable] ตรง ๆ เพื่อให้หน้าตาเหมือนกันหมด
/// (เดิมแต่ละหน้าเรียก DataTable เองจึงไม่มีทั้งเส้นแบ่งบางและ hover)
class AppDataTable extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
  });

  final List<DataColumn> columns;

  /// แถวข้อมูลตามลำดับที่จะแสดง — สีพื้นหลังถูกกำหนดให้อัตโนมัติ
  final List<List<DataCell>> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: columns,
          rows: [
            for (final cells in rows) DataRow(color: appRowColor(scheme), cells: cells),
          ],
        ),
      ),
    );
  }
}

/// สีพื้นหลังของแถวตาราง: โปร่งตามปกติ และเรืองฟ้าอ่อนเมื่อเมาส์ชี้
///
/// ตาม mockup แถวไม่สลับสี (zebra) แล้ว — ให้เส้นแบ่งบาง ๆ ทำหน้าที่คั่นแถวแทน
/// ซึ่งอ่านง่ายกว่าเมื่อตารางมีหลายคอลัมน์
///
/// แยกเป็นฟังก์ชันเพื่อให้ตารางที่ต้องประกอบ [DataRow] เองใช้ค่าเดียวกันได้
WidgetStateProperty<Color?> appRowColor(ColorScheme scheme) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.hovered)) {
      return AppColors.blueBg.withValues(alpha: 0.6);
    }
    return null;
  });
}

/// ธีมของ [DataTable] ทั้งแอป (หัวตารางตัวเล็กสีจาง + เส้นแบ่งบาง)
DataTableThemeData appDataTableTheme(ColorScheme scheme, TextTheme text) {
  return DataTableThemeData(
    // หัวตารางพื้นขาวเหมือนตัวการ์ด ให้ตัวอักษรจาง ๆ เป็นตัวบอกว่าเป็นหัวตาราง
    headingRowColor: const WidgetStatePropertyAll(Colors.transparent),
    headingTextStyle: text.labelSmall?.copyWith(color: AppColors.muted),
    dataTextStyle: text.bodyMedium,
    dividerThickness: 1,
    headingRowHeight: 40,
    dataRowMinHeight: 44,
    dataRowMaxHeight: 60,
    horizontalMargin: AppSpacing.lg,
    columnSpacing: AppSpacing.xl,
  );
}
