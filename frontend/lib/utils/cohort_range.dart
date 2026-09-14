/// ช่วงรุ่นนิสิตที่ชุดเกณฑ์แต่ละชุด "ใช้กับ" — คำนวณจากรายการชุดจริง ไม่ใช่ค่าที่กรอก
///
/// ชุดเกณฑ์เก็บแค่ `effective_from_cohort` (ปีรุ่นที่เริ่มใช้) ส่วนปลายช่วงขึ้นกับว่า
/// มีชุดที่เริ่มรุ่นถัดไปในหลักสูตรเดียวกันหรือยัง — กติกาเดียวกับ resolver ฝั่ง backend
/// (เลือกชุดที่เริ่มล่าสุดแต่ยังไม่เกินรุ่นของนิสิต) พอเพิ่มชุด 2570 ชุด 2567 ก็หดเหลือ
/// 67–69 เองโดยไม่ต้องแก้ชุดเก่า
library;

import 'dart:math' as math;

import '../models/criteria_set.dart';
import 'format.dart';

/// "67" จากปีรุ่น 2567 (เติมศูนย์: 2605 → "05")
String shortCohort(int cohort) => (cohort % 100).toString().padLeft(2, '0');

/// ปีการศึกษา (พ.ศ.) ปัจจุบัน — เริ่มเดือนมิถุนายน (กฎเดียวกับ `academic_year_for` ของ backend)
int currentAcademicYear([DateTime? now]) {
  final th = thaiNowNaive(now);
  return th.month >= 6 ? th.year + 543 : th.year + 542;
}

class CohortRange {
  const CohortRange({required this.from, this.until});

  /// ปีรุ่นแรก — 0 (หรือต่ำกว่า) = ไม่มีขอบล่าง ครอบรุ่นเก่าทั้งหมด
  final int from;

  /// ปีรุ่นสุดท้าย — null = ไม่มีขอบบน (ยังไม่มีชุดถัดไป)
  final int? until;

  bool get _allCohorts => from <= 0 && until == null;

  /// ช่วงรหัสแบบสั้น: "67–69" · "≤66" · "67 ขึ้นไป" · "67"
  String get codes {
    final end = until;
    if (from <= 0) return end == null ? 'ทุกรุ่น' : '≤${shortCohort(end)}';
    if (end == null) return '${shortCohort(from)} ขึ้นไป';
    if (end <= from) return shortCohort(from);
    return '${shortCohort(from)}–${shortCohort(end)}';
  }

  /// ป้ายหลักบนหัวการ์ด — รหัสนิสิตคงที่ ไม่เลื่อนตามปีการศึกษา
  String get pillLabel => _allCohorts ? 'ใช้กับทุกรุ่น' : 'ใช้กับรหัส $codes';

  /// "นิสิตรหัส 67–69" — ใช้ต่อท้ายประโยค เช่น "มีผลกับนิสิตรหัส 67–69"
  String get studentsLabel => _allCohorts ? 'นิสิตทุกรุ่น' : 'นิสิตรหัส $codes';

  /// ปีที่เข้าศึกษาแบบเต็ม: "เข้าศึกษาปี 2567–2569"
  String get entryYearsLabel {
    final end = until;
    if (from <= 0) return end == null ? 'ทุกปีที่เข้าศึกษา' : 'เข้าศึกษาปี $end ลงไป';
    if (end == null) return 'เข้าศึกษาปี $from ขึ้นไป';
    if (end <= from) return 'เข้าศึกษาปี $from';
    return 'เข้าศึกษาปี $from–$end';
  }

  /// ชั้นปีของรุ่นในช่วงนี้ ณ ปีการศึกษา [academicYear] — ข้อมูลเสริม เพราะเลื่อนทุกปี
  String currentYearLevels(int academicYear) {
    if (from > academicYear) return 'ยังไม่มีนิสิตรุ่นนี้เข้าศึกษา';
    final end = until;
    final youngest = academicYear - math.min(end ?? academicYear, academicYear) + 1;
    if (from <= 0) return 'ปัจจุบัน = ปี $youngest ขึ้นไป';
    final oldest = academicYear - from + 1;
    return youngest == oldest ? 'ปัจจุบัน = ปี $youngest' : 'ปัจจุบัน = ปี $youngest–$oldest';
  }

  @override
  bool operator ==(Object other) =>
      other is CohortRange && other.from == from && other.until == until;

  @override
  int get hashCode => Object.hash(from, until);

  @override
  String toString() => 'CohortRange($from..$until)';
}

/// ช่วงรุ่นของ [set] = [ปีรุ่นของชุดนี้ .. ปีรุ่นของชุดถัดไปที่มากกว่าในหลักสูตรเดียวกัน − 1]
CohortRange cohortRangeOf(CriteriaSet set, Iterable<CriteriaSet> all) {
  int? next;
  for (final other in all) {
    if (other.id == set.id || other.programType != set.programType) continue;
    final cohort = other.effectiveFromCohort;
    if (cohort > set.effectiveFromCohort && (next == null || cohort < next)) next = cohort;
  }
  return CohortRange(from: set.effectiveFromCohort, until: next == null ? null : next - 1);
}

/// ชื่อสั้นของชุดในประโยคพรีวิว — "ชุด 2567" · ชุดขั้นล่างสุดไม่มีปีจึงใช้ชื่อชุดแทน
String criteriaSetShortName(CriteriaSet set) => set.effectiveFromCohort > 0
    ? 'ชุด ${set.effectiveFromCohort}'
    : 'ชุด "${set.name}"';

/// ชุดอื่นที่ช่วงรุ่นเปลี่ยนเพราะชุดที่กำลังกรอก
class CohortRangeChange {
  const CohortRangeChange(this.set, this.before, this.after);
  final CriteriaSet set;
  final CohortRange before;
  final CohortRange after;

  /// ปลายช่วงขยับลง = ชุดเดิม "เหลือ" ช่วงแคบลง · นอกนั้นคือขยาย
  bool get shrinks {
    final newEnd = after.until;
    final oldEnd = before.until;
    return newEnd != null && (oldEnd == null || newEnd < oldEnd);
  }

  String get sentence =>
      '${criteriaSetShortName(set)} ${shrinks ? 'เหลือ' : 'ขยายเป็น'} ${after.codes}';
}

class CohortPreview {
  const CohortPreview({required this.range, this.changes = const [], this.duplicate});

  /// ช่วงของชุดที่กำลังกรอก
  final CohortRange range;
  final List<CohortRangeChange> changes;

  /// ชุดอื่นในหลักสูตรเดียวกันที่เริ่มปีรุ่นเดียวกัน (backend จะปฏิเสธ)
  final CriteriaSet? duplicate;
}

/// ผลของการตั้งปีรุ่น [cohort] ให้ชุด [editing] (null = ชุดใหม่) ต่อทุกชุดใน [sets]
CohortPreview previewCohort({
  required int cohort,
  required String programType,
  required List<CriteriaSet> sets,
  CriteriaSet? editing,
}) {
  final draft = CriteriaSet(
    id: editing?.id ?? -1,
    code: editing?.code ?? '',
    name: editing?.name ?? '',
    programType: programType,
    effectiveFromCohort: cohort,
  );
  final others = [for (final s in sets) if (s.id != draft.id) s];
  CriteriaSet? duplicate;
  for (final s in others) {
    if (s.programType == programType && s.effectiveFromCohort == cohort) duplicate = s;
  }
  final after = [...others, draft];
  return CohortPreview(
    range: cohortRangeOf(draft, after),
    duplicate: duplicate,
    changes: [
      for (final s in others)
        if (cohortRangeOf(s, sets) != cohortRangeOf(s, after))
          CohortRangeChange(s, cohortRangeOf(s, sets), cohortRangeOf(s, after)),
    ],
  );
}

/// ข้อความพรีวิวใต้ช่อง "ปีรุ่นที่เริ่มใช้" — null เมื่อยังกรอกไม่เป็นปีที่ใช้ได้
///
/// ตัวอย่าง: "ชุดนี้จะใช้กับรหัส 70 ขึ้นไป และทำให้ชุด 2567 เหลือ 67–69"
String? cohortPreviewText({
  required String cohortText,
  required String programType,
  required List<CriteriaSet> sets,
  CriteriaSet? editing,
}) {
  final cohort = int.tryParse(cohortText.trim());
  if (cohort == null || cohort < 0 || cohort > 2700) return null;
  final preview = previewCohort(
    cohort: cohort,
    programType: programType,
    sets: sets,
    editing: editing,
  );
  final duplicate = preview.duplicate;
  if (duplicate != null) {
    return 'ปีรุ่น $cohort มี "${duplicate.name}" ใช้อยู่แล้วในกลุ่มหลักสูตรนี้ — เลือกปีอื่น';
  }
  final own = 'ชุดนี้จะ${preview.range.pillLabel}';
  if (preview.changes.isEmpty) return own;
  return '$own และทำให้${preview.changes.map((c) => c.sentence).join(' และ ')}';
}
