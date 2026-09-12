import 'package:flutter/material.dart';

import '../models/hour_category.dart';

/// ช่อง "หมวดชั่วโมง" ของฟอร์มกิจกรรม (แก้บั๊ก E3)
///
/// ปัญหาเดิม: ชื่อเต็ม "หมวด › หมวดย่อย" ยาวจนล้นออกนอกกรอบ dialog
/// วิธีแก้: ในช่องที่ปิดอยู่แสดง **ชื่อหมวดย่อยสั้น ๆ** บรรทัดเดียว (ellipsis ถ้ายังยาว)
/// ส่วนรายการที่กางออกมาแสดงชื่อเต็มพร้อมชื่อหมวดแม่ เพื่อให้เลือกได้ไม่สับสน
class SubcategoryDropdown extends StatelessWidget {
  const SubcategoryDropdown({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
    this.labelText = 'หมวดชั่วโมง',
    this.required = true,
  });

  final List<HourCategory> categories;
  final int? value;
  final ValueChanged<int?> onChanged;

  /// ต้องเลือกไหม — ฟอร์มกิจกรรมที่เลือกรายการเกณฑ์ชุดใหม่ได้แล้วไม่บังคับช่องนี้
  /// และเปิดตัวเลือก "ไม่ระบุ" ให้ล้างค่าที่เผลอเลือกไว้ได้
  final bool required;
  final String labelText;

  /// คู่ (หมวดแม่, หมวดย่อย) ทั้งหมด เรียงตามลำดับที่ API ส่งมา
  List<(HourCategory, HourSubcategory)> get _options => [
        for (final category in categories)
          for (final sub in category.subcategories) (category, sub),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _options;
    HourCategory? parentOfSelected;
    for (final (category, sub) in options) {
      if (sub.id == value) parentOfSelected = category;
    }

    return DropdownButtonFormField<int>(
      initialValue: value,
      // กันข้อความยาวดันความกว้าง dropdown จนล้นกรอบ dialog
      isExpanded: true,
      decoration: InputDecoration(
        labelText: labelText,
        // ชื่อหมวดแม่ย้ายมาอยู่ใต้ช่อง แทนที่จะยัดรวมในบรรทัดเดียวจนล้น
        helperText: parentOfSelected?.name ??
            (required
                ? 'เลือกหมวดย่อยที่กิจกรรมนี้นับชั่วโมงให้'
                : 'สำหรับนิสิตที่ยังไม่ผูกชุดเกณฑ์เท่านั้น'),
        helperMaxLines: 1,
      ),
      items: [
        if (!required)
          DropdownMenuItem(
            value: null,
            child: Text('— ไม่ระบุ —', style: theme.textTheme.bodyMedium),
          ),
        for (final (category, sub) in options)
          DropdownMenuItem(
            value: sub.id,
            child: Text(
              '${category.name} › ${sub.name}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
      // ช่องที่ปิดอยู่แสดงเฉพาะชื่อสั้น ไม่ใช่ path เต็ม
      selectedItemBuilder: (context) => [
        if (!required)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('— ไม่ระบุ —', style: theme.textTheme.bodyMedium),
          ),
        for (final (_, sub) in options)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              sub.name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
      onChanged: onChanged,
      validator: (v) => required && v == null ? 'กรุณาเลือกหมวดชั่วโมง' : null,
    );
  }
}
