import 'package:activity_tracking_frontend/screens/checkin_scan_screen.dart';
import 'package:activity_tracking_frontend/screens/chatbot_screen.dart';
import 'package:activity_tracking_frontend/screens/home_screen.dart';
import 'package:activity_tracking_frontend/screens/my_hours_screen.dart';
import 'package:activity_tracking_frontend/screens/activity_calendar_screen.dart';
import 'package:activity_tracking_frontend/screens/participations_screen.dart';
import 'package:activity_tracking_frontend/screens/register_activities_screen.dart';
import 'package:activity_tracking_frontend/screens/student_home_view.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/format.dart';
import 'package:activity_tracking_frontend/widgets/app_nav.dart';
import 'package:activity_tracking_frontend/widgets/app_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// หน้าจอเหล่านี้ยิง API ตอนเปิด ซึ่งในเทสต์จะล้มเหลว (ไม่มีเซิร์ฟเวอร์) —
/// ที่ตรวจคือ "โครงหน้ายังขึ้นครบและกดต่อได้" ไม่ใช่ข้อมูลที่โหลดมา
///
/// ห้ามใช้ pumpAndSettle กับหน้าที่มีวงหมุนกำลังโหลด เพราะวงหมุนหมุนไม่จบ
Widget _app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void _loginAsStudent() {
  authService.token = 'fake-token';
  authService.username = '662021052';
  authService.role = 'student';
}

/// ข้อความในเนื้อหาหน้าแรก (ทางลัด) — ชื่อเดียวกันมีบนแถบเมนูด้วยตั้งแต่เพิ่มเมนูนิสิต
Finder _inHomeBody(String text) =>
    find.descendant(of: find.byType(StudentHomeView), matching: find.text(text));

/// ข้อความบนแถบเมนูซ้าย
Finder _inSidebar(String text) =>
    find.descendant(of: find.byType(AppSidebar), matching: find.text(text));

void _wideScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(_loginAsStudent);
  tearDown(() => authService.logout());

  group('หน้าแรกของนิสิต', () {
    testWidgets('มีแถบนำทางด้านบน และ "หน้าแรก" เป็นเมนูที่เปิดอยู่', (tester) async {
      _wideScreen(tester);
      await tester.pumpWidget(_app(const HomeScreen()));

      expect(find.byType(AppSidebar), findsOneWidget);
      expect(find.text('TSU'), findsOneWidget);
      expect(find.text('นอกชั้นเรียน'), findsOneWidget);

      final active = tester.widget<Text>(find.text('หน้าแรก'));
      expect(active.style?.color, AppColors.blue);
    });

    testWidgets('โหลดข้อมูลไม่สำเร็จ: บอกให้ลองใหม่ แต่ทางลัดยังใช้ได้', (tester) async {
      _wideScreen(tester);
      await tester.pumpWidget(_app(const HomeScreen()));
      // ปล่อยให้คำขอที่ล้มเหลวจบก่อน แล้วค่อยตรวจ (ไม่ใช้ pumpAndSettle เพราะมีวงหมุน)
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('โหลดข้อมูลไม่สำเร็จ'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'ลองใหม่'), findsOneWidget);
      // ส่วนที่ไม่ต้องใช้ข้อมูลต้องยังอยู่ ไม่ถูกกลืนไปกับ error ทั้งหน้า
      expect(find.text('ทางลัด'), findsOneWidget);
      expect(_inHomeBody('ปฏิทินกิจกรรม'), findsOneWidget);
    });

    testWidgets('ทางลัดกดได้ตั้งแต่ยังโหลดข้อมูลไม่เสร็จ', (tester) async {
      _wideScreen(tester);
      await tester.pumpWidget(_app(const HomeScreen()));

      // ยังไม่ได้ pump รอผลโหลด — ทางลัดต้องอยู่แล้ว
      expect(find.text('ทางลัด'), findsOneWidget);
      expect(_inHomeBody('เช็กอินหน้างาน'), findsOneWidget);

      await tester.tap(_inHomeBody('เช็กอินหน้างาน'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CheckinScanScreen), findsOneWidget);
    });
  });

  group('การนำทางจากแถบเมนู', () {
    for (final (label, screenType) in const [
      ('ปฏิทินกิจกรรม', ActivityCalendarScreen),
      ('เช็กอินหน้างาน', CheckinScanScreen),
      ('การเข้าร่วมกิจกรรม', ParticipationsScreen),
    ]) {
      testWidgets('เมนูนิสิต "$label" บนแถบซ้ายเปิดหน้าได้ และเมนูนั้นเป็นตัวที่เปิดอยู่',
          (tester) async {
        _wideScreen(tester);
        await tester.pumpWidget(_app(const HomeScreen()));

        await tester.tap(_inSidebar(label));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byWidgetPredicate((w) => w.runtimeType == screenType), findsOneWidget);
        // หน้าปลายทางบอก sidebar ว่าอยู่หน้าไหน — เมนูนั้นต้องไฮไลต์ (ตัวน้ำเงิน)
        expect(tester.widget<Text>(_inSidebar(label)).style?.color, AppColors.blue);
      });
    }

    testWidgets('กดเมนูแล้วเปิดหน้านั้น และกลับหน้าแรกได้จากโลโก้', (tester) async {
      _wideScreen(tester);
      await tester.pumpWidget(_app(const HomeScreen()));

      await tester.tap(find.text('สมัครกิจกรรม'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(RegisterActivitiesScreen), findsOneWidget);

      // โลโก้พากลับหน้าแรก (เมนู "หน้าแรก" ก็ทำได้เหมือนกัน)
      await tester.tap(find.text('TSU'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(RegisterActivitiesScreen), findsNothing);
      expect(find.text('ทางลัด'), findsOneWidget);
    });

    testWidgets('สลับเมนูไปมาแล้ว stack ไม่ลึกขึ้นเรื่อย ๆ', (tester) async {
      _wideScreen(tester);
      await tester.pumpWidget(_app(const HomeScreen()));

      for (final label in ['สมัครกิจกรรม', 'รายละเอียดชั่วโมง', 'ผู้ช่วยอัจฉริยะ']) {
        await tester.tap(find.text(label).first);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }

      expect(find.byType(ChatbotScreen), findsOneWidget);
      // เหลือหน้าแรก + หน้าปัจจุบันเท่านั้น: หน้าที่แวะระหว่างทางต้องไม่ค้างใน stack
      expect(find.byType(RegisterActivitiesScreen), findsNothing);
      expect(find.byType(MyHoursScreen), findsNothing);
    });

    testWidgets('จอแคบ: เมนูยุบเป็น popup และแถบบนบอกชื่อหน้าที่เปิดอยู่', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(const ChatbotScreen()));

      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.text('ผู้ช่วยอัจฉริยะ'), findsOneWidget);
    });
  });

  group('หน้าสมัครกิจกรรม', () {
    testWidgets('มีหัวข้อหน้า ช่องค้นหา และตัวกรอง อยู่ใต้แถบเมนูเดียวกัน', (tester) async {
      _wideScreen(tester);
      await tester.pumpWidget(_app(const RegisterActivitiesScreen()));

      expect(find.byType(AppSidebar), findsOneWidget);
      expect(find.text('สมัครกิจกรรม'), findsNWidgets(2)); // เมนูบน + หัวข้อหน้า
      expect(find.widgetWithText(FilterChip, 'รวมกิจกรรมที่จัดไปแล้ว'), findsOneWidget);
      expect(find.text('ค้นหากิจกรรม/หมวด/สถานที่'), findsOneWidget);
    });
  });

  group('หน้าเช็กอิน QR', () {
    testWidgets('เจ้าหน้าที่เปิดหน้านี้ไม่ได้', (tester) async {
      authService.role = 'staff';
      await tester.pumpWidget(_app(const CheckinScanScreen()));

      expect(find.text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้'), findsOneWidget);
    });

    testWidgets('นิสิตเห็นการ์ดเช็กอินพร้อมโลโก้ TSU และปุ่มเปิดกล้อง', (tester) async {
      _wideScreen(tester);
      await tester.pumpWidget(_app(const CheckinScanScreen()));

      // โลโก้สองอัน: อันบนเมนู sidebar กับอันบนการ์ดเช็กอินตาม mockup
      // (จอแคบ sidebar ยุบเป็น drawer จะเหลืออันเดียว จึงต้องตรึงความกว้างไว้)
      expect(find.byType(TsuLogo), findsNWidgets(2));
      expect(find.text('สแกน QR ของกิจกรรมที่หน้างาน'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'เปิดกล้องสแกน QR'), findsOneWidget);
    });
  });

  group('วันที่ในตารางประวัติ', () {
    test('แสดงวันที่อย่างเดียวเป็น พ.ศ. ไม่มีเวลา', () {
      expect(formatThaiDate(DateTime(2026, 12, 1, 9, 30)), '1 ธ.ค. 2569');
      expect(formatThaiDate(DateTime(2024, 6, 29)), '29 มิ.ย. 2567');
    });
  });
}
