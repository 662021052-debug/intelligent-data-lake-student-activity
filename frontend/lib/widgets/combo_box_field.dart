import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ช่องกรอกที่มีรายการให้เลือก แต่ยัง **พิมพ์ค่าใหม่ได้**
///
/// ใช้กับข้อมูลที่ "ส่วนใหญ่ซ้ำของเดิม แต่ของใหม่ต้องเพิ่มได้" เช่นชื่อคณะ —
/// dropdown ล้วนจะกรอกคณะที่ยังไม่มีนิสิตไม่ได้เลย ส่วนช่องพิมพ์ล้วนก็ทำให้ชื่อ
/// คณะเดียวกันสะกดต่างกันจนกรองไม่เจอ
///
/// สร้างบน [RawAutocomplete] แทน `DropdownMenu` ของ M3 โดยตั้งใจ เพื่อให้ช่องที่
/// เห็นเป็น [TextFormField] ที่รับ [decoration] กับ [validator] ของฟอร์มได้ตรง ๆ
/// หน้าตาและการตรวจความถูกต้องจึงเหมือนช่องอื่นในฟอร์มเดียวกันทุกประการ
class ComboBoxField extends StatefulWidget {
  const ComboBoxField({
    super.key,
    required this.controller,
    required this.options,
    required this.decoration,
    this.validator,
    this.maxVisibleOptions = 6,
  });

  final TextEditingController controller;

  /// ตัวเลือกที่มีอยู่แล้ว — ว่างได้ (ยังพิมพ์เองได้ตามปกติ)
  final List<String> options;
  final InputDecoration decoration;
  final String? Function(String?)? validator;

  /// จำกัดความสูงของรายการ ไม่ให้บังฟอร์มทั้งหน้าเมื่อมีตัวเลือกเยอะ
  final int maxVisibleOptions;

  @override
  State<ComboBoxField> createState() => _ComboBoxFieldState();
}

class _ComboBoxFieldState extends State<ComboBoxField> {
  // เป็นของ State ไม่ใช่สร้างใหม่ทุกครั้งที่ build — ไม่งั้นโฟกัสจะหลุดทุกครั้งที่
  // ฟอร์มวาดใหม่ (เช่น ตอนพิมพ์รหัสนิสิตแล้วปุ่มเติมอีเมลเปลี่ยนสถานะ)
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return widget.options;
        return widget.options.where((o) => o.toLowerCase().contains(query));
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: widget.decoration,
          validator: widget.validator,
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, opts) {
        final items = opts.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(AppRadius.field),
            child: ConstrainedBox(
              // ความสูงคิดจากจำนวนแถวที่ยอมให้เห็น ไม่ใช่ค่าคงที่ รายการสั้น ๆ
              // จะได้ไม่มีที่ว่างห้อยอยู่ข้างล่าง
              constraints: BoxConstraints(
                maxHeight: (widget.maxVisibleOptions * 48).toDouble(),
                maxWidth: 420,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: items.length,
                itemBuilder: (context, index) => ListTile(
                  dense: true,
                  title: Text(items[index]),
                  onTap: () => onSelected(items[index]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
