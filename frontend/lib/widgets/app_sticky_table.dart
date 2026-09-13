import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_data_table.dart';

/// หนึ่งแถวของ [AppStickyTable] — แยกเป็นสองฝั่งตามที่ตารางแบ่ง
class StickyRow {
  const StickyRow({required this.scrollable, required this.pinned});

  /// เซลล์ฝั่งซ้ายที่เลื่อนแนวนอนได้
  final List<DataCell> scrollable;

  /// เซลล์ฝั่งขวาที่ตรึงไว้ให้เห็นเสมอ
  final List<DataCell> pinned;
}

/// ตารางที่ "ตรึงคอลัมน์ขวาไว้" ส่วนคอลัมน์ที่เหลือเลื่อนแนวนอนได้
///
/// [AppDataTable] ปกติห่อทั้งตารางไว้ใน scroll แนวนอนก้อนเดียว พอคอลัมน์เยอะเข้า
/// คอลัมน์ท้าย ๆ (สถานะ/ปุ่มจัดการ) จะหลุดออกนอกจอ ผู้ใช้ต้องเลื่อนไปขวาทุกครั้งที่
/// อยากกดปุ่มสักปุ่ม ตัวนี้แยกเป็นสองตารางวางชิดกัน ฝั่งขวาจึงอยู่กับที่เสมอ
///
/// **ความสูงของแถวถูกล็อกให้เท่ากันทั้งสองฝั่ง** ([rowHeight]) เพราะสองตารางคำนวณ
/// ความสูงเองแยกกัน ถ้าปล่อยให้ยืดตามเนื้อหา แถวซ้าย-ขวาจะเหลื่อมกันทันทีที่ฝั่งใด
/// ฝั่งหนึ่งมีเนื้อหาสูงกว่า — เซลล์จึงควรเป็นบรรทัดเดียว (ตัดด้วย ellipsis ถ้ายาว)
class AppStickyTable extends StatefulWidget {
  const AppStickyTable({
    super.key,
    required this.scrollableColumns,
    required this.pinnedColumns,
    required this.rows,
    this.rowHeight = 56,
  });

  final List<DataColumn> scrollableColumns;
  final List<DataColumn> pinnedColumns;
  final List<StickyRow> rows;
  final double rowHeight;

  @override
  State<AppStickyTable> createState() => _AppStickyTableState();
}

class _AppStickyTableState extends State<AppStickyTable> {
  final ScrollController _horizontal = ScrollController();

  /// แถวที่เมาส์ชี้อยู่ — เก็บไว้ที่เดียวเพื่อให้สองฝั่งไฮไลต์พร้อมกัน
  ///
  /// ถ้าปล่อยให้ DataTable แต่ละตัวจัดการ hover ของตัวเอง จะเห็นครึ่งแถวสว่าง
  /// อีกครึ่งไม่สว่าง ซึ่งอ่านแล้วเหมือนตารางพัง
  int? _hovered;

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  DataRow _row(int index, List<DataCell> cells, ColorScheme scheme) {
    return DataRow(
      color: WidgetStatePropertyAll(
        index == _hovered ? AppColors.blueBg.withValues(alpha: 0.6) : null,
      ),
      cells: [
        for (final cell in cells)
          DataCell(
            MouseRegion(
              onEnter: (_) => _setHovered(index),
              onExit: (_) => _setHovered(null),
              // กินพื้นที่เซลล์ทั้งช่องเพื่อให้ชี้ตรงไหนของแถวก็ติด ไม่ใช่ติดเฉพาะบนตัวอักษร
              child: SizedBox(
                height: widget.rowHeight,
                child: Align(alignment: Alignment.centerLeft, child: cell.child),
              ),
            ),
          ),
      ],
    );
  }

  void _setHovered(int? index) {
    if (_hovered == index) return;
    setState(() => _hovered = index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = DataTableThemeData(
      dataRowMinHeight: widget.rowHeight,
      dataRowMaxHeight: widget.rowHeight,
    );

    return Theme(
      data: Theme.of(context).copyWith(
        dataTableTheme: Theme.of(context).dataTableTheme.copyWith(
              dataRowMinHeight: locked.dataRowMinHeight,
              dataRowMaxHeight: locked.dataRowMaxHeight,
            ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Scrollbar(
              controller: _horizontal,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: widget.scrollableColumns,
                  rows: [
                    for (var i = 0; i < widget.rows.length; i++)
                      _row(i, widget.rows[i].scrollable, scheme),
                  ],
                ),
              ),
            ),
          ),
          // เส้นคั่น + เงาบาง ๆ บอกว่าฝั่งขวาลอยอยู่เหนือเนื้อหาที่เลื่อนผ่านไปข้างหลัง
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(left: BorderSide(color: AppColors.line)),
              boxShadow: [
                BoxShadow(color: kCardShadowColor, blurRadius: 8, offset: Offset(-2, 0)),
              ],
            ),
            child: DataTable(
              columns: widget.pinnedColumns,
              rows: [
                for (var i = 0; i < widget.rows.length; i++)
                  _row(i, widget.rows[i].pinned, scheme),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// จำกัดความกว้างของเซลล์ + ตัดด้วย ellipsis และบอกข้อความเต็มตอนชี้เมาส์
///
/// คอลัมน์อย่าง "หมวดชั่วโมง" มีชื่อเกณฑ์ยาวเป็นประโยค ถ้าปล่อยตามเนื้อหา คอลัมน์
/// เดียวกินความกว้างจนคอลัมน์อื่นถูกดันหลุดจอ
class TruncatedCell extends StatelessWidget {
  const TruncatedCell(this.text, {super.key, this.maxWidth = 160, this.style});

  final String text;
  final double maxWidth;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 400),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      ),
    );
  }
}

/// ความกว้างคงที่ของเซลล์วันที่ — พอสำหรับวันที่ยาวสุด "30 มิ.ย. 2570" ด้วยฟอนต์ Sarabun
/// พร้อมเผื่อที่
const kThaiDateCellWidth = 112.0;

/// เซลล์วันที่ พ.ศ. (เช่น "1 ก.พ. 2570") — กว้างคงที่ บรรทัดเดียว
///
/// ห้ามปล่อยให้คอลัมน์กว้างตามเนื้อหา: DataTable วัดความกว้างคอลัมน์จากข้อความตอนวาดครั้ง
/// แรก ซึ่งบนเว็บฟอนต์ Sarabun (google_fonts) ยังโหลดไม่เสร็จ จึงวัดด้วยฟอนต์สำรองที่แคบกว่า
/// พอ Sarabun มาถึงตัวอักษรกว้างขึ้นแต่คอลัมน์ไม่ขยายตาม ปี พ.ศ. ท้ายข้อความเลยถูกตัด
/// เหลือ "1 ก.พ. 25" — ความกว้างคงที่ไม่ขึ้นกับว่าวัดตอนฟอนต์ไหน
class ThaiDateCell extends StatelessWidget {
  const ThaiDateCell(this.text, {super.key, this.tooltip, this.style});

  final String text;

  /// ข้อความเต็มตอนชี้ (เช่นวันที่พร้อมเวลา)
  final String? tooltip;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cell = SizedBox(
      width: kThaiDateCellWidth,
      child: Text(text, maxLines: 1, softWrap: false, style: style),
    );
    return tooltip == null ? cell : Tooltip(message: tooltip, child: cell);
  }
}

/// เซลล์ตัวเลขแคบ ๆ (ชั่วโมง / รับสูงสุด) — กว้างพอสำหรับเลขไม่กี่หลักเท่านั้น
class NarrowCell extends StatelessWidget {
  const NarrowCell(this.child, {super.key, this.width = 44});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: child);
}
