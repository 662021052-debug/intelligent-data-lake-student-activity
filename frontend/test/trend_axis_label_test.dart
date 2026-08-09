import 'package:activity_tracking_frontend/screens/dashboard_screen.dart';
import 'package:activity_tracking_frontend/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMonthLabel', () {
    test('ค.ศ. → ชื่อเดือนไทยย่อ + พ.ศ. สองหลัก', () {
      expect(formatMonthLabel(DateTime(2025, 8)), 'ส.ค. 68');
      expect(formatMonthLabel(DateTime(2026, 2)), 'ก.พ. 69');
    });

    test('เดือนหัวท้ายต้องไม่หลุด index', () {
      expect(formatMonthLabel(DateTime(2026, 1)), 'ม.ค. 69');
      expect(formatMonthLabel(DateTime(2026, 12)), 'ธ.ค. 69');
    });

    test('ข้ามศตวรรษ (พ.ศ. 2600) ยังเป็นเลขสองหลัก ไม่ใช่ "0" โดด ๆ', () {
      expect(formatMonthLabel(DateTime(2057, 3)), 'มี.ค. 00');
    });
  });

  group('showsTrendLabel', () {
    /// index ที่ได้ป้ายจริง — เทียบง่ายกว่าไล่เรียกทีละจุด
    List<int> labelled(int count) =>
        [for (var i = 0; i < count; i++) if (showsTrendLabel(i, count)) i];

    test('จุดน้อยกว่า 6 เดือน ทุกจุดมีป้ายครบ ไม่ข้ามเดือนไหน', () {
      expect(labelled(5), [0, 1, 2, 3, 4]);
    });

    test('จุดเยอะ ป้ายเว้นระยะเท่ากันหมด ไม่มีคู่ไหนชิดกันเป็นพิเศษ', () {
      // 14 จุด → step 3 · ถ้าโชว์จุดสุดท้ายแบบยกเว้น จะได้ …,12,13 ที่ชนกัน
      final indexes = labelled(14);
      expect(indexes, [1, 4, 7, 10, 13]);
      final gaps = [
        for (var i = 1; i < indexes.length; i++) indexes[i] - indexes[i - 1],
      ];
      expect(gaps.toSet(), {3});
    });

    test('เดือนล่าสุดต้องมีป้ายเสมอ ไม่ว่าจะกี่จุด', () {
      for (var count = 1; count <= 40; count++) {
        expect(showsTrendLabel(count - 1, count), isTrue, reason: 'count=$count');
      }
    });

    test('index นอกช่วงข้อมูลไม่มีป้าย — กัน label ซ้ำจาก interval ทศนิยม', () {
      expect(showsTrendLabel(-1, 10), isFalse);
      expect(showsTrendLabel(10, 10), isFalse);
      expect(showsTrendLabel(0, 0), isFalse);
    });
  });
}
