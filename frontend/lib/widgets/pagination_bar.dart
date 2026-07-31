import 'package:flutter/material.dart';

/// แถบแบ่งหน้าแบบเดียวกันทุกหน้า list — "1-50 จาก 104" + ปุ่มหน้าก่อน/ถัดไป
///
/// เดิมแต่ละหน้าเขียนโค้ดชุดนี้ซ้ำเอง ทำให้หน้าที่ลืมเขียน (เช่นจัดการผู้ใช้)
/// ต้องยิงขอข้อมูลทั้งหมดในครั้งเดียวจนชน limit ของ backend
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.skip,
    required this.limit,
    required this.total,
    required this.onChanged,
  });

  /// ลำดับรายการแรกของหน้านี้ (0 = หน้าแรก)
  final int skip;

  /// จำนวนรายการต่อหน้า
  final int limit;

  /// จำนวนรายการทั้งหมดจาก backend
  final int total;

  /// เรียกพร้อมค่า skip ใหม่เมื่อผู้ใช้เปลี่ยนหน้า
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final start = total == 0 ? 0 : skip + 1;
    final end = (skip + limit) > total ? total : (skip + limit);
    final hasPrev = skip > 0;
    final hasNext = (skip + limit) < total;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$start-$end จาก $total'),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'หน้าก่อนหน้า',
            onPressed: hasPrev ? () => onChanged((skip - limit).clamp(0, total)) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'หน้าถัดไป',
            onPressed: hasNext ? () => onChanged(skip + limit) : null,
          ),
        ],
      ),
    );
  }
}
