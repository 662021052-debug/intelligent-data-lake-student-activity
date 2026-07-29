import 'package:activity_tracking_frontend/screens/chatbot_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/typing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app() => MaterialApp(theme: AppTheme.light, home: const ChatbotScreen());

void main() {
  testWidgets('ข้อความบอทมี avatar และอยู่ชิดซ้าย', (tester) async {
    await tester.pumpWidget(_app());

    expect(find.byIcon(Icons.smart_toy), findsOneWidget);

    // ฟองข้อความทักทายของบอทต้องเริ่มจากขอบซ้ายของพื้นที่แชต
    final greeting = find.textContaining('ผู้ช่วยอัจฉริยะ 🤖');
    expect(greeting, findsOneWidget);
    final bubbleLeft = tester.getTopLeft(greeting).dx;
    final listCenter = tester.getCenter(find.byType(ListView)).dx;
    expect(bubbleLeft, lessThan(listCenter));
  });

  testWidgets('คำถามลัดเป็นชิปกดได้ และช่องพิมพ์อยู่ล่างสุดของหน้า', (tester) async {
    await tester.pumpWidget(_app());

    expect(find.text('คำถามที่ถามบ่อย'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(4));

    // ช่องพิมพ์ต้องอยู่ใต้ทั้งพื้นที่แชตและแถวคำถามลัด
    final composerTop = tester.getTopLeft(find.byType(TextField)).dy;
    final chipTop = tester.getTopLeft(find.byType(ActionChip).first).dy;
    final listTop = tester.getTopLeft(find.byType(ListView)).dy;
    expect(composerTop, greaterThan(chipTop));
    expect(chipTop, greaterThan(listTop));
  });

  testWidgets('กดชิปแล้วคำถามขึ้นเป็นข้อความของผู้ใช้ ชิดขวา', (tester) async {
    await tester.pumpWidget(_app());

    await tester.tap(find.text('ชั่วโมงของฉัน'));
    await tester.pump();

    // คำถามของผู้ใช้ถูกเพิ่มเข้าไปในบทสนทนา และอยู่ฝั่งขวา (ต่างจากฟองของบอท)
    final question = find.text('ฉันได้กี่ชั่วโมงแล้ว');
    expect(question, findsOneWidget);
    expect(
      tester.getTopRight(question).dx,
      greaterThan(tester.getCenter(find.byType(ListView)).dx),
    );

    // ปล่อยให้ request (ที่ล้มเหลวในเทสต์) จบก่อนปิดหน้าจอ
    await tester.pumpAndSettle();
  });

  testWidgets('TypingIndicator: จุดสามจุด + บอกโปรแกรมอ่านหน้าจอว่ากำลังพิมพ์', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: TypingIndicator())),
    ));

    expect(find.bySemanticsLabel('กำลังพิมพ์'), findsOneWidget);
    expect(find.byType(Container), findsNWidgets(3));

    // จุดกระพริบไล่เฟสกัน → ความจางของแต่ละจุดต้องไม่เท่ากัน
    await tester.pump(const Duration(milliseconds: 200));
    final opacities =
        tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity).toSet();
    expect(opacities.length, greaterThan(1));

    semantics.dispose();
  });
}
