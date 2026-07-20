class AppUser {
  final int id;
  final String username;
  final String role; // student | staff | admin
  final int? studentId;

  AppUser({
    required this.id,
    required this.username,
    required this.role,
    this.studentId,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        username: json['username'] as String,
        role: json['role'] as String,
        studentId: json['student_id'] as int?,
      );
}
