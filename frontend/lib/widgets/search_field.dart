import 'dart:async';

import 'package:flutter/material.dart';

/// ช่องค้นหาที่พิมพ์แล้วผลขึ้นเอง ไม่ต้องกด Enter
///
/// หน่วง [debounce] สั้น ๆ ก่อนเรียก [onSearch] เพื่อไม่ให้ยิง API ทุกตัวอักษร
/// (กด Enter หรือกดล้างคำค้นหา = ค้นทันทีไม่ต้องรอ)
/// ค่าที่ส่งให้ [onSearch] ผ่าน trim มาแล้ว และจะไม่ส่งซ้ำถ้าคำค้นหาไม่เปลี่ยน
class DebouncedSearchField extends StatefulWidget {
  final String label;
  final ValueChanged<String> onSearch;
  final double width;
  final Duration debounce;

  const DebouncedSearchField({
    super.key,
    required this.label,
    required this.onSearch,
    this.width = 260,
    this.debounce = const Duration(milliseconds: 350),
  });

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _applied = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // อัปเดตปุ่มล้างคำค้นหา
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () => _apply(value));
  }

  void _apply(String value) {
    _debounce?.cancel();
    final next = value.trim();
    if (next == _applied) return;
    _applied = next;
    widget.onSearch(next);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          // ข้อความบอกใบ้อยู่ในช่องเลยตาม mockup (ไม่ใช่ label ลอยอยู่เหนือช่อง)
          // ช่องค้นหาสั้น ๆ ไม่ต้องมีป้ายชื่อค้างไว้ ไอคอนแว่นขยายบอกหน้าที่ชัดพอ
          hintText: widget.label,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  tooltip: 'ล้างคำค้นหา',
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                    _apply('');
                  },
                ),
        ),
        onChanged: _onChanged,
        onSubmitted: _apply,
      ),
    );
  }
}
