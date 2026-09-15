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

  /// id ของกลุ่มแชร์เป้า — ฟอร์มแก้ไขใช้เลือกกลุ่มเดิมไว้ให้ (ชื่อซ้ำกันได้ id ไม่ซ้ำ)
  final int? groupId;

  /// ฟิลด์ที่ไม่ได้แสดงบนหน้า แต่ PUT แทนที่ทั้งแถว — ฟอร์มแก้ไขต้องส่งค่าเดิมกลับ
  /// ไม่งั้นแก้ชั่วโมงแล้ว "กฎพิเศษ" ของรายการ (เช่นคู่ Social ≥ 16) หายไปด้วย
  final String? ruleNote;
  final String? organizer;
  final int? minActivities;

  const CriteriaRequirement({
    required this.id,
    required this.name,
    this.requiredHours = 0,
    this.isMandatory = false,
    this.learningUnitName,
    this.groupName,
    this.groupId,
    this.ruleNote,
    this.organizer,
    this.minActivities,
  });

  factory CriteriaRequirement.fromJson(Map<String, dynamic> json) => CriteriaRequirement(
        id: json['id'] as int,
        name: json['name'] as String,
        requiredHours: (json['required_hours'] as num?)?.toDouble() ?? 0,
        isMandatory: json['is_mandatory'] as bool? ?? false,
        learningUnitName: json['learning_unit_name'] as String?,
        groupName: json['group_name'] as String?,
        groupId: json['group_id'] as int?,
        ruleNote: json['rule_note'] as String?,
        organizer: json['organizer'] as String?,
        minActivities: json['min_activities'] as int?,
      );
}

/// กลุ่มแชร์เป้าชั่วโมงของชุด (เช่น Social สองด้านรวม ≥ 16) — มาจาก
/// `requirement_groups` ของชุด จึงรวมกลุ่มที่เพิ่งสร้างและยังไม่มีรายการเป็นสมาชิกด้วย
class RequirementGroupOption {
  final int id;
  final String code;
  final String name;
  final double requiredHours;
  final String? ruleNote;

  const RequirementGroupOption({
    required this.id,
    required this.code,
    required this.name,
    this.requiredHours = 0,
    this.ruleNote,
  });

  factory RequirementGroupOption.fromJson(Map<String, dynamic> json) => RequirementGroupOption(
        id: json['id'] as int,
        code: json['code'] as String? ?? '',
        name: json['name'] as String,
        requiredHours: (json['required_hours'] as num?)?.toDouble() ?? 0,
        ruleNote: json['rule_note'] as String?,
      );

  /// รูปที่ฟอร์มกลุ่มใช้เติมค่าเดิม
  Map<String, dynamic> toFormJson() => {
        'id': id,
        'code': code,
        'name': name,
        'required_hours': requiredHours,
        'rule_note': ruleNote,
      };
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
  final String programType;
  final double totalRequiredHours;
  final String countingRule;

  /// ปีรุ่นแรกที่ชุดนี้เริ่มใช้ — 0 = ครอบรุ่นเก่าทั้งหมดที่ยังไม่มีชุดของตัวเอง
  final int effectiveFromCohort;

  /// true = เกณฑ์ทางการที่ระบบ seed ไว้ · แก้/ลบผ่าน API ไม่ได้ (403)
  final bool isSystem;

  /// "talent" (ชุดที่มี Talent/PLO) หรือ "learning_unit" (ชุดเดิม)
  final String groupedBy;

  /// ข้อความเตือนเมื่อผลรวมชั่วโมงของรายการเกณฑ์ไม่เท่าชั่วโมงรวมของชุด
  final String? hoursWarning;

  final List<CriteriaGroup> groups;

  /// กลุ่มแชร์เป้าทั้งหมดของชุด — แยกจาก [groups] (หัวข้อจัดหน้า) เพราะกลุ่มที่ยังไม่มี
  /// สมาชิกจะไม่โผล่ในรายการเกณฑ์เลย แต่ต้องเลือกได้ในฟอร์มตอนผูกรายการแรกเข้ากลุ่ม
  final List<RequirementGroupOption> requirementGroups;

  const CriteriaSet({
    required this.id,
    required this.code,
    required this.name,
    this.academicYear = 0,
    this.programType = 'regular',
    this.totalRequiredHours = 0,
    this.countingRule = 'min_per_requirement',
    this.effectiveFromCohort = 0,
    this.isSystem = false,
    this.groupedBy = 'talent',
    this.hoursWarning,
    this.groups = const [],
    this.requirementGroups = const [],
  });

  factory CriteriaSet.fromJson(Map<String, dynamic> json) => CriteriaSet(
        id: json['id'] as int,
        code: json['code'] as String,
        name: json['name'] as String,
        academicYear: json['academic_year'] as int? ?? 0,
        programType: json['program_type'] as String? ?? 'regular',
        totalRequiredHours: (json['total_required_hours'] as num?)?.toDouble() ?? 0,
        countingRule: json['counting_rule'] as String? ?? 'min_per_requirement',
        effectiveFromCohort: json['effective_from_cohort'] as int? ?? 0,
        isSystem: json['is_system'] as bool? ?? false,
        groupedBy: json['grouped_by'] as String? ?? 'talent',
        hoursWarning: json['hours_warning'] as String?,
        groups: ((json['groups'] as List?) ?? const [])
            .map((e) => CriteriaGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
        requirementGroups: ((json['requirement_groups'] as List?) ?? const [])
            .map((e) => RequirementGroupOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// "ใช้กับนิสิตรหัส 67 ขึ้นไป" — รหัสนิสิตขึ้นต้นด้วย พ.ศ. สองหลักท้าย
  ///
  /// รุ่น 0 แปลว่าชุดนี้เป็นขั้นล่างสุดของบันได ใช้กับทุกรุ่นที่ยังไม่มีชุดของตัวเอง
  /// จึงเขียนเป็นช่วงแทนที่จะเขียนว่า "รหัส 00 ขึ้นไป" ซึ่งอ่านไม่รู้เรื่อง
  String get audienceLabel {
    if (effectiveFromCohort <= 0) return 'ใช้กับนิสิตรุ่นก่อนหน้าที่ยังไม่มีชุดของตัวเอง';
    final shortCode = (effectiveFromCohort % 100).toString().padLeft(2, '0');
    return 'ใช้กับนิสิตรหัส $shortCode ขึ้นไป (เข้าศึกษา $effectiveFromCohort)';
  }

  /// ป้ายกลุ่มหลักสูตรภาษาไทย
  String get programTypeLabel =>
      programType == 'continuing' ? 'หลักสูตรต่อเนื่อง' : 'หลักสูตรปกติ';

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
