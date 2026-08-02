import 'package:activity_tracking_frontend/utils/api_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('apiErrorMessage', () {
    test('422 ของ FastAPI ต้องไม่โผล่ JSON ดิบให้ผู้ใช้เห็น', () {
      // นี่คือ body จริงที่ทำให้หน้าจัดการผู้ใช้ขึ้น error อ่านไม่รู้เรื่อง
      final body = {
        'detail': [
          {
            'type': 'less_than_equal',
            'loc': ['query', 'limit'],
            'msg': 'Input should be less than or equal to 200',
            'input': '500',
            'ctx': {'le': 200},
          }
        ]
      };

      final message = apiErrorMessage(422, body);

      expect(message, 'ข้อมูลที่กรอกไม่ถูกต้อง (จำนวนต่อหน้า: ต้องไม่เกิน 200)');
      expect(message, isNot(contains('less_than_equal')));
      expect(message, isNot(contains('loc')));
    });

    test('รวมหลายฟิลด์ที่ผิดไว้ในข้อความเดียว', () {
      final body = {
        'detail': [
          {
            'type': 'missing',
            'loc': ['body', 'hours'],
            'msg': 'Field required',
          },
          {
            'type': 'int_parsing',
            'loc': ['body', 'year_level'],
            'msg': 'Input should be a valid integer',
          },
        ]
      };

      expect(
        apiErrorMessage(422, body),
        'ข้อมูลที่กรอกไม่ถูกต้อง (จำนวนชั่วโมง: ต้องระบุ, ชั้นปี: ต้องเป็นตัวเลข)',
      );
    });

    test('detail ที่ backend เขียนเป็นไทยอยู่แล้ว ใช้ตามนั้น', () {
      expect(
        apiErrorMessage(400, {'detail': 'บัญชีนิสิตต้องผูกกับข้อมูลนิสิต (student_id)'}),
        'บัญชีนิสิตต้องผูกกับข้อมูลนิสิต (student_id)',
      );
    });

    test('ไม่มี detail ให้ใช้ข้อความตามรหัสสถานะ', () {
      expect(apiErrorMessage(401, null), 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
      expect(apiErrorMessage(403, {}), 'คุณไม่มีสิทธิ์ทำรายการนี้');
      expect(apiErrorMessage(404, null), 'ไม่พบข้อมูลที่ต้องการ');
      expect(apiErrorMessage(500, null), 'เซิร์ฟเวอร์ขัดข้อง กรุณาลองใหม่อีกครั้ง');
      expect(apiErrorMessage(418, null), 'เกิดข้อผิดพลาด (418)');
    });

    test('detail อังกฤษจาก backend ต้องถูกแปลเป็นไทย', () {
      expect(
        apiErrorMessage(403, {'detail': 'This account is not linked to a student record'}),
        'บัญชีนี้ยังไม่ได้ผูกกับข้อมูลนิสิต',
      );
      expect(
        apiErrorMessage(403, {'detail': 'Insufficient permissions'}),
        'คุณไม่มีสิทธิ์ทำรายการนี้',
      );
      expect(
        apiErrorMessage(401, {'detail': 'Incorrect username or password'}),
        'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง',
      );
      expect(
        apiErrorMessage(400, {'detail': 'username already exists'}),
        'ชื่อผู้ใช้นี้ถูกใช้ไปแล้ว กรุณาตั้งชื่ออื่น',
      );
      expect(
        apiErrorMessage(400, {'detail': 'student_id does not exist'}),
        'ไม่พบนิสิตที่เลือก กรุณาเลือกใหม่',
      );
      expect(apiErrorMessage(404, {'detail': 'Student not found'}), 'ไม่พบข้อมูลนิสิต');
      expect(apiErrorMessage(404, {'detail': 'Activity not found'}), 'ไม่พบกิจกรรมนี้');
      expect(
        apiErrorMessage(404, {'detail': 'Participation not found'}),
        'ไม่พบรายการเข้าร่วมนี้',
      );
      expect(apiErrorMessage(404, {'detail': 'User not found'}), 'ไม่พบบัญชีผู้ใช้นี้');
    });

    test('เทียบข้อความแบบไม่สนตัวพิมพ์เล็กใหญ่', () {
      expect(
        apiErrorMessage(403, {'detail': 'INSUFFICIENT PERMISSIONS'}),
        'คุณไม่มีสิทธิ์ทำรายการนี้',
      );
    });

    test('อังกฤษที่ยังไม่ได้แปล ต้องไม่หลุดไปถึงผู้ใช้', () {
      final message = apiErrorMessage(400, {'detail': 'Some brand new english error'});
      expect(message, 'ข้อมูลที่ส่งไม่ถูกต้อง');
      expect(message, isNot(contains('english')));
    });

    test('extra_forbidden (ส่งฟิลด์ที่ห้ามส่ง) อธิบายเป็นไทย', () {
      final body = {
        'detail': [
          {
            'type': 'extra_forbidden',
            'loc': ['body', 'hours_earned'],
            'msg': 'Extra inputs are not permitted',
          }
        ]
      };
      expect(
        apiErrorMessage(422, body),
        contains('ชั่วโมงที่ได้รับ: ไม่อนุญาตให้ส่งค่านี้'),
      );
    });
  });

  group('friendlyError', () {
    test('ต่อ backend ไม่ติด บอกวิธีตรวจสอบแทนชื่อ exception', () {
      expect(
        friendlyError(Exception('ClientException: Failed to fetch, uri=http://localhost:8000')),
        'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบว่าเปิด backend อยู่หรือไม่',
      );
    });

    test('ตัดคำว่า Exception: ที่ผู้ใช้ไม่ต้องเห็นออก', () {
      expect(friendlyError(Exception('ไม่พบข้อมูลที่ต้องการ')), 'ไม่พบข้อมูลที่ต้องการ');
    });
  });
}
