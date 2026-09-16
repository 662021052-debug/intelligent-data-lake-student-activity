{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // ฟอนต์สำรองของ engine (✓ อีโมจิ ไทยนอก Sarabun) เสิร์ฟจากเซิร์ฟเวอร์เราเอง
    // แทน https://fonts.gstatic.com/s/ — เครือข่ายที่บล็อก Google จะไม่เห็นกล่องสี่เหลี่ยม
    // รายละเอียด/วิธีอัปเดตไฟล์: web/fonts/gstatic/README.md
    fontFallbackBaseUrl: "/fonts/gstatic/",
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
