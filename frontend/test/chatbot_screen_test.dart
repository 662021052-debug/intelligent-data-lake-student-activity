import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:activity_tracking_frontend/screens/chatbot_screen.dart';

void main() {
  testWidgets('ChatbotScreen renders greeting, quick prompts and composer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChatbotScreen()));

    // AppBar title
    expect(find.text('ผู้ช่วยอัจฉริยะ'), findsOneWidget);
    // Quick prompt chips
    expect(find.text('ชั่วโมงของฉัน'), findsOneWidget);
    expect(find.text('ขาดหมวดไหน'), findsOneWidget);
    expect(find.text('กิจกรรมที่เปิดรับ'), findsOneWidget);
    expect(find.text('แนะนำกิจกรรม'), findsOneWidget);
    // Composer input
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
    // Greeting bubble from the assistant
    expect(find.textContaining('ผู้ช่วยอัจฉริยะ'), findsWidgets);
  });
}
