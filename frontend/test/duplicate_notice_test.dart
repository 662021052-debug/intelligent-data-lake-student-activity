import 'package:activity_tracking_frontend/models/ocr_result.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/ocr_status.dart';
import 'package:activity_tracking_frontend/widgets/duplicate_notice.dart';
import 'package:activity_tracking_frontend/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

OcrResult _ocr({
  String decision = 'flagged',
  bool isDuplicate = true,
  String? reason = 'cross_student',
  int? dupOf = 62162,
  String? name = 'นางสาวนงนภัส ขนุนนิล',
  String? code = '6710000001',
  String? activity = 'ตลาดนัดผู้ประกอบการรุ่นเยาว์',
  String? originalStatus = 'approved',
  bool viewable = true,
}) =>
    OcrResult(
      id: 1,
      rawFileId: 50,
      participationId: 91442,
      extractedText: 'มหาวิทยาลัยทักษิณ',
      ocrConfidence: 0.69,
      matchScore: 0.76,
      decision: decision,
      isDuplicate: isDuplicate,
      processedAt: DateTime(2026, 9, 14),
      duplicateOfParticipationId: dupOf,
      duplicateReason: reason,
      duplicateOfStudentName: name,
      duplicateOfStudentCode: code,
      duplicateOfActivityName: activity,
      duplicateOfEvidenceStatus: originalStatus,
      duplicateOfViewable: viewable,
    );

/// ปุ่มที่เรียก confirmApproveIfDuplicate แล้วเก็บผลไว้ให้เทสอ่าน
class _ApproveProbe extends StatefulWidget {
  const _ApproveProbe(this.ocr);
  final OcrResult? ocr;

  @override
  State<_ApproveProbe> createState() => _ApproveProbeState();
}

class _ApproveProbeState extends State<_ApproveProbe> {
  String result = 'ยังไม่กด';

  @override
  Widget build(BuildContext context) => Column(children: [
        FilledButton(
          onPressed: () async {
            final ok = await confirmApproveIfDuplicate(context, widget.ocr);
            setState(() => result = ok ? 'อนุมัติต่อ' : 'ยกเลิกแล้ว');
          },
          child: const Text('อนุมัติ'),
        ),
        Text(result),
      ]);
}

void main() {
  group('ป้ายผล OCR ของใบ flagged บอกเหตุผล (เฟส 1.3)', () {
    test('ป้ายสั้นตามเหตุผล · ผลรุ่นเก่า (null) ยังเป็น "ไฟล์ซ้ำ"', () {
      expect(ocrDecisionLabel('flagged', duplicateReason: 'cross_student'), contains('ซ้ำกับนิสิตคนอื่น'));
      expect(ocrDecisionLabel('flagged', duplicateReason: 'same_student_reuse'), contains('ใช้ไฟล์เดิมซ้ำ'));
      expect(ocrDecisionLabel('flagged', duplicateReason: 'matches_rejected'), contains('เคยถูกปฏิเสธ'));
      expect(ocrDecisionLabel('flagged'), contains('ไฟล์ซ้ำ'));
      expect(ocrDecisionLabel('needs_review', duplicateReason: 'cross_student'), contains('รอเจ้าหน้าที่ตรวจ'));
    });

    test('สี: ซ้ำกับนิสิตคนอื่น/ตรงใบที่ถูกปฏิเสธ/ไม่รู้เหตุผล = แดง · ใช้ไฟล์เดิมซ้ำ = เหลือง', () {
      StatusPalette paletteOf(String? reason) =>
          StatusChip.ocr('flagged', duplicateReason: reason).palette;
      expect(paletteOf('cross_student'), StatusPalette.rejected);
      expect(paletteOf('matches_rejected'), StatusPalette.rejected);
      expect(paletteOf(null), StatusPalette.rejected);
      expect(paletteOf('same_student_reuse'), StatusPalette.pending);
      expect(StatusChip.ocr('auto_approved').palette, StatusPalette.approved);
    });
  });

  group('แถบบอกว่าซ้ำกับใบไหน', () {
    testWidgets('cross_student: บอกชื่อ (รหัส) · กิจกรรม · สถานะใบต้นทาง + ลิงก์ดูใบต้นทาง', (tester) async {
      var opened = false;
      await tester.pumpWidget(_wrap(DuplicateNotice(ocr: _ocr(), onOpenOriginal: () => opened = true)));

      expect(
        find.text('⚠ ซ้ำกับใบของนิสิตคนอื่น: นางสาวนงนภัส ขนุนนิล (6710000001) · กิจกรรม ตลาดนัดผู้ประกอบการรุ่นเยาว์'),
        findsOneWidget,
      );
      expect(find.textContaining('สถานะหลักฐานของใบต้นทาง'), findsOneWidget);
      await tester.tap(find.text('ดูใบต้นทาง'));
      expect(opened, isTrue);
    });

    testWidgets('same_student_reuse: "ใช้ไฟล์เดิมกับกิจกรรม {ชื่อ}"', (tester) async {
      await tester.pumpWidget(_wrap(DuplicateNotice(
        ocr: _ocr(reason: 'same_student_reuse', activity: 'อบรมดิจิทัล'),
      )));
      expect(find.text('ใช้ไฟล์เดิมกับกิจกรรม อบรมดิจิทัล'), findsOneWidget);
    });

    testWidgets('matches_rejected: บอกว่าตรงกับใบที่เคยถูกปฏิเสธของใคร', (tester) async {
      await tester.pumpWidget(_wrap(DuplicateNotice(
        ocr: _ocr(reason: 'matches_rejected', originalStatus: 'rejected'),
      )));
      expect(find.textContaining('ตรงกับใบที่เคยถูกปฏิเสธ: นางสาวนงนภัส ขนุนนิล'), findsOneWidget);
    });

    testWidgets('ไม่มีสิทธิ์เปิดใบต้นทาง → ไม่มีลิงก์ (แต่ยังเห็นว่าซ้ำกับใคร)', (tester) async {
      await tester.pumpWidget(_wrap(DuplicateNotice(ocr: _ocr(viewable: false), onOpenOriginal: () {})));
      expect(find.textContaining('ซ้ำกับใบของนิสิตคนอื่น'), findsOneWidget);
      expect(find.text('ดูใบต้นทาง'), findsNothing);
    });

    testWidgets('ผล OCR รุ่นเก่า (ไม่มีเหตุผล/ใบต้นทาง) บอกให้ประมวลผลใหม่ ไม่มีลิงก์', (tester) async {
      await tester.pumpWidget(_wrap(DuplicateNotice(
        ocr: _ocr(reason: null, dupOf: null, name: null, code: null, activity: null, originalStatus: null,
            viewable: false),
        onOpenOriginal: () {},
      )));
      expect(find.textContaining('ประมวลผล OCR'), findsOneWidget);
      expect(find.text('ดูใบต้นทาง'), findsNothing);
    });
  });

  group('อนุมัติใบ flagged ต้องผ่าน dialog ยืนยัน', () {
    testWidgets('ใบไม่ซ้ำ → อนุมัติต่อได้ทันที ไม่มี dialog', (tester) async {
      await tester.pumpWidget(_wrap(_ApproveProbe(_ocr(decision: 'needs_review', isDuplicate: false, reason: null))));
      await tester.tap(find.text('อนุมัติ'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('อนุมัติต่อ'), findsOneWidget);
    });

    testWidgets('ยังไม่มีผล OCR → อนุมัติต่อได้ ไม่มี dialog', (tester) async {
      await tester.pumpWidget(_wrap(const _ApproveProbe(null)));
      await tester.tap(find.text('อนุมัติ'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('อนุมัติต่อ'), findsOneWidget);
    });

    testWidgets('ใบ flagged → dialog บอกว่าซ้ำกับใคร · กดยกเลิกแล้วไม่อนุมัติ', (tester) async {
      await tester.pumpWidget(_wrap(_ApproveProbe(_ocr())));
      await tester.tap(find.text('อนุมัติ'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('อนุมัติใบที่ไฟล์ซ้ำ?'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('นางสาวนงนภัส ขนุนนิล (6710000001)')),
        findsOneWidget,
      );
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(find.text('ยกเลิกแล้ว'), findsOneWidget);
    });

    testWidgets('ใบ flagged → กด "อนุมัติทั้งที่ซ้ำ" แล้วไปต่อได้ (ไม่บล็อกถาวร)', (tester) async {
      await tester.pumpWidget(_wrap(_ApproveProbe(_ocr(reason: 'same_student_reuse'))));
      await tester.tap(find.text('อนุมัติ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('อนุมัติทั้งที่ซ้ำ'));
      await tester.pumpAndSettle();
      expect(find.text('อนุมัติต่อ'), findsOneWidget);
    });
  });
}
