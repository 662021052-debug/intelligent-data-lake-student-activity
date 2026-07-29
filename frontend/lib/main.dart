import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

void main() {
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
