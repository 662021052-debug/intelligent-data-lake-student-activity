import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
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

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  if (_enableSemantics) binding.ensureSemantics();
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
        listenable: authService,
        builder: (context, _) {
          return authService.isLoggedIn ? const HomeScreen() : const LoginScreen();
        },
      ),
    );
  }
}
