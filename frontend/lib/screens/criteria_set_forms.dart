/// ฟอร์มของหน้า "จัดการชุดเกณฑ์" — ชุดเกณฑ์ · Talent · กลุ่มแชร์เป้า · รายการเกณฑ์
///
/// แยกไฟล์จากหน้าจอเพราะหน้าหมวดชั่วโมงยาวอยู่แล้ว และฟอร์มพวกนี้ไม่ต้องรู้อะไร
/// เกี่ยวกับหน้าจอเลย นอกจาก "ชุดไหน" กับ "แก้ของเดิมหรือสร้างใหม่"
library;

import 'package:flutter/material.dart';

import '../models/criteria_set.dart';
import '../models/learning_unit.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../utils/cohort_range.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/dialogs.dart';

/// ป้ายช่องแบบเดียวกันทุกฟอร์ม (label ลอยบนเสมอ เหมือนฟอร์มนิสิต/กิจกรรม)
InputDecoration criteriaDecoration(
  String label, {
  bool required = false,
  String? hint,
  String? helper,
}) =>
    InputDecoration(
      labelText: required ? '$label *' : '$label (ไม่บังคับ)',
      hintText: hint,
      helperText: helper,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    );

/// ตรวจตัวเลขที่ต้องมากกว่า 0 (ชั่วโมง) — ให้ตรงกับ `Field(gt=0)` ฝั่ง backend
String? positiveNumberValidator(String? value) {
  final parsed = double.tryParse((value ?? '').trim());
  if (parsed == null) return 'กรอกตัวเลข';
  if (parsed <= 0) return 'ต้องมากกว่า 0';
  return null;
}

/// ตรวจปีรุ่น (พ.ศ.) ที่ชุดเกณฑ์เริ่มใช้ — ช่วงเดียวกับที่ backend รับ (0–2700)
String? cohortValidator(String? value) {
  final parsed = int.tryParse((value ?? '').trim());
  if (parsed == null) return 'กรอกปี พ.ศ. เช่น 2570';
  if (parsed < 0 || parsed > 2700) return 'ปีรุ่นต้องอยู่ระหว่าง 0–2700';
  return null;
}

// ---------------------------------------------------------------- ชุดเกณฑ์

/// payload ของ POST/PUT `/criteria-sets` — หน้าฟอร์มจัดใหม่ได้ แต่คีย์ 7 ตัวนี้คือสัญญากับ
/// backend ห้ามเพิ่ม/ลด/เปลี่ยนชื่อ
Map<String, dynamic> criteriaSetPayload({
  required String code,
  required String name,
  required String academicYear,
  required String programType,
  required String cohort,
  required String hours,
  required String countingRule,
}) =>
    {
      'code': code.trim(),
      'name': name.trim(),
      'academic_year': int.parse(academicYear.trim()),
      'program_type': programType,
      'effective_from_cohort': int.parse(cohort.trim()),
      'total_required_hours': double.parse(hours.trim()),
      'counting_rule': countingRule,
    };

/// ปุ่มหลักตอนสร้างชุดใหม่ — ชุดเปล่ายังใช้ไม่ได้ จึงบันทึกแล้วพาไปเพิ่มรายการเกณฑ์ต่อทันที
const kSaveAndAddRequirementLabel = 'บันทึก แล้วเพิ่มรายการเกณฑ์';

class CriteriaSetFormDialog extends StatefulWidget {
  const CriteriaSetFormDialog({super.key, this.existing, this.existingSets = const []});

  /// null = สร้างชุดใหม่
  final CriteriaSet? existing;

  /// ชุดที่มีอยู่ทั้งหมด — ใช้พรีวิวว่าปีรุ่นที่กรอกทำให้ช่วงรุ่นของชุดไหนเปลี่ยน
  final List<CriteriaSet> existingSets;

  @override
  State<CriteriaSetFormDialog> createState() => _CriteriaSetFormDialogState();
}

class _CriteriaSetFormDialogState extends State<CriteriaSetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _academicYear;
  late final TextEditingController _cohort;
  late final TextEditingController _hours;
  String _programType = 'regular';
  String _countingRule = 'min_per_requirement';
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _code = TextEditingController(text: e?.code ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _academicYear = TextEditingController(text: '${e?.academicYear ?? ''}');
    _cohort = TextEditingController(text: e == null ? '' : '${e.effectiveFromCohort}');
    _hours = TextEditingController(text: e == null ? '60' : formatNumber(e.totalRequiredHours));
    _programType = e?.programType ?? 'regular';
    _countingRule = e?.countingRule ?? 'min_per_requirement';
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _academicYear.dispose();
    _cohort.dispose();
    _hours.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = criteriaSetPayload(
      code: _code.text,
      name: _name.text,
      academicYear: _academicYear.text,
      programType: _programType,
      cohort: _cohort.text,
      hours: _hours.text,
      countingRule: _countingRule,
    );
    try {
      if (_isNew) {
        final created = await ApiService.create('/criteria-sets', body, (json) => json);
        // ส่ง id ชุดใหม่กลับไป หน้าจอจะเปิดฟอร์มรายการเกณฑ์ของชุดนี้ต่อ
        if (mounted) Navigator.pop(context, created['id'] as int? ?? true);
        return;
      }
      await ApiService.update(
        '/criteria-sets/${widget.existing!.id}',
        body,
        (json) => json,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "ชุดนี้จะใช้กับรหัส 70 ขึ้นไป และทำให้ชุด 2567 เหลือ 67–69" — ช่วงรุ่นไม่ได้กรอก
  /// ตรง ๆ แต่คำนวณจากชุดถัดไป ผู้ดูแลจึงต้องเห็นผลก่อนกดบันทึก
  Widget _cohortPreview(BuildContext context) {
    final text = cohortPreviewText(
      cohortText: _cohort.text,
      programType: _programType,
      sets: widget.existingSets,
      editing: widget.existing,
    );
    if (text == null) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('cohort-preview'),
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.info_outline, size: 16, color: AppColors.blueDark),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.blueDark, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppFormDialog(
      title: _isNew ? 'เพิ่มชุดเกณฑ์ใหม่' : 'แก้ไขชุดเกณฑ์',
      subtitle: _isNew
          ? 'สร้างเกณฑ์การเก็บชั่วโมงสำหรับนิสิตรุ่นใหม่ที่มีโครงสร้างต่างจากเดิม'
          : 'เปลี่ยนปีรุ่นที่เริ่มใช้แล้ว ช่วงรุ่นของชุดข้างเคียงจะปรับตามเอง',
      width: 540,
      submitLabel: _isNew ? kSaveAndAddRequirementLabel : 'บันทึก',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        // บล็อกพระเอก: ปีรุ่นเป็นตัวกำหนดว่าใครใช้ชุดนี้ จึงอยู่บนสุดพร้อมพรีวิวผลที่เกิด
        FormBlock(
          key: const ValueKey('criteria-set-audience-block'),
          hero: true,
          title: 'ชุดนี้ใช้กับนิสิตรุ่นไหน',
          description: 'ปีรุ่นที่เริ่มใช้คือตัวกำหนดว่านิสิตรหัสไหนจะใช้ชุดนี้ · '
              'ระบบคำนวณช่วงที่เหลือให้อัตโนมัติ ไม่ต้องกรอกปีสิ้นสุด',
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('criteria-set-cohort'),
                  controller: _cohort,
                  decoration: criteriaDecoration(
                    'ปีรุ่นที่เริ่มใช้ (พ.ศ.)',
                    required: true,
                    // "เช่น" นำหน้า — hint เลขล้วนดูเหมือนกรอกแล้ว ผู้ใช้เลยไม่พิมพ์และไม่เห็นพรีวิว
                hint: 'เช่น 2570',
                    helper: 'นิสิตที่เข้าศึกษาตั้งแต่ปีนี้เป็นต้นไปจะใช้ชุดนี้ · '
                        'ห้ามซ้ำในกลุ่มหลักสูตรเดียวกัน',
                  ),
                  keyboardType: TextInputType.number,
                  validator: cohortValidator,
                  // พรีวิวสดตามเลขที่พิมพ์
                  onChanged: (_) => setState(() {}),
                ),
                _cohortPreview(context),
              ],
            ),
          ],
        ),
        FormBlock(
          key: const ValueKey('criteria-set-info-block'),
          title: 'ข้อมูลชุดเกณฑ์',
          description: 'ช่องที่มีเครื่องหมาย * จำเป็นต้องกรอก',
          children: [
            TextFormField(
              key: const ValueKey('criteria-set-name'),
              controller: _name,
              decoration: criteriaDecoration(
                'ชื่อชุดเกณฑ์',
                required: true,
                hint: 'เช่น เกณฑ์ 2570 หลักสูตรปกติ (60 ชม.)',
              ),
              validator: requiredValidator,
            ),
            FormFieldRow(
              children: [
                TextFormField(
                  key: const ValueKey('criteria-set-code'),
                  controller: _code,
                  decoration: criteriaDecoration(
                    'รหัสชุด',
                    required: true,
                    hint: 'เช่น 2570-regular',
                    helper: 'ใช้อ้างถึงชุดนี้ในระบบ ห้ามซ้ำ',
                  ),
                  validator: requiredValidator,
                ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('criteria-set-program-type'),
                  initialValue: _programType,
                  isExpanded: true,
                  decoration: criteriaDecoration(
                    'กลุ่มหลักสูตร',
                    required: true,
                    helper: 'ช่วงรุ่นคิดแยกตามกลุ่มหลักสูตร',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'regular', child: Text('หลักสูตรปกติ')),
                    DropdownMenuItem(value: 'continuing', child: Text('หลักสูตรต่อเนื่อง')),
                  ],
                  // เปลี่ยนกลุ่มหลักสูตรแล้วพรีวิวช่วงรุ่นต้องคิดใหม่ด้วย
                  onChanged: (v) => setState(() => _programType = v ?? 'regular'),
                ),
              ],
            ),
            TextFormField(
              key: const ValueKey('criteria-set-academic-year'),
              controller: _academicYear,
              decoration: criteriaDecoration(
                'ปีหลักสูตร (พ.ศ.)',
                required: true,
                // "เช่น" นำหน้า — hint เลขล้วนดูเหมือนกรอกแล้ว ผู้ใช้เลยไม่พิมพ์และไม่เห็นพรีวิว
                hint: 'เช่น 2570',
                helper: 'ปีของเล่มหลักสูตรที่เกณฑ์ชุดนี้อ้างอิง',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                final year = int.tryParse((v ?? '').trim());
                if (year == null) return 'กรอกปี พ.ศ. เช่น 2570';
                if (year < 2500 || year > 2700) return 'ปีหลักสูตรต้องอยู่ระหว่าง 2500–2700';
                return null;
              },
            ),
          ],
        ),
        FormBlock(
          key: const ValueKey('criteria-set-counting-block'),
          title: 'การนับชั่วโมง',
          description: 'ต่อรายการ = ต้องครบทุกรายการ · ต่อหน่วย = ดูยอดรวมของหน่วยการเรียนรู้',
          children: [
            FormFieldRow(
              children: [
                TextFormField(
                  key: const ValueKey('criteria-set-hours'),
                  controller: _hours,
                  decoration: criteriaDecoration(
                    'ชั่วโมงรวมของชุด',
                    required: true,
                    hint: '60',
                    helper: 'ผลรวมของทุกรายการควรเท่ากับเลขนี้ — ไม่เท่าจะมีคำเตือนบนการ์ดชุด',
                  ),
                  keyboardType: TextInputType.number,
                  validator: positiveNumberValidator,
                ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('criteria-set-counting-rule'),
                  initialValue: _countingRule,
                  isExpanded: true,
                  decoration: criteriaDecoration('วิธีนับความครบ', required: true),
                  items: const [
                    DropdownMenuItem(
                      value: 'min_per_requirement',
                      child: Text('ครบตามชั่วโมงของแต่ละรายการ'),
                    ),
                    DropdownMenuItem(
                      value: 'total_per_unit',
                      child: Text('ครบตามยอดรวมของหน่วยการเรียนรู้'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _countingRule = v ?? 'min_per_requirement'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Talent

class TalentFormDialog extends StatefulWidget {
  const TalentFormDialog({super.key, required this.criteriaSetId, this.existing});

  final int criteriaSetId;

  /// ข้อมูล Talent เดิม (id, code, name, plo, sort_order) — null = สร้างใหม่
  final Map<String, dynamic>? existing;

  @override
  State<TalentFormDialog> createState() => _TalentFormDialogState();
}

class _TalentFormDialogState extends State<TalentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _plo;
  late final TextEditingController _sortOrder;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _code = TextEditingController(text: e?['code'] as String? ?? '');
    _name = TextEditingController(text: e?['name'] as String? ?? '');
    _plo = TextEditingController(text: e?['plo'] as String? ?? '');
    _sortOrder = TextEditingController(text: '${e?['sort_order'] ?? 0}');
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _plo.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final plo = _plo.text.trim();
    final body = {
      'code': _code.text.trim(),
      'name': _name.text.trim(),
      'plo': plo.isEmpty ? null : plo,
      'sort_order': int.tryParse(_sortOrder.text.trim()) ?? 0,
    };
    try {
      if (widget.existing == null) {
        await ApiService.create(
          '/criteria-sets/${widget.criteriaSetId}/talents',
          body,
          (json) => json,
        );
      } else {
        await ApiService.update('/talents/${widget.existing!['id']}', body, (json) => json);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFormDialog(
      title: widget.existing == null ? 'เพิ่ม Talent' : 'แก้ไข Talent',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        const FormSectionHeader('Talent / PLO', first: true),
        TextFormField(
          controller: _code,
          decoration: criteriaDecoration('รหัส', required: true, hint: 'เช่น glocal'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _name,
          decoration:
              criteriaDecoration('ชื่อ', required: true, hint: 'เช่น TSU Glocal Talent'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _plo,
          decoration: criteriaDecoration('PLO', hint: 'เช่น PLO 1'),
        ),
        TextFormField(
          controller: _sortOrder,
          decoration: criteriaDecoration('ลำดับการแสดง', required: true, hint: '1'),
          keyboardType: TextInputType.number,
          validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'กรอกตัวเลข' : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- กลุ่มแชร์เป้า

class RequirementGroupFormDialog extends StatefulWidget {
  const RequirementGroupFormDialog({
    super.key,
    required this.criteriaSetId,
    this.existing,
  });

  final int criteriaSetId;
  final Map<String, dynamic>? existing;

  @override
  State<RequirementGroupFormDialog> createState() => _RequirementGroupFormDialogState();
}

class _RequirementGroupFormDialogState extends State<RequirementGroupFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _hours;
  late final TextEditingController _ruleNote;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _code = TextEditingController(text: e?['code'] as String? ?? '');
    _name = TextEditingController(text: e?['name'] as String? ?? '');
    _hours = TextEditingController(
      text: e == null ? '' : formatNumber((e['required_hours'] as num).toDouble()),
    );
    _ruleNote = TextEditingController(text: e?['rule_note'] as String? ?? '');
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _hours.dispose();
    _ruleNote.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final note = _ruleNote.text.trim();
    final body = {
      'code': _code.text.trim(),
      'name': _name.text.trim(),
      'required_hours': double.parse(_hours.text.trim()),
      'rule_note': note.isEmpty ? null : note,
    };
    try {
      if (widget.existing == null) {
        await ApiService.create(
          '/criteria-sets/${widget.criteriaSetId}/requirement-groups',
          body,
          (json) => json,
        );
      } else {
        await ApiService.update(
          '/requirement-groups/${widget.existing!['id']}',
          body,
          (json) => json,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFormDialog(
      title: widget.existing == null ? 'เพิ่มกลุ่มแชร์เป้าชั่วโมง' : 'แก้ไขกลุ่มแชร์เป้าชั่วโมง',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        const FormSectionHeader(
          'กลุ่มแชร์เป้าชั่วโมง',
          note: 'รายการในกลุ่มเดียวกันตรวจความครบที่ "ยอดรวมของกลุ่ม" ไม่ใช่ทีละรายการ',
          first: true,
        ),
        TextFormField(
          controller: _code,
          decoration: criteriaDecoration('รหัสกลุ่ม', required: true, hint: 'เช่น social-16'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _name,
          decoration: criteriaDecoration('ชื่อกลุ่ม', required: true),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _hours,
          decoration: criteriaDecoration('ชั่วโมงรวมของกลุ่ม', required: true, hint: '16'),
          keyboardType: TextInputType.number,
          validator: positiveNumberValidator,
        ),
        TextFormField(
          controller: _ruleNote,
          decoration: criteriaDecoration(
            'คำอธิบายกฎ',
            hint: 'เช่น เลือกด้านเดียวหรือรวมสองด้าน',
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- รายการเกณฑ์

/// payload ของ POST/PUT รายการเกณฑ์
///
/// PUT แทนที่ทั้งแถว — ฟิลด์ที่ฟอร์มไม่มีช่องให้แก้ (organizer / min_activities) จึงต้องส่ง
/// ค่าเดิมจาก [existing] กลับไป ไม่งั้นแก้ชั่วโมงรายการเดียวแล้วค่าพวกนั้นหายเงียบ ๆ
/// (ชุดทางการแก้ได้แล้ว รายการที่มีค่าเหล่านี้จึงถูกแก้ผ่านฟอร์มนี้ได้จริง)
Map<String, dynamic> requirementFormPayload({
  required String name,
  required int? learningUnitId,
  required int? talentId,
  required int? groupId,
  required bool isMandatory,
  required String hours,
  required String ruleNote,
  Map<String, dynamic>? existing,
}) {
  final note = ruleNote.trim();
  return {
    'name': name.trim(),
    'learning_unit_id': learningUnitId,
    'talent_id': talentId,
    'group_id': groupId,
    'is_mandatory': isMandatory,
    'required_hours': double.parse(hours.trim()),
    'rule_note': note.isEmpty ? null : note,
    'organizer': existing?['organizer'],
    'min_activities': existing?['min_activities'],
  };
}

class RequirementFormDialog extends StatefulWidget {
  const RequirementFormDialog({
    super.key,
    required this.criteriaSetId,
    required this.learningUnits,
    this.talents = const [],
    this.groups = const [],
    this.existing,
  });

  final int criteriaSetId;
  final List<LearningUnit> learningUnits;

  /// Talent ของชุดนี้ (id + name) — ว่างได้ ถ้าชุดนี้ไม่ได้จัดกลุ่มด้วย Talent
  final List<Map<String, dynamic>> talents;

  /// กลุ่มแชร์เป้าของชุดนี้ (id + name)
  final List<Map<String, dynamic>> groups;

  final Map<String, dynamic>? existing;

  @override
  State<RequirementFormDialog> createState() => _RequirementFormDialogState();
}

class _RequirementFormDialogState extends State<RequirementFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _hours;
  late final TextEditingController _ruleNote;
  int? _learningUnitId;
  int? _talentId;
  int? _groupId;
  bool _isMandatory = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] as String? ?? '');
    _hours = TextEditingController(
      text: e == null ? '' : formatNumber((e['required_hours'] as num).toDouble()),
    );
    _ruleNote = TextEditingController(text: e?['rule_note'] as String? ?? '');
    _learningUnitId = e?['learning_unit_id'] as int? ??
        (widget.learningUnits.isNotEmpty ? widget.learningUnits.first.id : null);
    // ค่าเดิมที่ไม่มีในตัวเลือกแล้ว (เช่นกลุ่มถูกลบไประหว่างเปิดหน้า) ต้องตกเป็น "ไม่ผูก"
    // ไม่งั้น DropdownButtonFormField จะ assert ล้มทั้งฟอร์ม
    final talentId = e?['talent_id'] as int?;
    _talentId = widget.talents.any((t) => t['id'] == talentId) ? talentId : null;
    final groupId = e?['group_id'] as int?;
    _groupId = widget.groups.any((g) => g['id'] == groupId) ? groupId : null;
    _isMandatory = e?['is_mandatory'] as bool? ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _hours.dispose();
    _ruleNote.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_learningUnitId == null) {
      setState(() => _error = 'ต้องเลือกหน่วยการเรียนรู้');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = requirementFormPayload(
      name: _name.text,
      learningUnitId: _learningUnitId,
      talentId: _talentId,
      groupId: _groupId,
      isMandatory: _isMandatory,
      hours: _hours.text,
      ruleNote: _ruleNote.text,
      existing: widget.existing,
    );
    try {
      if (widget.existing == null) {
        await ApiService.create(
          '/criteria-sets/${widget.criteriaSetId}/requirements',
          body,
          (json) => json,
        );
      } else {
        await ApiService.update(
          '/requirements/${widget.existing!['id']}',
          body,
          (json) => json,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFormDialog(
      title: widget.existing == null ? 'เพิ่มรายการเกณฑ์' : 'แก้ไขรายการเกณฑ์',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        const FormSectionHeader(
          'รายการเกณฑ์',
          note: 'ช่องที่มีเครื่องหมาย * จำเป็นต้องกรอก',
          first: true,
        ),
        TextFormField(
          controller: _name,
          decoration: criteriaDecoration('ชื่อรายการ', required: true),
          validator: requiredValidator,
        ),
        DropdownButtonFormField<int>(
          initialValue: _learningUnitId,
          isExpanded: true,
          decoration: criteriaDecoration(
            'หน่วยการเรียนรู้',
            required: true,
            helper: 'ชั่วโมงของรายการนี้จะถูกนับเข้าหน่วยนี้',
          ),
          items: [
            for (final unit in widget.learningUnits)
              DropdownMenuItem(value: unit.id, child: Text('${unit.code}. ${unit.name}')),
          ],
          onChanged: (v) => setState(() => _learningUnitId = v),
        ),
        TextFormField(
          controller: _hours,
          decoration: criteriaDecoration('ชั่วโมงที่ต้องได้', required: true, hint: '4'),
          keyboardType: TextInputType.number,
          validator: positiveNumberValidator,
        ),
        SwitchListTile(
          value: _isMandatory,
          onChanged: (v) => setState(() => _isMandatory = v),
          title: const Text('เป็นรายการบังคับ'),
          subtitle: const Text('บังคับ = ต้องครบทุกตัว ไม่ครบถือว่าไม่ผ่านเกณฑ์'),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (widget.talents.isNotEmpty)
          DropdownButtonFormField<int?>(
            initialValue: _talentId,
            isExpanded: true,
            decoration: criteriaDecoration('อยู่ใน Talent'),
            items: [
              const DropdownMenuItem(value: null, child: Text('ไม่ผูกกับ Talent ใด')),
              for (final talent in widget.talents)
                DropdownMenuItem(
                  value: talent['id'] as int,
                  child: Text(talent['name'] as String),
                ),
            ],
            onChanged: (v) => setState(() => _talentId = v),
          ),
        if (widget.groups.isNotEmpty)
          DropdownButtonFormField<int?>(
            initialValue: _groupId,
            isExpanded: true,
            decoration: criteriaDecoration(
              'กลุ่มแชร์เป้าชั่วโมง',
              helper: 'อยู่ในกลุ่ม = ตรวจความครบที่ยอดรวมของกลุ่ม ไม่ใช่ที่รายการนี้ตัวเดียว',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('ไม่อยู่ในกลุ่มใด')),
              for (final group in widget.groups)
                DropdownMenuItem(
                  value: group['id'] as int,
                  child: Text(group['name'] as String),
                ),
            ],
            onChanged: (v) => setState(() => _groupId = v),
          ),
        TextFormField(
          controller: _ruleNote,
          decoration: criteriaDecoration('คำอธิบายกฎ'),
        ),
      ],
    );
  }
}

/// 4.0 → "4" แต่ 4.5 ยังเป็น "4.5" — ใช้เติมค่าเดิมลงช่องกรอก
String formatNumber(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toString();
