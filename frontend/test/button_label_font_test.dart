import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ป้ายปุ่มต้องใช้ Sarabun (ฟอนต์ที่ฝังในบันเดิลและมีอักษรไทยครบ) เสมอ
///
/// Material ครอบป้ายปุ่มด้วย `DefaultTextStyle` ที่ *แทนที่* ไม่ใช่ merge — ถ้า ButtonStyle
/// ระบุ `textStyle: TextStyle(fontSize: …)` ดิบ ๆ ที่ไม่มี fontFamily ป้ายจะตกไปใช้ Roboto ซึ่งไม่มี
/// อักษรไทย แล้วต้องพึ่งฟอนต์สำรองที่โหลดจากเซิร์ฟเวอร์ตอนรัน ถ้าโหลดไม่ได้ (404 ใต้ sub-path,
/// เครือข่ายบล็อก Google) ปุ่มจะเหลือแต่ไอคอน เทสต์ widget จับไม่ได้เพราะมีฟอนต์ให้ครบเสมอ
/// จึงต้องกันที่ต้นทาง: ห้ามมี TextStyle ดิบใน textStyle/labelStyle ของปุ่มและชิป
void main() {
  test('ไม่มี TextStyle ดิบ (ไม่มี fontFamily) ใน textStyle/labelStyle ของปุ่ม/ชิป', () {
    final raw = RegExp(
      r'(textStyle|labelStyle)\s*:\s*(const\s+)?(WidgetStatePropertyAll\(\s*)?(const\s+)?TextStyle\(',
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (raw.hasMatch(lines[i])) offenders.add('${entity.path}:${i + 1}  ${lines[i].trim()}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'สืบจากธีมแทน: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: …)',
    );
  });

  test('fontFallbackBaseUrl อิง <base href> ไม่ฮาร์ดโค้ดราก "/"', () {
    final js = File('web/flutter_bootstrap.js').readAsStringSync();
    final config = RegExp(r'^\s*fontFallbackBaseUrl\s*:\s*(.+),\s*$', multiLine: true).firstMatch(js);
    expect(config, isNotNull, reason: 'ต้องตั้ง fontFallbackBaseUrl (ฟอนต์สำรอง self-host)');
    final value = config!.group(1)!;
    expect(value, contains('document.baseURI'));
    expect(value.trim().startsWith('"/'), isFalse, reason: '"/fonts/…" จะ 404 ใต้ --base-href /662021052/');
  });
}
