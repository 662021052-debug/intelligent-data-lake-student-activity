/// ชุดเกณฑ์กิจกรรมและรายการเกณฑ์ที่กิจกรรมผูกถึงได้ (จาก `GET /criteria-sets`)
///
/// backend จัดกลุ่มมาให้แล้ว เพราะสองชุดเกณฑ์จัดกลุ่มคนละแบบ (2567 = Talent/PLO ·
/// ชุดเดิม = หน่วยการเรียนรู้) UI จึงวาดตามที่ได้มาโดยไม่ต้องรู้กติกานั้นเอง
library;

class CriteriaRequirement {
  final int id;
  final String name;
  final double requiredHours;
  final bool isMandatory;

  /// หน่วยการเรียนรู้ที่รายการนี้สังกัด — ชุด 2567 จัดกลุ่มด้วย Talent จึงเอาหน่วย
  /// มาแสดงเป็นคำกำกับแทน
  final String? learningUnitName;

  /// อยู่ในกลุ่มที่แชร์เป้าชั่วโมงกับรายการอื่นไหม (เช่น Social รวม ≥ 16 ชม.)
  final String? groupName;

  const CriteriaRequirement({
    required this.id,
    required this.name,
    this.requiredHours = 0,
    this.isMandatory = false,
    this.learningUnitName,
    this.groupName,
  });

  factory CriteriaRequirement.fromJson(Map<String, dynamic> json) => CriteriaRequirement(
        id: json['id'] as int,
        name: json['name'] as String,
        requiredHours: (json['required_hours'] as num?)?.toDouble() ?? 0,
        isMandatory: json['is_mandatory'] as bool? ?? false,
        learningUnitName: json['learning_unit_name'] as String?,
        groupName: json['group_name'] as String?,
      );
}

class CriteriaGroup {
  /// กุญแจของกลุ่ม เช่น "talent:1" / "unit:3" — ใช้จำว่ากลุ่มไหนกางอยู่
  final String key;
  final String name;

  /// คำกำกับหัวข้อ เช่น "PLO 1" หรือ "หน่วยที่ 3"
  final String? subtitle;
  final List<CriteriaRequirement> requirements;

  const CriteriaGroup({
    required this.key,
    required this.name,
    this.subtitle,
    this.requirements = const [],
  });

  factory CriteriaGroup.fromJson(Map<String, dynamic> json) => CriteriaGroup(
        key: json['key'] as String,
        name: json['name'] as String,
        subtitle: json['subtitle'] as String?,
        requirements: ((json['requirements'] as List?) ?? const [])
            .map((e) => CriteriaRequirement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CriteriaSet {
  final int id;
  final String code;
  final String name;
  final int academicYear;
  final double totalRequiredHours;

  /// "talent" (ชุดที่มี Talent/PLO) หรือ "learning_unit" (ชุดเดิม)
  final String groupedBy;
  final List<CriteriaGroup> groups;

  const CriteriaSet({
    required this.id,
    required this.code,
    required this.name,
    this.academicYear = 0,
    this.totalRequiredHours = 0,
    this.groupedBy = 'talent',
    this.groups = const [],
  });

  factory CriteriaSet.fromJson(Map<String, dynamic> json) => CriteriaSet(
        id: json['id'] as int,
        code: json['code'] as String,
        name: json['name'] as String,
        academicYear: json['academic_year'] as int? ?? 0,
        totalRequiredHours: (json['total_required_hours'] as num?)?.toDouble() ?? 0,
        groupedBy: json['grouped_by'] as String? ?? 'talent',
        groups: ((json['groups'] as List?) ?? const [])
            .map((e) => CriteriaGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Iterable<CriteriaRequirement> get requirements =>
      groups.expand((g) => g.requirements);

  /// หัวข้อของกลุ่มในชุดนี้เรียกว่าอะไร — ใช้เป็นคำอธิบายในฟอร์ม
  String get groupNoun => groupedBy == 'talent' ? 'Talent / PLO' : 'หน่วยการเรียนรู้';
}

/// รายการเกณฑ์ทุกชุดรวมกัน แผนที่จาก id → รายการ (สำหรับแปลง id ที่เก็บไว้เป็นชื่อ)
Map<int, CriteriaRequirement> requirementsById(List<CriteriaSet> sets) => {
      for (final set in sets)
        for (final requirement in set.requirements) requirement.id: requirement,
    };

/// ชุดเกณฑ์ที่รายการนี้สังกัด (null ถ้าไม่พบ)
CriteriaSet? criteriaSetOfRequirement(List<CriteriaSet> sets, int requirementId) {
  for (final set in sets) {
    if (set.requirements.any((r) => r.id == requirementId)) return set;
  }
  return null;
}
