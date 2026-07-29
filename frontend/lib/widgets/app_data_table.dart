import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ตารางมาตรฐานของแอป — หัวตารางตัวหนา, แถวสลับสีอ่อน (zebra), hover highlight
///
/// ทุกหน้าที่มีตารางให้ใช้ตัวนี้แทน [DataTable] ตรง ๆ เพื่อให้หน้าตาเหมือนกันหมด
/// (เดิมแต่ละหน้าเรียก DataTable เองจึงไม่มีทั้ง zebra และ hover)
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
            for (final (index, cells) in rows.indexed)
              DataRow(
                color: zebraRowColor(scheme, index),
                cells: cells,
              ),
          ],
        ),
      ),
    );
  }
}

/// สีพื้นหลังของแถวที่ [index]: แถวคู่/คี่สลับสีอ่อน และเข้มขึ้นเมื่อเมาส์ชี้
///
/// แยกออกมาเป็นฟังก์ชันเพื่อให้ตารางที่ต้องประกอบ [DataRow] เองใช้ค่าเดียวกันได้
WidgetStateProperty<Color?> zebraRowColor(ColorScheme scheme, int index) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.hovered)) {
      return scheme.primaryContainer.withValues(alpha: 0.45);
    }
    return index.isEven ? null : scheme.surfaceContainerHighest.withValues(alpha: 0.4);
  });
}

/// ธีมของ [DataTable] ทั้งแอป (หัวตารางตัวหนา + ระยะห่างสม่ำเสมอ)
DataTableThemeData appDataTableTheme(ColorScheme scheme, TextTheme text) {
  return DataTableThemeData(
    headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
    headingTextStyle: text.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
    ),
    dataTextStyle: text.bodyMedium,
    dividerThickness: 0.6,
    horizontalMargin: AppSpacing.lg,
    columnSpacing: AppSpacing.xl,
  );
}
