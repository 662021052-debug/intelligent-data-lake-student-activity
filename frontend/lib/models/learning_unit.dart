/// หน่วยการเรียนรู้ 5 หน่วย (จาก `GET /learning-units`)
///
/// เป็น taxonomy คงที่ที่ทุกชุดเกณฑ์ใช้ร่วมกัน — ฟอร์มรายการเกณฑ์ใช้เลือกว่า
/// ชั่วโมงของรายการนั้นนับเข้าหน่วยไหน
class LearningUnit {
  final int id;
  final String code;
  final String name;

  const LearningUnit({required this.id, required this.code, required this.name});

  factory LearningUnit.fromJson(Map<String, dynamic> json) => LearningUnit(
        id: json['id'] as int,
        code: json['code'] as String,
        name: json['name'] as String,
      );
}
