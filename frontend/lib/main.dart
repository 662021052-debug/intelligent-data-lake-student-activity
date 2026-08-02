import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/checkin_confirm_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/pending_checkin.dart';
import 'theme/app_theme.dart';

/// เปิด semantics tree ตั้งแต่เริ่ม เพื่อให้เครื่องมืออัตโนมัติอ่านหน้าเว็บได้
///
/// Flutter web วาดทุกอย่างลง `<canvas>` (renderer html ถูกถอดออกตั้งแต่ 3.29
/// เหลือแต่ canvaskit/skwasm) เครื่องมือที่อ่าน DOM จึงไม่เห็นอะไรเลย ทางเดียว
/// ที่รองรับคือ semantics tree ซึ่ง Flutter จะสร้าง DOM จริง (`<flt-semantics>`
/// พร้อม ARIA) ให้ — แต่ปกติจะเปิดก็ต่อเมื่อตรวจพบ screen reader เท่านั้น
///
/// เปิดผ่าน --dart-define เพื่อไม่ให้ build ปกติต้องแบกค่าใช้จ่ายส่วนนี้:
///   flutter build web --dart-define=ENABLE_SEMANTICS=true
const bool _enableSemantics = bool.fromEnvironment('ENABLE_SEMANTICS');

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  if (_enableSemantics) binding.ensureSemantics();
  // กู้สถานะล็อกอินก่อน build หน้าแรก — ไม่งั้นหน้า login จะแวบขึ้นมาก่อนแล้ว
  // ค่อยสลับเป็นหน้าหลัก ทุกครั้งที่ผู้ใช้กดรีเฟรช
  await authService.restore();
  // deep link จากการสแกน QR ด้วยกล้องมือถือปกติ — ต้องอ่านตั้งแต่ตอนเปิดแอป
  // ก่อนที่หน้าไหนจะวาด (ส่งทั้ง route และ URL เต็มไปให้ ดูเหตุผลใน PendingCheckin)
  pendingCheckin.readFromAppStart(
    route: binding.platformDispatcher.defaultRouteName,
    url: Uri.base,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Intelligent Data Lake - Activity Tracking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // ทั้งแอปเป็นภาษาไทย — ปุ่ม/คำอธิบายที่ Flutter สร้างเองต้องเป็นไทยด้วย
      // (ก่อนหน้านี้ปุ่มย้อนกลับบน AppBar ขึ้นคำว่า "Back" เป็นภาษาอังกฤษ)
      locale: const Locale('th'),
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ListenableBuilder(
        // ฟังทั้งสองอย่าง: สถานะล็อกอิน และ token เช็กอินที่ค้างอยู่ — พอนิสิต
        // ล็อกอินเสร็จ ตัว builder นี้จะพาไปหน้ายืนยันเช็กอินต่อเอง token
        // จึงไม่หายระหว่างทางไปหน้า login (F4b)
        listenable: Listenable.merge([authService, pendingCheckin]),
        builder: (context, _) {
          if (!authService.isLoggedIn) return const LoginScreen();
          final token = pendingCheckin.token;
          if (token != null) {
            return CheckinConfirmScreen(token: token, onDone: pendingCheckin.clear);
          }
          return const HomeScreen();
        },
      ),
    );
  }
}
