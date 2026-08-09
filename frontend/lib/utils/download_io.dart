// เซฟไฟล์ที่ได้จาก API ลงเครื่องผู้ใช้ — ทำได้เฉพาะบนเว็บ
//
// โครงเดียวกับ evidence_io.dart: `dart:html` มีเฉพาะ target เว็บ การ export
// แบบมีเงื่อนไขทำให้ `flutter test` (รันบน Dart VM) ยังคอมไพล์ผ่านโดยใช้ตัว stub
export 'download_io_stub.dart' if (dart.library.html) 'download_io_web.dart';
