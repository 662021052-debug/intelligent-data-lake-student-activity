import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// จุดสามจุดกระพริบไล่กัน — ใช้บอกว่าอีกฝั่งกำลังพิมพ์/กำลังคิดคำตอบอยู่
///
/// ชัดกว่าวงกลมหมุน (ซึ่งสื่อว่า "ระบบกำลังโหลด") เพราะสื่อว่ากำลังมีคนตอบอยู่
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, this.dotCount = 3, this.semanticsLabel = 'กำลังพิมพ์'});

  final int dotCount;
  final String semanticsLabel;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      // container: true เพื่อให้จุดกระพริบ (ที่ไม่มีข้อความ) มี node ของตัวเอง
      // โปรแกรมอ่านหน้าจอจะได้บอกได้ว่ากำลังรอคำตอบอยู่
      container: true,
      label: widget.semanticsLabel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.dotCount; i++)
              Padding(
                padding: EdgeInsets.only(
                  right: i == widget.dotCount - 1 ? 0 : AppSpacing.xs,
                ),
                child: Opacity(
                  // เหลื่อมเฟสกันทีละ 1/dotCount รอบ ให้เห็นเป็นคลื่นวิ่ง
                  opacity: 0.35 +
                      0.65 *
                          (0.5 +
                              0.5 *
                                  math.sin((_controller.value - i / widget.dotCount) *
                                      2 *
                                      math.pi)),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
