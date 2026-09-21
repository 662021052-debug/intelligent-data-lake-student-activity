{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // ฟอนต์สำรองของ engine (✓ อีโมจิ ไทยนอก Sarabun) เสิร์ฟจากเซิร์ฟเวอร์เราเอง
    // แทน https://fonts.gstatic.com/s/ — เครือข่ายที่บล็อก Google จะไม่เห็นกล่องสี่เหลี่ยม
    // รายละเอียด/วิธีอัปเดตไฟล์: web/fonts/gstatic/README.md
    // ต้องอิง <base href> ไม่ใช่ราก "/" — ใต้ --base-href /662021052/ ค่า "/fonts/gstatic/" จะชี้
    // ออกนอกโฟลเดอร์แอปแล้ว 404 ทุกไฟล์ (ตัวอักษรที่ไม่ใช่ Sarabun กลายเป็นช่องว่าง)
    // document.baseURI = URL ของหน้าที่ประมวลผล <base href> แล้ว จึงได้ /662021052/fonts/gstatic/
    fontFallbackBaseUrl: new URL("fonts/gstatic/", document.baseURI).href,
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
