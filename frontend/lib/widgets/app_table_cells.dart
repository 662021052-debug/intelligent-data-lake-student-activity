import 'package:flutter/material.dart';

/// ข้อความในเซลล์ตาราง — บรรทัดเดียว ตัดด้วย ellipsis และบอกข้อความเต็มตอนชี้เมาส์
///
/// [maxWidth] จำกัดความกว้างเองเมื่อคอลัมน์กว้างตามเนื้อหา · คอลัมน์ที่ความกว้างมาจากตาราง
/// แล้ว (flex) ส่ง `double.infinity` — ตารางเป็นคนกำหนดขอบ ข้อความยาวก็ตัดตามขอบนั้น
class TruncatedCell extends StatelessWidget {
  const TruncatedCell(this.text, {super.key, this.maxWidth = 160, this.style, this.tooltip});

  final String text;
  final double maxWidth;
  final TextStyle? style;

  /// ข้อความใน tooltip (ค่าเริ่มต้น = [text])
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? text,
      waitDuration: const Duration(milliseconds: 400),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

/// ความกว้างคงที่ของเซลล์วันที่ — วัดด้วยฟอนต์ Sarabun ไฟล์จริงที่ 13.5px วันที่ยาวสุด
/// ("28 เม.ย. 2570") กว้าง 78.1px จึงเผื่อไว้ราว 18px
const kThaiDateCellWidth = 96.0;

/// ความกว้างจริงของวันที่ยาวสุดด้วย Sarabun 13.5px (วัดจากไฟล์ฟอนต์จริง) — ใช้ในเทสกันเผลอลด
/// [kThaiDateCellWidth] จนตัดปี
const kThaiDateWidestMeasured = 78.11;

/// เซลล์วันที่ พ.ศ. (เช่น "1 ก.พ. 2570") — กว้างคงที่ บรรทัดเดียว
///
/// ห้ามปล่อยให้กว้างตามเนื้อหา: DataTable วัดความกว้างจากข้อความตอนวาดครั้งแรก ซึ่งบนเว็บ
/// ฟอนต์ Sarabun (google_fonts) ยังโหลดไม่เสร็จ จึงวัดด้วยฟอนต์สำรองที่แคบกว่า — ความกว้าง
/// คงที่ไม่ขึ้นกับว่าวัดตอนฟอนต์ไหน
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

/// หัวคอลัมน์ของตารางที่กำหนดความกว้างคอลัมน์เอง (columnWidth) — หดและตัด … แทนการล้น
///
/// DataTable วางป้ายหัวคอลัมน์เป็นลูกตรงของ [Row] ที่ไม่หด ป้ายที่กว้างกว่าคอลัมน์จึงล้นทับ
/// คอลัมน์ข้าง ๆ — เป็น [Flexible] เองจึงหดตามคอลัมน์ได้ (แนวเดียวกับหัวตารางกิจกรรม)
class TableColumnLabel extends Flexible {
  TableColumnLabel(this.text, {super.key})
      : super(
          child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
        );

  /// ข้อความหัวคอลัมน์ (ใช้อ้างถึงคอลัมน์ในเทส)
  final String text;
}

/// เซลล์ตัวเลขแคบ ๆ (ชั่วโมง) — กว้างพอสำหรับเลขไม่กี่หลักเท่านั้น
class NarrowCell extends StatelessWidget {
  const NarrowCell(this.child, {super.key, this.width = 44});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: child);
}
