#!/usr/bin/env python3
"""เสิร์ฟ build/web สำหรับ dev โดยไม่ให้เบราว์เซอร์ cache อะไรเลย

ปัญหาที่แก้: Flutter web ลงทะเบียน service worker ที่ cache `main.dart.js` ไว้แรงมาก
พอ rebuild แล้ว reload ธรรมดา เบราว์เซอร์ยังเสิร์ฟ bundle เก่าอยู่ — ทำให้ไล่บั๊กผิดตัว
(เคสจริง: หน้าจัดการผู้ใช้ยังยิง limit=500 ทั้งที่โค้ดแก้ไปแล้ว 2 รอบ)

สคริปต์นี้ทำ 2 อย่าง:
  1. ใส่ Cache-Control: no-store ทุก response — reload ธรรมดาก็ได้ของใหม่เสมอ
  2. เสิร์ฟ flutter_service_worker.js เป็นสคริปต์ "ฆ่าตัวเอง" ที่ unregister ตัวเอง
     แล้วล้าง cache ทิ้ง — service worker ตัวเก่าที่ค้างอยู่ในเบราว์เซอร์จะหายไปเอง
     ตอนที่เบราว์เซอร์เช็คอัปเดต โดยผู้ใช้ไม่ต้องเข้าไป unregister เองใน DevTools

ใช้:  python frontend/devserver.py [port]     (ค่าเริ่มต้น 8080)
"""

import functools
import http.server
import os
import socketserver
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")

# service worker ที่ทำลายตัวเอง: ถอนการลงทะเบียน ล้าง cache แล้วบังคับให้หน้าที่
# เปิดค้างอยู่โหลดใหม่ — เสิร์ฟที่ URL เดิมของ Flutter เพื่อ "กลบ" ตัวเก่าที่ค้าง
SELF_DESTRUCT_SW = b"""// dev: self-destructing service worker (see devserver.py)
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) {
      client.navigate(client.url);
    }
  })());
});
"""


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def send_response(self, *args, **kwargs):
        super().send_response(*args, **kwargs)
        # no-store สำคัญกว่า no-cache: no-cache ยังเก็บไว้แล้วถาม revalidate
        # ซึ่งยังพลาดได้ถ้า response ไม่มี validator
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")

    def do_GET(self):
        if self.path.split("?")[0].endswith("flutter_service_worker.js"):
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript")
            self.send_header("Content-Length", str(len(SELF_DESTRUCT_SW)))
            self.end_headers()
            self.wfile.write(SELF_DESTRUCT_SW)
            return
        super().do_GET()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


class ReusableServer(socketserver.TCPServer):
    allow_reuse_address = True


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    if not os.path.isdir(ROOT):
        sys.exit("ไม่พบ %s — รัน `flutter build web` ก่อน" % ROOT)
    handler = functools.partial(NoCacheHandler, directory=ROOT)
    with ReusableServer(("127.0.0.1", port), handler) as httpd:
        print("serving %s at http://localhost:%d (no-store, SW self-destruct)" % (ROOT, port))
        httpd.serve_forever()


if __name__ == "__main__":
    main()
