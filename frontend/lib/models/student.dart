class Student {
  final int? id;
  final String studentId;
  final String fullName;
  final String faculty;
  final String major;
  final int yearLevel;
  final String status; // active | inactive

  /// อีเมลสำหรับแจ้งเตือน — null/ว่าง = ยังไม่ระบุ (ระบบไม่เดาจากรหัสนิสิตให้)
  final String? email;

  Student({
    this.id,
    required this.studentId,
    required this.fullName,
    required this.faculty,
    required this.major,
    required this.yearLevel,
    this.status = 'active',
    this.email,
  });

  factory Student.fromJson(Map<String, dynamic> json) => Student(
        id: json['id'] as int?,
        studentId: json['student_id'] as String,
        fullName: json['full_name'] as String,
        faculty: json['faculty'] as String,
        major: json['major'] as String,
        yearLevel: json['year_level'] as int,
        status: json['status'] as String? ?? 'active',
        email: json['email'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'full_name': fullName,
        'faculty': faculty,
        'major': major,
        'year_level': yearLevel,
        'status': status,
        // ส่ง null ไปด้วยเสมอ เพื่อให้ "ล้างอีเมลทิ้ง" มีผลจริงตอนแก้ไข
        'email': email,
      };
}
