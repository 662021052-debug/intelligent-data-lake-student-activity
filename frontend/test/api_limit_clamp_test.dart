import 'package:activity_tracking_frontend/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// กันบั๊กเก่ากลับมา: frontend เคยยิง `limit=500` ไปหา endpoint ที่ backend
/// จำกัดไว้ที่ 200 → ได้ 422 ทั้งคำขอ → dropdown "นิสิตที่ผูกบัญชี" ว่างเปล่า
void main() {
  group('ApiService.clampLimit', () {
    test('limit เกินเพดาน 200 ถูกบีบลงมาเป็น 200', () {
      expect(ApiService.clampLimit({'limit': '500'}), {'limit': '200'});
    });

    test('limit ที่ไม่เกินเพดาน ปล่อยผ่านตามเดิม', () {
      expect(ApiService.clampLimit({'limit': '200'}), {'limit': '200'});
      expect(ApiService.clampLimit({'limit': '10'}), {'limit': '10'});
    });

    test('คิวรีอื่นไม่ถูกแตะ และ skip ยังอยู่ครบ', () {
      expect(
        ApiService.clampLimit({'skip': '400', 'limit': '999', 'search': 'สมชาย'}),
        {'skip': '400', 'limit': '200', 'search': 'สมชาย'},
      );
    });

    test('ไม่มี limit หรือไม่มีคิวรีเลย ก็ไม่พัง', () {
      expect(ApiService.clampLimit(null), isNull);
      expect(ApiService.clampLimit({'search': 'x'}), {'search': 'x'});
    });

    test('limit ที่ไม่ใช่ตัวเลข ปล่อยให้ backend เป็นคนตัดสิน', () {
      expect(ApiService.clampLimit({'limit': 'abc'}), {'limit': 'abc'});
    });

    test('เพดานตรงกับที่ backend ประกาศไว้ (Query(..., le=200))', () {
      expect(ApiService.maxPageSize, 200);
    });
  });
}
