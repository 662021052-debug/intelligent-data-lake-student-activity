import 'package:activity_tracking_frontend/main.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// E5 — ปุ่มย้อนกลับต้องมีปุ่มเดียว และเป็นภาษาไทย (เดิมขึ้นคำว่า "Back")
void main() {
  testWidgets('แอปตั้งค่าภาษาไทยไว้ที่ MaterialApp', (tester) async {
    await tester.pumpWidget(const MyApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('th'));
    expect(app.localizationsDelegates, contains(GlobalMaterialLocalizations.delegate));
  });

  testWidgets('หน้าที่เปิดซ้อนมีปุ่มย้อนกลับอันเดียว และ tooltip เป็นภาษาไทย', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('th'),
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(appBar: AppBar(title: const Text('หน้าซ้อน'))),
                ),
              ),
              child: const Text('เปิด'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });
}
