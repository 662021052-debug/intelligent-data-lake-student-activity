import 'package:activity_tracking_frontend/models/participation.dart';
import 'package:activity_tracking_frontend/screens/app_shell.dart';
import 'package:activity_tracking_frontend/screens/evidence_review_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/evidence_kind.dart';
import 'package:activity_tracking_frontend/utils/ocr_status.dart';
import 'package:activity_tracking_frontend/widgets/app_card.dart';
import 'package:activity_tracking_frontend/widgets/app_table_cells.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _labelOf(DataColumn column) => (column.label as TableColumnLabel).text;

const _labels = ['นิสิต', 'กิจกรรม', 'ส่งเมื่อ', 'ผล OCR', 'สถานะ', 'จัดการ'];

Participation _p(
  int id, {
  String name = 'นายสมชาย ใจดี',
  String activity = 'อบรมปฐมพยาบาล',
  String status = 'pending',
  String? decision,
  String? reason,
  String? matchKind,
  String? kind,
}) =>
    Participation(
      id: id,
      studentId: id,
      activityId: 100 + id,
      evidenceStatus: status,
      studentName: name,
      studentCode: '692151007$id',
      activityName: activity,
      hasEvidence: true,
      evidenceUploadedAt: DateTime(2026, 9, 15, 13, 32),
      hasOcr: decision != null,
      ocrDecision: decision,
      ocrMatchScore: 0.93,
      ocrConfidence: 0.71,
      ocrDuplicateReason: reason,
      ocrMatchKind: matchKind,
      evidenceKind: kind,
    );

/// แถวที่ยาวที่สุดที่คิวจริงมีได้: ชื่อ/กิจกรรมยาว + ป้ายซ้ำยาว + ป้ายภาพถ่าย (สองป้ายซ้อน)
final _items = [
  _p(
    1,
    name: 'นางสาวกัลยาณมิตรพิมพ์ชนก ขนานใต้วงศ์สวัสดิ์ศรีสุขเจริญ',
    activity: 'ค่ายทักษะการทำงานเป็นทีมและการสื่อสารอย่างสร้างสรรค์เพื่อชุมชน ครั้งที่ 4/2570',
    decision: 'flagged',
    reason: 'cross_student',
    matchKind: 'near',
    kind: 'photo',
  ),
  _p(2, status: 'rejected', decision: 'needs_review', kind: 'other'),
  _p(3, status: 'approved', decision: 'auto_approved', kind: 'certificate'),
  _p(4),
];

final _flaggedLabel = ocrDecisionLabel('flagged', duplicateReason: 'cross_student', matchKind: 'near');

void _screen(WidgetTester tester, double width, {double height = 900}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  authService.token = 'fake-token';
  authService.username = 'admin';
  authService.role = 'admin';
}

/// หน้าเต็มแบบที่ผู้ใช้เห็นจริง: เปลือกผู้ดูแล (แถบเมนู + ขอบหน้า) + การ์ดตาราง
Future<void> _pumpTable(
  WidgetTester tester,
  double width, {
  ValueChanged<Participation>? onReview,
}) async {
  _screen(tester, width);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: AdminPage(
      activeId: 'evidence_review',
      title: 'ตรวจหลักฐาน',
      child: TableCard(
        child: EvidenceReviewTable(items: _items, onReview: onReview ?? (_) {}),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Rect _rectOf(Element element) {
  final box = element.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  tearDown(() => authService.logout());

  group('คอลัมน์คิวตรวจหลักฐาน', () {
    test('นิสิต · กิจกรรม · ส่งเมื่อ · ผล OCR · สถานะ · จัดการ (ปุ่มตรวจ)', () {
      expect(evidenceReviewColumns().map(_labelOf).toList(), _labels);
    });

    test('ข้อความ/ป้ายแชร์พื้นที่แบบ flex · วันที่ สถานะ ปุ่ม กว้างคงที่', () {
      final columns = {for (final c in evidenceReviewColumns()) _labelOf(c): c};
      for (final label in ['นิสิต', 'กิจกรรม', 'ผล OCR']) {
        expect(columns[label]!.columnWidth, isA<FlexColumnWidth>(), reason: label);
      }
      for (final label in ['ส่งเมื่อ', 'สถานะ', 'จัดการ']) {
        expect(columns[label]!.columnWidth, isA<FixedColumnWidth>(), reason: label);
      }
      // คอลัมน์ปุ่มรวม padding ของเซลล์ + ขอบตาราง — ปุ่มไม่ถูกบีบ
      expect(
        (columns['จัดการ']!.columnWidth! as FixedColumnWidth).value,
        EvidenceReviewButton.width + kEvidenceColumnSpacing / 2 + kEvidenceTableMargin,
      );
    });

    test('เซลล์ต่อแถวเท่าจำนวนคอลัมน์', () {
      expect(evidenceReviewCells(_items.first, onReview: () {}).length, _labels.length);
    });
  });

  group('ตารางพอดีจอ ปุ่ม "ตรวจ" เห็นครบ', () {
    for (final width in [1024.0, 1280.0, 1440.0]) {
      testWidgets('กว้าง ${width.toInt()}: ไม่ล้น ไม่เลื่อนแนวนอน ปุ่มตรวจทุกแถวอยู่ในตาราง', (tester) async {
        await _pumpTable(tester, width);

        expect(tester.takeException(), isNull, reason: 'ต้องไม่ overflow');
        final inCard = find.byType(TableCard);
        expect(
          find.descendant(
            of: inCard,
            matching: find.byWidgetPredicate((w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.left || w.axisDirection == AxisDirection.right)),
          ),
          findsNothing,
          reason: 'ตารางต้องไม่มีส่วนที่เลื่อนแนวนอน',
        );

        final table = tester.getRect(find.byType(DataTable));
        final card = tester.getRect(find.descendant(of: inCard, matching: find.byType(AppCard)));
        expect(table.right, lessThanOrEqualTo(width + 0.5), reason: 'ตารางเกินขอบจอ');
        expect(table.right, lessThanOrEqualTo(card.right + 0.5), reason: 'ตารางเกินขอบการ์ด');

        for (final label in _labels) {
          final header = tester.getRect(
            find.descendant(of: find.byType(DataTable), matching: find.text(label)),
          );
          expect(header.right, lessThanOrEqualTo(table.right + 0.5), reason: '"$label" หลุดขวา');
        }

        final buttons = find.byType(EvidenceReviewButton);
        expect(buttons, findsNWidgets(_items.length));
        for (final element in buttons.evaluate()) {
          final rect = _rectOf(element);
          expect(rect.right, lessThanOrEqualTo(table.right + 0.5), reason: 'ปุ่มตรวจหลุดขอบตาราง');
          expect(rect.width, moreOrLessEquals(EvidenceReviewButton.width, epsilon: 0.5),
              reason: 'ปุ่มตรวจต้องไม่ถูกบีบ');
        }
        expect(
          find.descendant(of: find.byType(DataTable), matching: find.text('ตรวจ')),
          findsNWidgets(_items.length),
        );

        // ป้ายซ้ำ + ป้ายภาพถ่าย/อื่น ๆ ยังแสดง (ตัด … ได้ แต่ต้องไม่หาย)
        expect(find.text(_flaggedLabel), findsOneWidget);
        expect(find.text(evidenceKindShortLabel('photo')), findsOneWidget);
        expect(find.text(evidenceKindShortLabel('other')), findsOneWidget);
        expect(find.text(evidenceKindShortLabel('certificate')), findsNothing,
            reason: 'เกียรติบัตรไม่ต้องมีป้ายประเภท');
      });
    }

    testWidgets('ตารางกว้างเท่าการ์ดพอดี', (tester) async {
      await _pumpTable(tester, 1440);
      final card = tester.getRect(find.descendant(of: find.byType(TableCard), matching: find.byType(AppCard)));
      expect(tester.getRect(find.byType(DataTable)).width, moreOrLessEquals(card.width, epsilon: 2));
    });

    testWidgets('ชื่อ/กิจกรรม/ป้ายยาวตัดด้วย … ไม่ดันคอลัมน์อื่น', (tester) async {
      await _pumpTable(tester, 1280);
      expect(tester.takeException(), isNull);

      final flagged = tester.widget<Text>(find.text(_flaggedLabel));
      expect(flagged.overflow, TextOverflow.ellipsis);
      expect(flagged.maxLines, 1);

      final ocrColumn = tester.getRect(find.descendant(of: find.byType(DataTable), matching: find.text('ผล OCR')));
      final statusColumn = tester.getRect(find.descendant(of: find.byType(DataTable), matching: find.text('สถานะ')));
      // ป้ายซ้ำยาวอยู่ในคอลัมน์ผล OCR ไม่ล้นทับคอลัมน์สถานะ
      expect(tester.getRect(find.text(_flaggedLabel)).right, lessThanOrEqualTo(statusColumn.left + 0.5));
      expect(tester.getRect(find.text(_flaggedLabel)).left, greaterThanOrEqualTo(ocrColumn.left - 0.5));
    });

    testWidgets('กดปุ่ม "ตรวจ" ของแถวไหน เปิดรายการนั้น', (tester) async {
      Participation? opened;
      await _pumpTable(tester, 1440, onReview: (p) => opened = p);
      await tester.tap(find.byType(EvidenceReviewButton).at(2));
      expect(opened?.id, _items[2].id);
    });
  });

  group('จอแคบเป็นการ์ด ไม่ล้น', () {
    for (final width in [360.0, 390.0]) {
      testWidgets('กว้าง ${width.toInt()}: การ์ดครบ ป้ายยังแสดง ไม่ overflow', (tester) async {
        _screen(tester, width, height: 1400);
        Participation? opened;
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: AdminPage(
            activeId: 'evidence_review',
            title: 'ตรวจหลักฐาน',
            child: EvidenceReviewCards(items: _items, onReview: (p) => opened = p),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'การ์ดต้องไม่ overflow');
        expect(find.byType(ListTile), findsNWidgets(_items.length));
        expect(find.text(_flaggedLabel), findsOneWidget);
        expect(find.text(evidenceKindShortLabel('photo')), findsOneWidget);
        for (final element in find.byType(ListTile).evaluate()) {
          expect(_rectOf(element).right, lessThanOrEqualTo(width + 0.5));
        }

        await tester.tap(find.byType(ListTile).first);
        expect(opened?.id, _items.first.id);
      });
    }
  });
}
