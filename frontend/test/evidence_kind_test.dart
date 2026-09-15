import 'dart:typed_data';

import 'package:activity_tracking_frontend/models/ocr_result.dart';
import 'package:activity_tracking_frontend/models/participation.dart';
import 'package:activity_tracking_frontend/services/api_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/evidence_kind.dart';
import 'package:activity_tracking_frontend/widgets/evidence_kind_dialog.dart';
import 'package:activity_tracking_frontend/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

/// ปุ่มที่เปิด dialog เลือกประเภท แล้วแสดงค่าที่ได้ (null → "ยกเลิกแล้ว")
class _KindProbe extends StatefulWidget {
  const _KindProbe();

  @override
  State<_KindProbe> createState() => _KindProbeState();
}

class _KindProbeState extends State<_KindProbe> {
  String result = 'ยังไม่กด';

  @override
  Widget build(BuildContext context) => Column(children: [
        FilledButton(
          onPressed: () async {
            final kind = await showEvidenceKindDialog(context);
            setState(() => result = kind ?? 'ยกเลิกแล้ว');
          },
          child: const Text('อัปโหลดหลักฐาน'),
        ),
        Text('ผล: $result'),
      ]);
}

FilledButton _chooseFileButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'เลือกไฟล์'));

void main() {
  group('ฟอร์มอัปโหลด: เลือกประเภทหลักฐาน (บังคับ ไม่มีค่าเริ่ม)', () {
    testWidgets('มีครบ 3 ตัวเลือก + ข้อความช่วย · ยังไม่เลือก ปุ่ม "เลือกไฟล์" กดไม่ได้', (tester) async {
      await tester.pumpWidget(_wrap(const _KindProbe()));
      await tester.tap(find.text('อัปโหลดหลักฐาน'));
      await tester.pumpAndSettle();

      expect(find.text('เกียรติบัตร / ใบรับรอง'), findsOneWidget);
      expect(find.text('ภาพถ่ายกิจกรรม (หน้าแบนเนอร์/สถานที่)'), findsOneWidget);
      expect(find.text('อื่น ๆ'), findsOneWidget);
      expect(find.text('ภาพถ่ายจะถูกส่งให้เจ้าหน้าที่ตรวจ ไม่อนุมัติอัตโนมัติ'), findsOneWidget);
      expect(_chooseFileButton(tester).onPressed, isNull, reason: 'ไม่มีค่าเริ่ม — ต้องเลือกเองก่อน');
    });

    for (final (label, kind) in [
      ('เกียรติบัตร / ใบรับรอง', 'certificate'),
      ('ภาพถ่ายกิจกรรม (หน้าแบนเนอร์/สถานที่)', 'photo'),
      ('อื่น ๆ', 'other'),
    ]) {
      testWidgets('เลือก "$label" แล้วกดเลือกไฟล์ → คืน $kind', (tester) async {
        await tester.pumpWidget(_wrap(const _KindProbe()));
        await tester.tap(find.text('อัปโหลดหลักฐาน'));
        await tester.pumpAndSettle();

        await tester.tap(find.text(label));
        await tester.pump();
        expect(_chooseFileButton(tester).onPressed, isNotNull);
        await tester.tap(find.text('เลือกไฟล์'));
        await tester.pumpAndSettle();

        expect(find.text('ผล: $kind'), findsOneWidget);
      });
    }

    testWidgets('กดยกเลิก → ไม่ได้ค่า (ไม่ไปต่อที่การเลือกไฟล์/อัปโหลด)', (tester) async {
      await tester.pumpWidget(_wrap(const _KindProbe()));
      await tester.tap(find.text('อัปโหลดหลักฐาน'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ภาพถ่ายกิจกรรม (หน้าแบนเนอร์/สถานที่)'));
      await tester.pump();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();

      expect(find.text('ผล: ยกเลิกแล้ว'), findsOneWidget);
    });
  });

  group('คำขออัปโหลดส่ง evidence_kind ไปเสมอ', () {
    for (final kind in kEvidenceKinds) {
      test('multipart มี field evidence_kind=$kind + ไฟล์ + token', () {
        final request = ApiService.buildEvidenceUploadRequest(
          Uri.parse('http://localhost:8000/participations/5/evidence'),
          bytes: Uint8List.fromList([1, 2, 3]),
          filename: 'proof.jpg',
          contentType: 'image/jpeg',
          evidenceKind: kind,
          token: 'abc',
        );

        expect(request.method, 'POST');
        expect(request.fields, {'evidence_kind': kind});
        expect(request.files.single.field, 'file');
        expect(request.files.single.filename, 'proof.jpg');
        expect(request.files.single.contentType.mimeType, 'image/jpeg');
        expect(request.headers['Authorization'], 'Bearer abc');
      });
    }
  });

  group('ป้ายประเภทในหน้าตรวจ', () {
    test('ภาพถ่าย/อื่น ๆ = ต้องตรวจด้วยตา (เหลือง) · เกียรติบัตร/null = สีกลาง ไม่มีคำว่าตรวจด้วยตา', () {
      expect(evidenceKindReviewLabel('photo'), '📷 ภาพถ่ายกิจกรรม — ต้องตรวจด้วยตา');
      expect(evidenceKindReviewLabel('other'), contains('ต้องตรวจด้วยตา'));
      expect(evidenceKindReviewLabel('certificate'), isNot(contains('ตรวจด้วยตา')));
      expect(evidenceKindReviewLabel(null), evidenceKindReviewLabel('certificate'), reason: 'ไฟล์ก่อนมีประเภท = เกียรติบัตร');

      expect(evidenceKindNeedsHumanReview('photo'), isTrue);
      expect(evidenceKindNeedsHumanReview('other'), isTrue);
      expect(evidenceKindNeedsHumanReview('certificate'), isFalse);
      expect(evidenceKindNeedsHumanReview(null), isFalse);

      expect(StatusChip.evidenceKind('photo').palette, StatusPalette.pending);
      expect(StatusChip.evidenceKind('other').palette, StatusPalette.pending);
      expect(StatusChip.evidenceKind('certificate').palette, StatusPalette.neutral);
    });

    test('ป้ายสั้นสำหรับตาราง', () {
      expect(StatusChip.evidenceKind('photo', compact: true).label, '📷 ภาพถ่าย · ตรวจด้วยตา');
      expect(StatusChip.evidenceKind('photo').label, '📷 ภาพถ่ายกิจกรรม — ต้องตรวจด้วยตา');
    });

    testWidgets('ชิปแสดงข้อความตามประเภท', (tester) async {
      await tester.pumpWidget(_wrap(Column(children: [
        StatusChip.evidenceKind('photo'),
        StatusChip.evidenceKind('certificate'),
      ])));

      expect(find.text('📷 ภาพถ่ายกิจกรรม — ต้องตรวจด้วยตา'), findsOneWidget);
      expect(find.text('📄 เกียรติบัตร / ใบรับรอง'), findsOneWidget);
    });

    test('โมเดลอ่าน evidence_kind จาก API (ผล OCR + รายการคิวตรวจ)', () {
      final ocr = OcrResult.fromJson({
        'id': 1, 'raw_file_id': 2, 'participation_id': 3, 'extracted_text': '',
        'ocr_confidence': 0.9, 'match_score': 0.9, 'decision': 'needs_review',
        'is_duplicate': false, 'processed_at': '2026-09-16T10:00:00', 'evidence_kind': 'photo',
      });
      final participation = Participation.fromJson({'id': 3, 'student_id': 1, 'activity_id': 2, 'evidence_kind': 'other'});
      final noFile = Participation.fromJson({'id': 4, 'student_id': 1, 'activity_id': 2});

      expect(ocr.evidenceKind, 'photo');
      expect(participation.evidenceKind, 'other');
      expect(noFile.evidenceKind, isNull);
    });
  });
}
