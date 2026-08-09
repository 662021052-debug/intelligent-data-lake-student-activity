// คอมไพล์เฉพาะ target เว็บ (เลือกผ่าน conditional export ใน download_io.dart)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// ห่อ bytes เป็น object URL แล้วสั่งดาวน์โหลดด้วยชื่อไฟล์ที่กำหนด
///
/// ใช้ `<a download>` แทนการเปิดแท็บใหม่ เพราะไฟล์ .xlsx เปิดในเบราว์เซอร์ไม่ได้อยู่ดี
/// และวิธีนี้คุมชื่อไฟล์ภาษาไทยได้เอง ไม่ต้องพึ่ง Content-Disposition ของ response
void saveBytesAsFile(Uint8List bytes, String filename, String contentType) {
  final blob = html.Blob([bytes], contentType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  // ปล่อย URL ทิ้งหลังเบราว์เซอร์เริ่มดาวน์โหลดแล้ว (revoke ทันทีทำให้ไฟล์ว่างในบางเบราว์เซอร์)
  Timer(const Duration(seconds: 30), () => html.Url.revokeObjectUrl(url));
}
