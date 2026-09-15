import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/criteria_set.dart';
import '../models/learning_unit.dart';
import '../models/hour_category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../utils/cohort_range.dart';
import '../utils/format.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/search_field.dart';
import '../widgets/status_chip.dart';
import 'criteria_set_forms.dart';
import 'app_shell.dart';

/// หน้า "หมวดชั่วโมงกิจกรรม" (admin เท่านั้น) — แสดงชุดเกณฑ์ **ทุกชุดพร้อมกัน** และแก้ได้ทุกชุด
///
/// นิสิตที่เรียนอยู่ตอนนี้ใช้เกณฑ์คนละชุดกันตามรหัส ผู้ดูแลจึงต้องเห็นทุกชุดในหน้าเดียว
/// ไม่งั้นจะตอบคำถามนิสิตปี 4 ด้วยโครงสร้างของปี 1 โดยไม่รู้ตัว:
///
/// * **ชุดทางการ** ที่ seed ไว้ (2567 = Talent/PLO → รายการ · เกณฑ์เดิม = หน่วยการเรียนรู้ →
///   รายการ) — เพิ่ม/แก้/ลบ Talent · กลุ่มแชร์เป้า · รายการเกณฑ์ได้ แต่ไม่มีปุ่มแก้ชื่อ/ปีรุ่น
///   หรือลบทั้งชุด (backend ตอบ 403 — ปีรุ่นคือขั้นบันไดที่นิสิตทั้งรุ่นแมปอยู่)
/// * **ชุดของผู้ดูแล** — แก้/ลบได้ทั้งชุด
///
/// ทุกชุดอ่านจาก `GET /criteria-sets` และเขียนผ่าน CRUD ชุดเดียวกัน (`/talents`,
/// `/requirement-groups`, `/requirements`) รวมเกณฑ์เดิมด้วย — เดิมการ์ดเกณฑ์เดิมแก้ตาราง
/// hourcategory ผ่าน `/hour-categories` ซึ่งไม่ใช่รายการที่ใช้วัดนิสิตจริง (ชุด legacy-2566)
/// หน้านี้จึงเลิกใช้ทางนั้น · API/ตาราง hourcategory ยังอยู่ (ฟอร์มกิจกรรมใช้เป็นหมวดโครงเดิม)
///
/// ไม่มีการแบ่งหน้า: endpoint คืนต้นไม้ทั้งก้อน และการแบ่งหน้าจะตัดรายการขาดจากหัวข้อ
/// ช่องค้นหาจึงกรองในเครื่องแทน
class HourCategoriesScreen extends StatefulWidget {
  const HourCategoriesScreen({super.key});

  @override
  State<HourCategoriesScreen> createState() => _HourCategoriesScreenState();
}

class _HourCategoriesScreenState extends State<HourCategoriesScreen> {
  List<CriteriaSet> _criteriaSets = [];
  List<LearningUnit> _learningUnits = [];
  bool _loading = false;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final criteriaSets = await ApiService.fetchList('/criteria-sets', CriteriaSet.fromJson);
      final units = await ApiService.fetchList('/learning-units', LearningUnit.fromJson);
      if (!mounted) return;
      setState(() {
        _criteriaSets = criteriaSets;
        _learningUnits = units;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// ชุดทางการ เรียงรุ่นใหม่ขึ้นก่อน (2567 → เกณฑ์เดิม) — ลำดับเดียวกับป้าย "ชุดที่ N"
  List<CriteriaSet> get _officialSets => _criteriaSets.where((s) => s.isSystem).toList()
    ..sort((a, b) => b.effectiveFromCohort.compareTo(a.effectiveFromCohort));

  /// ชุดที่ผู้ดูแลสร้างเอง (แก้/ลบได้ทั้งชุด)
  List<CriteriaSet> get _customSets =>
      _criteriaSets.where((s) => !s.isSystem).toList();

  /// เปิดฟอร์มแล้วโหลดใหม่ถ้าบันทึกสำเร็จ — ใช้ร่วมกันทุกฟอร์มของชุดเกณฑ์
  ///
  /// ฟอร์มสร้างชุดใหม่ ("บันทึก แล้วเพิ่มรายการเกณฑ์") ส่ง id ของชุดกลับมาแทน true
  /// → โหลดใหม่แล้วเปิดฟอร์มรายการเกณฑ์ของชุดนั้นต่อทันที (ชุดเปล่ายังใช้นับชั่วโมงไม่ได้)
  Future<void> _openCriteriaForm(Widget dialog) async {
    final saved = await showDialog<Object?>(context: context, builder: (_) => dialog);
    if (saved == true || saved is int) await _load();
    if (saved is! int || !mounted) return;
    CriteriaSet? created;
    for (final set in _criteriaSets) {
      if (set.id == saved) created = set;
    }
    await _openCriteriaForm(RequirementFormDialog(
      criteriaSetId: saved,
      learningUnits: _learningUnits,
      talents: created == null ? const [] : _talentOptions(created),
      groups: created == null ? const [] : requirementGroupOptions(created),
    ));
  }

  /// ลบของในชุดเกณฑ์ — ข้อความ 400 ของ backend ("มีรายการเกณฑ์ n รายการใช้กลุ่มนี้อยู่")
  /// คือคำอธิบายที่ผู้ใช้ต้องเห็น จึงโยนขึ้น snackbar ตรง ๆ
  Future<void> _deleteCriteriaThing(
    String path, {
    required String title,
    required String message,
    required String detail,
  }) async {
    final confirmed = await confirmAction(
      context,
      title: title,
      message: message,
      detail: detail,
      confirmLabel: 'ลบ',
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (confirmed != true) return;
    await _runDelete(path);
  }

  /// ลบแล้วโหลดใหม่ — ข้อความ 400 ของ backend ("มีกิจกรรมผูกอยู่ n รายการ")
  /// คือคำอธิบายที่ผู้ใช้ต้องเห็น จึงโยนขึ้น snackbar ตรง ๆ
  Future<void> _runDelete(String path) async {
    try {
      await ApiService.delete(path);
      await _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!authService.isAdmin) {
      return const AppShell(
        activeId: 'hour_categories',
        body: Center(child: Text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้')),
      );
    }

    final official = _officialSets;
    return AdminPage(
      activeId: 'hour_categories',
      title: 'หมวดชั่วโมงกิจกรรม',
      subtitle: 'เกณฑ์แยกตามรุ่นนิสิต · ปุ่มเพิ่ม/แก้ของแต่ละชุดอยู่ในกรอบของชุดนั้น',
      // ปุ่มระดับหน้ามีปุ่มเดียว = สร้างเกณฑ์ของรุ่นใหม่ · ปุ่มที่แก้ของในชุดใดชุดหนึ่ง
      // อยู่ในกรอบของชุดนั้นเท่านั้น ไม่งั้นผู้ดูแลเดาไม่ออกว่ากดแล้วของใหม่ไปโผล่ในชุดไหน
      actions: [
        FilledButton.icon(
          onPressed: () =>
              _openCriteriaForm(CriteriaSetFormDialog(existingSets: _criteriaSets)),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(kAddCriteriaSetLabel),
        ),
      ],
      filters: [
        DebouncedSearchField(
          label: 'ค้นหาหัวข้อ/รายการเกณฑ์',
          onSearch: (value) => setState(() => _search = value),
        ),
        AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: _load),
      ],
      busy: _loading && _criteriaSets.isNotEmpty,
      child: _loading && _criteriaSets.isEmpty
          ? const LoadingState(message: 'กำลังโหลดโครงสร้างเกณฑ์...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  children: [
                    if (_criteriaSets.isEmpty)
                      _sectionMessage('ยังไม่มีชุดเกณฑ์ในระบบ — กดปุ่ม "$kAddCriteriaSetLabel" ด้านบน'),
                    for (final (index, set) in official.indexed) ...[
                      if (index > 0) const SizedBox(height: AppSpacing.xl),
                      _officialSetSection(set, index: index),
                    ],
                    for (final set in _customSets) ...[
                      const SizedBox(height: AppSpacing.xl),
                      _customSetSection(set),
                    ],
                    if (_criteriaSets.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      CriteriaRangeHint(
                        text: criteriaRangeHint(_criteriaSets, currentAcademicYear()),
                      ),
                    ],
                  ],
                ),
    );
  }

  // ---------------- ชุดทางการ (2567 / เกณฑ์เดิม) — แก้ของข้างในได้ ----------------

  Widget _officialSetSection(CriteriaSet set, {required int index}) {
    return CriteriaSetCard(
      key: ValueKey('criteria-set-card-${set.code}'),
      header: officialCriteriaSectionHeader(
        set,
        badge: 'ชุดที่ ${index + 1}',
        allSets: _criteriaSets,
        // ชุดที่จัดกลุ่มด้วยหน่วยการเรียนรู้ (เกณฑ์เดิม) ไม่มีปุ่ม Talent — backend จัดกลุ่ม
        // ด้วย Talent ทันทีที่ชุดมี Talent สักตัว กดเพิ่มทีเดียวโครงเกณฑ์เดิมจะเปลี่ยนทั้งหน้า
        onAddTalent: set.groupedBy == 'talent'
            ? () => _openCriteriaForm(TalentFormDialog(criteriaSetId: set.id))
            : null,
        onAddGroup: () => _openCriteriaForm(RequirementGroupFormDialog(criteriaSetId: set.id)),
        onAddRequirement: () => _openCriteriaForm(_newRequirementForm(set)),
      ),
      children: _setContents(set),
    );
  }

  // ---------------- ชุดที่ผู้ดูแลสร้างเอง (แก้/ลบได้ทั้งชุด) ----------------

  Widget _customSetSection(CriteriaSet set) {
    return CriteriaSetCard(
      key: ValueKey('criteria-set-card-${set.code}'),
      header: customCriteriaSectionHeader(
        set,
        allSets: _criteriaSets,
        onEdit: () => _openCriteriaForm(
          CriteriaSetFormDialog(existing: set, existingSets: _criteriaSets),
        ),
        onDelete: () => _deleteCriteriaThing(
          '/criteria-sets/${set.id}',
          title: 'ยืนยันการลบชุดเกณฑ์',
          message: 'ต้องการลบชุดเกณฑ์ "${set.name}" ใช่หรือไม่?',
          detail: 'Talent และรายการเกณฑ์ในชุดจะถูกลบไปด้วย · '
              'ลบไม่ได้ถ้ามีนิสิตใช้ชุดนี้อยู่หรือมีกิจกรรมผูกกับรายการเกณฑ์',
        ),
        onAddTalent: () => _openCriteriaForm(TalentFormDialog(criteriaSetId: set.id)),
        onAddGroup: () => _openCriteriaForm(RequirementGroupFormDialog(criteriaSetId: set.id)),
        onAddRequirement: () => _openCriteriaForm(_newRequirementForm(set)),
      ),
      children: _setContents(set),
    );
  }

  RequirementFormDialog _newRequirementForm(CriteriaSet set) => RequirementFormDialog(
        criteriaSetId: set.id,
        learningUnits: _learningUnits,
        talents: _talentOptions(set),
        groups: requirementGroupOptions(set),
      );

  /// เนื้อหาในการ์ดของชุด — เหมือนกันทุกชุด (ทางการหรือของผู้ดูแล): กลุ่มแชร์เป้า + หัวข้อที่แก้ได้
  List<Widget> _setContents(CriteriaSet set) {
    final groups = filterCriteriaGroups(set.groups, _search);
    return [
      if (set.requirementGroups.isNotEmpty) _sharedTargetGroups(context, set),
      if (groups.isEmpty)
        _sectionMessage(
          _search.isEmpty
              ? 'ยังไม่มีรายการเกณฑ์ในชุดนี้ — กดปุ่ม "เพิ่มรายการเกณฑ์" ด้านบน'
              : 'ไม่พบรายการที่ตรงกับคำค้นในชุดนี้',
        )
      else
        for (final (index, group) in groups.indexed) _criteriaGroupTile(set, group, index: index),
    ];
  }

  /// หัวข้อ Talent/PLO หรือหน่วยการเรียนรู้ พร้อมรายการเกณฑ์ที่มีปุ่มแก้/ลบในแต่ละแถว
  Widget _criteriaGroupTile(CriteriaSet set, CriteriaGroup group, {required int index}) {
    return CriteriaGroupTile(
      key: ValueKey('criteria-group-${set.id}-${group.key}-$_search'),
      name: group.name,
      chip: group.subtitle,
      countLabel: '${group.requirements.length} รายการ',
      hours: criteriaGroupTargetHours(group, set.requirementGroups),
      rules: sharedTargetRules(group, set.requirementGroups),
      // ชุด Talent กางหัวข้อแรกไว้ให้เห็นหน้าตารายการ · ตอนค้นหากางทุกหัวข้อให้เห็นสิ่งที่ตรง
      initiallyExpanded: _search.isNotEmpty || (index == 0 && set.groupedBy == 'talent'),
      children: [
        for (final (i, requirement) in group.requirements.indexed)
          CriteriaRequirementRow(
            index: i,
            name: requirement.name,
            subtitle: requirementSubtitle(requirement),
            mandatory: requirement.isMandatory,
            hours: requirement.requiredHours,
            trailing: _requirementActions(set, group, requirement),
          ),
      ],
    );
  }

  /// Talent ของชุดนี้ในรูปที่ฟอร์มรายการเกณฑ์ใช้เลือกได้
  ///
  /// `GET /criteria-sets` คืนกลุ่มมาแบบจัดหน้าไว้แล้ว (key เป็น "talent:3") จึงถอด id
  /// กลับออกมาจาก key แทนที่จะยิง API เพิ่มอีกเส้นเพื่อเอาแค่ id กับชื่อ · ชุดที่จัดกลุ่มด้วย
  /// หน่วยการเรียนรู้ (key "unit:N") ได้รายการว่าง ฟอร์มจึงไม่แสดงช่อง Talent
  List<Map<String, dynamic>> _talentOptions(CriteriaSet set) => [
        for (final g in set.groups)
          if (talentIdOfGroup(g) != null) {'id': talentIdOfGroup(g), 'name': g.name},
      ];

  /// กลุ่มแชร์เป้าของชุด พร้อมปุ่มแก้/ลบ — กลุ่มที่เพิ่งสร้างยังไม่มีสมาชิกจะไม่โผล่
  /// ในหัวข้อรายการเกณฑ์เลย ถ้าไม่แสดงตรงนี้ผู้ดูแลจะไม่รู้ว่าสร้างสำเร็จแล้ว
  Widget _sharedTargetGroups(BuildContext context, CriteriaSet set) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.xs, AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('กลุ่มแชร์เป้าชั่วโมง', style: theme.textTheme.titleSmall),
          for (final group in set.requirementGroups)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${group.name} — รวม ≥ ${formatHours(group.requiredHours)} ชม.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          _groupMemberSummary(set, group),
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.edit,
                    size: 28,
                    tooltip: 'แก้ไขกลุ่มแชร์เป้า',
                    onPressed: () => _openCriteriaForm(RequirementGroupFormDialog(
                      criteriaSetId: set.id,
                      existing: group.toFormJson(),
                    )),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppIconButton(
                    icon: Icons.delete,
                    size: 28,
                    danger: true,
                    tooltip: 'ลบกลุ่มแชร์เป้า',
                    onPressed: () => _deleteCriteriaThing(
                      '/requirement-groups/${group.id}',
                      title: 'ยืนยันการลบกลุ่มแชร์เป้า',
                      message: 'ต้องการลบกลุ่ม "${group.name}" ใช่หรือไม่?',
                      detail: 'ลบไม่ได้ถ้ายังมีรายการเกณฑ์อยู่ในกลุ่มนี้',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _groupMemberSummary(CriteriaSet set, RequirementGroupOption group) {
    final members = set.requirements.where((r) => r.groupId == group.id).length;
    return members == 0
        ? 'ยังไม่มีรายการในกลุ่ม — ผูกได้จากฟอร์มรายการเกณฑ์'
        : 'รายการในกลุ่ม $members รายการ · ตรวจความครบที่ยอดรวมของกลุ่ม';
  }

  /// ปุ่มแก้/ลบท้ายแถวรายการเกณฑ์ — ใช้ฟอร์มและ endpoint เดียวกันทุกชุด
  List<Widget> _requirementActions(
    CriteriaSet set,
    CriteriaGroup group,
    CriteriaRequirement requirement,
  ) =>
      [
        AppIconButton(
          icon: Icons.edit,
          size: 28,
          tooltip: 'แก้ไขรายการเกณฑ์',
          onPressed: () => _openCriteriaForm(RequirementFormDialog(
            criteriaSetId: set.id,
            learningUnits: _learningUnits,
            talents: _talentOptions(set),
            groups: requirementGroupOptions(set),
            existing: {
              'id': requirement.id,
              'name': requirement.name,
              'required_hours': requirement.requiredHours,
              'is_mandatory': requirement.isMandatory,
              'learning_unit_id': _unitIdByName(requirement.learningUnitName),
              // ต้องส่งค่าเดิมกลับไปด้วย — PUT แทนที่ทั้งแถว ถ้าขาดไป กดบันทึกเฉย ๆ
              // ก็หลุดออกจากกลุ่ม/Talent โดยไม่รู้ตัว
              'talent_id': talentIdOfGroup(group),
              'group_id': requirement.groupId,
              'rule_note': requirement.ruleNote,
              'organizer': requirement.organizer,
              'min_activities': requirement.minActivities,
            },
          )),
        ),
        AppIconButton(
          icon: Icons.delete,
          size: 28,
          danger: true,
          tooltip: 'ลบรายการเกณฑ์',
          onPressed: () => _deleteCriteriaThing(
            '/requirements/${requirement.id}',
            title: 'ยืนยันการลบรายการเกณฑ์',
            message: 'ต้องการลบ "${requirement.name}" ใช่หรือไม่?',
            detail: 'ลบไม่ได้ถ้ามีกิจกรรมผูกกับรายการนี้อยู่ · มีผลกับการวัดนิสิตของชุดนี้ทันที',
          ),
        ),
      ];

  /// id ของหน่วยการเรียนรู้จากชื่อ — payload อ่านส่งมาเป็นชื่อ ไม่ใช่ id
  int? _unitIdByName(String? name) {
    if (name == null) return null;
    for (final unit in _learningUnits) {
      if (unit.name == name) return unit.id;
    }
    return null;
  }

  Widget _sectionMessage(String message) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
      );
}

/// id ของ Talent จากกุญแจหัวข้อ ("talent:3" → 3) · หัวข้ออื่น/"talent:none" → null
int? talentIdOfGroup(CriteriaGroup group) =>
    group.key.startsWith('talent:') ? int.tryParse(group.key.substring(7)) : null;

/// ตัวเลือก "กลุ่มแชร์เป้าชั่วโมง" ในฟอร์มรายการเกณฑ์ — ทุกกลุ่มของชุด รวมกลุ่มที่เพิ่ง
/// สร้างและยังไม่มีสมาชิก (ไม่งั้นผูกรายการแรกเข้ากลุ่มใหม่ไม่ได้เลย)
List<Map<String, dynamic>> requirementGroupOptions(CriteriaSet set) => [
      for (final group in set.requirementGroups)
        {
          'id': group.id,
          'name': '${group.name} (รวม ≥ ${formatHours(group.requiredHours)} ชม.)',
        },
    ];

/// กลุ่มเกณฑ์ที่ตรงคำค้น — เก็บกลุ่มไว้ถ้าชื่อกลุ่มตรง หรือมีรายการข้างในตรง
///
/// กติกาเดียวกับการกรองหมวดในส่วนเกณฑ์เดิม เพื่อให้พิมพ์คำเดียวแล้วสองส่วนตอบ
/// เหมือนกัน ไม่ใช่ส่วนหนึ่งหาย อีกส่วนยังอยู่
List<CriteriaGroup> filterCriteriaGroups(List<CriteriaGroup> groups, String search) {
  if (search.isEmpty) return groups;
  final needle = search.toLowerCase();
  return groups
      .where((g) =>
          g.name.toLowerCase().contains(needle) ||
          g.requirements.any((r) => r.name.toLowerCase().contains(needle)))
      .toList();
}

/// ปุ่มหลักของหน้า — สร้างเกณฑ์ของรุ่นใหม่ (ปุ่มเดียวบนหัวข้อหน้า)
const kAddCriteriaSetLabel = 'เพิ่มชุดเกณฑ์ใหม่';

/// บรรทัดรองใต้ชื่อชุด — ปีที่เข้าศึกษาแบบเต็ม + (ชั้นปีตอนนี้) · กลุ่มหลักสูตร
///
/// ตัวหลักคือป้ายรหัสบนหัวการ์ด (คงที่ทุกปี) ชั้นปีอยู่ในวงเล็บเพราะเลื่อนทุกปีการศึกษา
String criteriaAudience(CohortRange range, int academicYear, {String? programTypeLabel}) =>
    '${range.entryYearsLabel} (${range.currentYearLevels(academicYear)})'
    '${programTypeLabel == null ? '' : ' · $programTypeLabel'}';

/// บรรทัดช่วยจำท้ายหน้า — ยกตัวอย่างด้วยปีรุ่นถัดไปจริง และผลที่เกิดกับชุดเดิมจริง
String criteriaRangeHint(List<CriteriaSet> sets, int academicYear) {
  final latest = sets
      .where((s) => s.programType == 'regular')
      .fold<int>(0, (m, s) => math.max(m, s.effectiveFromCohort));
  final example = math.max(academicYear + 1, latest + 1);
  final preview = previewCohort(cohort: example, programType: 'regular', sets: sets);
  final adjust = preview.changes.isEmpty
      ? ''
      : 'ระบบจะปรับ${preview.changes.map((c) => c.sentence).join(' และ ')} ให้อัตโนมัติ และ';
  return 'อยากได้เกณฑ์รุ่นใหม่ (เช่น $example)? กด "$kAddCriteriaSetLabel" '
      'แล้วตั้ง "ปีรุ่นที่เริ่มใช้ = $example" — $adjustรหัส ${preview.range.codes} '
      'เข้าชุดใหม่เอง โดยไม่ต้องแก้ชุดเก่า';
}

class CriteriaRangeHint extends StatelessWidget {
  const CriteriaRangeHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('criteria-range-hint'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.muted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

/// ป้ายสั้นของวิธีนับความครบ — ใช้ในการ์ด metric ใต้หัวชุด
String countingRuleShortLabel(String rule) =>
    rule == 'total_per_unit' ? 'ต่อหน่วย' : 'ต่อรายการ';

/// ตัวเลขย่อหนึ่งใบใต้หัวการ์ดชุดเกณฑ์ ("60 ชม." / "ชั่วโมงรวม")
class CriteriaMetric {
  const CriteriaMetric(this.value, this.label);
  final String value;
  final String label;
}

/// metric 3 ใบของชุดเกณฑ์: ชั่วโมงรวม · จำนวนหัวข้อ (Talent หรือหน่วย) · วิธีนับความครบ
List<CriteriaMetric> criteriaSetMetrics(CriteriaSet set) => [
      CriteriaMetric('${formatHours(set.totalRequiredHours)} ชม.', 'ชั่วโมงรวม'),
      CriteriaMetric(
        '${set.groups.length} ${set.groupedBy == 'talent' ? 'กลุ่ม' : 'หน่วย'}',
        set.groupNoun,
      ),
      CriteriaMetric(countingRuleShortLabel(set.countingRule), 'วิธีนับความครบ'),
    ];

/// รายการในหัวข้อที่อยู่กลุ่มแชร์เป้าเดียวกัน — กุญแจคือ id กลุ่ม (หรือชื่อ ถ้า payload ไม่มี id)
Map<Object, List<CriteriaRequirement>> _sharedMembers(CriteriaGroup group) {
  final members = <Object, List<CriteriaRequirement>>{};
  for (final requirement in group.requirements) {
    final key = requirement.groupId ?? requirement.groupName;
    if (key == null) continue;
    members.putIfAbsent(key, () => []).add(requirement);
  }
  return members;
}

RequirementGroupOption? _sharedOption(
  List<CriteriaRequirement> members,
  List<RequirementGroupOption> shared,
) {
  final id = members.first.groupId;
  for (final option in shared) {
    if (option.id == id) return option;
  }
  return null;
}

/// ชั่วโมงเป้าของหน่วยทั้งกลุ่ม — ใช้ในกรณีที่ไม่มีข้อมูลกลุ่มจาก requirement_groups
double _sharedTarget(List<CriteriaRequirement> members, List<RequirementGroupOption> shared) =>
    _sharedOption(members, shared)?.requiredHours ??
    members.map((r) => r.requiredHours).reduce(math.max);

/// ป้าย "รวม N ชม." ของหัวข้อ — รายการในกลุ่มแชร์เป้านับเป้าของกลุ่มครั้งเดียว
///
/// PLO 3 มี "แนวคิด…" 4 ชม. + สองด้านที่แชร์เป้า 16 ชม. → 20 ไม่ใช่ 36
double criteriaGroupTargetHours(CriteriaGroup group, List<RequirementGroupOption> shared) {
  var total = 0.0;
  for (final requirement in group.requirements) {
    if (requirement.groupId == null && requirement.groupName == null) {
      total += requirement.requiredHours;
    }
  }
  for (final members in _sharedMembers(group).values) {
    total += _sharedTarget(members, shared);
  }
  return total;
}

/// แถบกฎของกลุ่มแชร์เป้าที่อยู่ในหัวข้อนี้ (ว่าง = ไม่มีกฎพิเศษ)
List<String> sharedTargetRules(CriteriaGroup group, List<RequirementGroupOption> shared) => [
      for (final members in _sharedMembers(group).values)
        '${_sharedOption(members, shared)?.name ?? members.first.groupName ?? 'กลุ่มแชร์เป้า'}: '
            '${members.length} รายการเลือกรวมกันต้อง ≥ '
            '${formatHours(_sharedTarget(members, shared))} ชม. (ตรวจผลรวมอัตโนมัติ)',
    ];

/// บรรทัดย่อยใต้ชื่อรายการเกณฑ์
String? requirementSubtitle(CriteriaRequirement requirement) {
  final parts = [
    if (requirement.learningUnitName != null) 'หน่วยการเรียนรู้: ${requirement.learningUnitName}',
    if (requirement.groupId != null || requirement.groupName != null) 'ใช้เป้าร่วมของกลุ่ม',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// ปุ่มเพิ่มของในชุด — ชุดทางการกับชุดของผู้ดูแลใช้ชุดปุ่มเดียวกัน
/// ([onAddTalent] เป็น null = ชุดที่จัดกลุ่มด้วยหน่วยการเรียนรู้ ไม่มีปุ่ม Talent)
List<Widget> criteriaContentActions({
  VoidCallback? onAddTalent,
  required VoidCallback onAddGroup,
  required VoidCallback onAddRequirement,
}) =>
    [
      if (onAddTalent != null)
        OutlinedButton.icon(
          onPressed: onAddTalent,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('เพิ่ม Talent'),
        ),
      OutlinedButton.icon(
        onPressed: onAddGroup,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('เพิ่มกลุ่มแชร์เป้า'),
      ),
      OutlinedButton.icon(
        onPressed: onAddRequirement,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('เพิ่มรายการเกณฑ์'),
      ),
    ];

/// หัวของชุดเกณฑ์ทางการ (2567 / เกณฑ์เดิม) — แก้ของข้างในชุดได้เหมือนชุดของผู้ดูแล
///
/// ไม่มีปุ่มแก้ข้อมูลระดับชุด/ลบชุด เพราะ backend ตอบ 403 (ปีรุ่นของชุดทางการคือขั้นบันได
/// ที่นิสิตทั้งรุ่นแมปอยู่) · ป้าย "ชุดทางการ" บอกที่มา ไม่ได้สื่อว่าแก้ไม่ได้
CriteriaSetHeader officialCriteriaSectionHeader(
  CriteriaSet set, {
  required String badge,
  List<CriteriaSet> allSets = const [],
  int? academicYear,
  VoidCallback? onAddTalent,
  required VoidCallback onAddGroup,
  required VoidCallback onAddRequirement,
}) {
  final range = cohortRangeOf(set, allSets);
  final byTalent = set.groupedBy == 'talent';
  return CriteriaSetHeader(
    badge: badge,
    title: set.name,
    rangeLabel: range.pillLabel,
    audience: criteriaAudience(range, academicYear ?? currentAcademicYear()),
    totalHours: set.totalRequiredHours,
    metrics: criteriaSetMetrics(set),
    palette: StatusPalette.info,
    note: 'รหัสชุด ${set.code}',
    warning: set.hoursWarning,
    official: true,
    capabilities: 'แก้ได้: ${byTalent ? 'Talent · ' : ''}กลุ่มแชร์เป้า · รายการเกณฑ์ (ปุ่มด้านล่าง) · '
        'แก้/ลบรายการจากปุ่มในแต่ละแถว — มีผลกับการวัด${range.studentsLabel} ทันที · '
        'ชื่อชุดและปีรุ่นที่เริ่มใช้ของชุดทางการแก้ไม่ได้',
    actions: criteriaContentActions(
      onAddTalent: byTalent ? onAddTalent : null,
      onAddGroup: onAddGroup,
      onAddRequirement: onAddRequirement,
    ),
  );
}

/// หัวข้อส่วนชุดที่ผู้ดูแลสร้างเอง — แก้ข้อมูลชุด + ปุ่มเพิ่มของทุกชนิดอยู่ในกรอบนี้
CriteriaSetHeader customCriteriaSectionHeader(
  CriteriaSet set, {
  List<CriteriaSet> allSets = const [],
  int? academicYear,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  required VoidCallback onAddTalent,
  required VoidCallback onAddGroup,
  required VoidCallback onAddRequirement,
}) {
  final range = cohortRangeOf(set, allSets);
  return CriteriaSetHeader(
    badge: 'ชุดของผู้ดูแล',
    title: set.name,
    rangeLabel: range.pillLabel,
    audience: criteriaAudience(
      range,
      academicYear ?? currentAcademicYear(),
      programTypeLabel: set.programTypeLabel,
    ),
    totalHours: set.totalRequiredHours,
    metrics: criteriaSetMetrics(set),
    palette: StatusPalette.approved,
    note: 'รหัสชุด ${set.code}',
    warning: set.hoursWarning,
    onEdit: onEdit,
    onDelete: onDelete,
    capabilities: 'แก้ได้ทั้งชุด: ข้อมูลชุด (ปุ่มดินสอ) · เพิ่ม Talent · กลุ่มแชร์เป้า · '
        'รายการเกณฑ์ (ปุ่มด้านล่าง) · แก้/ลบรายการจากปุ่มในแต่ละแถว — มีผลกับ${range.studentsLabel}',
    actions: criteriaContentActions(
      onAddTalent: onAddTalent,
      onAddGroup: onAddGroup,
      onAddRequirement: onAddRequirement,
    ),
  );
}

/// การ์ดของชุดเกณฑ์หนึ่งชุด — หัวการ์ด + หัวข้อ Talent/หน่วยอยู่ในกรอบเดียวกัน
///
/// เดิมหัวข้อกับการ์ดรายการแยกกันลอย ๆ พอเลื่อนเร็ว ๆ แยกไม่ออกว่าการ์ดไหนเป็นของชุดไหน
/// รวมเป็นกรอบเดียวแล้วขอบเขตของชุดเห็นได้เอง
class CriteriaSetCard extends StatelessWidget {
  const CriteriaSetCard({super.key, required this.header, this.children = const []});

  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.frame),
        border: Border.all(color: AppColors.line),
        boxShadow: const [
          BoxShadow(color: kCardShadowColor, blurRadius: 22, offset: Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // Material โปร่งใสให้ InkWell ของหัวข้อมีระลอกบนพื้นขาวของการ์ด
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (children.isNotEmpty) ...[
              const Divider(height: 1, thickness: 1, color: AppColors.line),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// หัวของชุดเกณฑ์หนึ่งชุด — ป้าย "ชุดที่ N" → ชื่อ → ป้ายช่วงรหัส (เด่น) → ป้าย "ชุดทางการ" ชิดขวา
/// ตามด้วยปีเข้าศึกษา + metric 3 ใบ + สิ่งที่ทำได้ในชุดนี้
class CriteriaSetHeader extends StatelessWidget {
  const CriteriaSetHeader({
    super.key,
    required this.badge,
    required this.title,
    required this.audience,
    required this.totalHours,
    required this.palette,
    this.rangeLabel,
    this.metrics,
    this.note,
    this.warning,
    this.official = false,
    this.onEdit,
    this.onDelete,
    this.capabilities,
    this.actions = const [],
  });

  /// บอกตรง ๆ ว่าในชุดนี้เพิ่ม/แก้อะไรได้บ้าง และส่วนไหนแก้ไม่ได้
  final String? capabilities;

  /// ปุ่มเพิ่มของในชุดนี้ — วางไว้ในกรอบเดียวกับหัวข้อ เห็นชัดว่าเป็นของชุดไหน
  final List<Widget> actions;

  final String badge;
  final String title;

  /// ใช้กับนิสิตกลุ่มไหน — เป็นสิ่งที่ผู้ดูแลต้องรู้ก่อนอ่านตัวเกณฑ์
  final String audience;

  /// ป้ายช่วงรหัสที่คำนวณจากชุดถัดไป ("ใช้กับรหัส 67–69") — ตัวหลักที่บอกว่าชุดนี้ของใคร
  final String? rangeLabel;
  final double totalHours;

  /// การ์ดตัวเลขย่อ — null = มีใบเดียวคือชั่วโมงรวม
  final List<CriteriaMetric>? metrics;
  final StatusPalette palette;
  final String? note;

  /// ข้อความเตือนจาก backend (`hours_warning`) — ชั่วโมงของรายการยังไม่ตรงกับเป้าของชุด
  final String? warning;

  /// ชุดเกณฑ์ทางการ (seed ไว้) — แสดงป้าย "ชุดทางการ" บอกที่มา ไม่ได้แปลว่าแก้ไม่ได้
  /// (ของข้างในชุดแก้ได้ทุกชุด · ปุ่มแก้/ลบระดับชุดควบคุมด้วย [onEdit]/[onDelete])
  final bool official;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shownMetrics =
        metrics ?? [CriteriaMetric('${formatHours(totalHours)} ชม.', 'ชั่วโมงรวม')];
    const officialChip = _OfficialChip();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md + 2, AppSpacing.lg, AppSpacing.md + 2),
      decoration: BoxDecoration(
        // ไล่สีอ่อนจากโทนของชุดลงมาเป็นเทาอมฟ้า — แยกหัวออกจากเนื้อหาโดยไม่ต้องใช้กรอบหนา
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(palette.background, AppColors.surface, 0.35)!,
            const Color(0xFFF7F9FC),
          ],
        ),
        border: Border(left: BorderSide(color: palette.accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            // จอกว้าง: ป้ายชุดทางการชิดขวา · จอแคบ: ต่อท้ายในแถวเดียวกันแล้วตกบรรทัดเอง
            final wide = constraints.maxWidth >= 640;
            final top = Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: palette.foreground,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.surface, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                if (rangeLabel != null)
                  Container(
                    key: const ValueKey('cohort-range-pill'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      rangeLabel!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.surface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (official && !wide) officialChip,
                if (onEdit != null)
                  AppIconButton(
                      icon: Icons.edit, size: 28, tooltip: 'แก้ไขชุดเกณฑ์', onPressed: onEdit),
                if (onDelete != null)
                  AppIconButton(
                    icon: Icons.delete,
                    size: 28,
                    danger: true,
                    tooltip: 'ลบชุดเกณฑ์',
                    onPressed: onDelete,
                  ),
              ],
            );
            if (!official || !wide) return top;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: top),
                const SizedBox(width: AppSpacing.sm),
                const Padding(padding: EdgeInsets.only(top: 2), child: officialChip),
              ],
            );
          }),
          const SizedBox(height: AppSpacing.xs + 2),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: 2,
            children: [
              Text(audience, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.sub)),
              if (note != null) ...[
                Text('·', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                Text(note!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.sub)),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            key: const ValueKey('criteria-metrics'),
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [for (final metric in shownMetrics) _MetricTile(metric)],
          ),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      warning!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (capabilities != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      capabilities!,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.sub),
                    ),
                  ),
                ],
              ),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: actions,
              ),
            ),
        ],
      ),
    );
  }
}

/// ป้าย "ชุดทางการ" — บอกว่าเป็นเกณฑ์ที่ระบบตั้งไว้ ไม่มีรูปกุญแจเพราะแก้ของข้างในได้แล้ว
///
/// ข้อความตกบรรทัดได้ (StatusChip ใช้ Row ที่หดไม่ได้ ป้ายจะล้นขอบการ์ดบนจอแคบ)
class _OfficialChip extends StatelessWidget {
  const _OfficialChip();

  @override
  Widget build(BuildContext context) {
    const palette = StatusPalette.neutral;
    return Container(
      key: const ValueKey('official-set-chip'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 14, color: palette.foreground),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              'ชุดทางการ',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.metric);

  final CriteriaMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 88),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            metric.value,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: AppColors.blueDark, fontWeight: FontWeight.w700),
          ),
          Text(metric.label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// หัวข้อ Talent/หน่วยที่พับได้: ▸/▾ + ชื่อ + ป้าย PLO + จำนวนรายการ + ป้าย "รวม N ชม."
///
/// [rules] = แถบกฎกลุ่มแชร์เป้า แสดงใต้หัวข้อตลอดแม้พับอยู่ เพราะเป็นกติกาที่อ่านข้ามไม่ได้
class CriteriaGroupTile extends StatefulWidget {
  const CriteriaGroupTile({
    super.key,
    required this.name,
    required this.countLabel,
    this.chip,
    this.hours,
    this.rules = const [],
    this.trailing = const [],
    this.children = const [],
    this.initiallyExpanded = false,
  });

  final String name;
  final String? chip;
  final String countLabel;
  final double? hours;
  final List<String> rules;
  final List<Widget> trailing;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<CriteriaGroupTile> createState() => _CriteriaGroupTileState();
}

class _CriteriaGroupTileState extends State<CriteriaGroupTile> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      Text(widget.countLabel, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
      if (widget.hours != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.blueBg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            'รวม ${formatHours(widget.hours!)} ชม.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.blueDark, fontWeight: FontWeight.w700),
          ),
        ),
    ];
    final name = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        Text(widget.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        if (widget.chip != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.blue,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.chip!,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.surface, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
            child: LayoutBuilder(builder: (context, constraints) {
              final chevron = Icon(
                _expanded ? Icons.expand_more : Icons.chevron_right,
                size: 20,
                color: AppColors.muted,
              );
              // จอแคบ: จำนวน/ชั่วโมง/ปุ่มลงไปบรรทัดที่สอง ชื่อหัวข้อจะได้ไม่ถูกบีบเหลือคำเดียว
              if (constraints.maxWidth < 520) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    chevron,
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          name,
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [...meta, ...widget.trailing],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  chevron,
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: name),
                  const SizedBox(width: AppSpacing.sm),
                  for (final item in [...meta, ...widget.trailing]) ...[
                    const SizedBox(width: AppSpacing.sm),
                    item,
                  ],
                ],
              );
            }),
          ),
        ),
        for (final rule in widget.rules)
          Container(
            key: const ValueKey('shared-target-rule'),
            margin: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: StatusPalette.approved.background,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.balance, size: 16, color: StatusPalette.approved.foreground),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    rule,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: StatusPalette.approved.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_expanded && widget.children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

/// แถวรายการเกณฑ์ (หรือหมวดย่อยของเกณฑ์เดิม): ชื่อ + ป้ายบังคับ/เลือก + บรรทัดย่อย · ชั่วโมงชิดขวา
///
/// แถวคู่มีพื้นอ่อนให้ไล่สายตาข้ามแถวได้ · ป้ายใช้ StatusChip สีเดียวกับฟอร์มกิจกรรม
class CriteriaRequirementRow extends StatelessWidget {
  const CriteriaRequirementRow({
    super.key,
    required this.index,
    required this.name,
    required this.hours,
    this.subtitle,
    this.mandatory,
    this.trailing = const [],
  });

  final int index;
  final String name;
  final double hours;
  final String? subtitle;

  /// null = ไม่มีแนวคิดบังคับ/เลือก (หมวดย่อยของเกณฑ์เดิม)
  final bool? mandatory;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm + 2, AppSpacing.sm, AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: index.isEven ? AppColors.fieldFill : null,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w500),
                    ),
                    if (mandatory != null)
                      StatusChip(
                        label: mandatory! ? 'บังคับ' : 'เลือก',
                        palette: mandatory! ? StatusPalette.pending : StatusPalette.neutral,
                        dense: true,
                      ),
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            '${formatHours(hours)} ชม.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.blueDark, fontWeight: FontWeight.w700),
          ),
          for (final item in trailing) ...[
            const SizedBox(width: AppSpacing.xs),
            item,
          ],
        ],
      ),
    );
  }
}

/// ตรวจช่อง "ชั่วโมงที่ต้องการ" ให้ตรงกับกฎของ backend (ต้องเป็นตัวเลข > 0)
///
/// กันตั้งแต่ในฟอร์มเพื่อไม่ให้ผู้ใช้เจอ 422 ดิบ ๆ จาก Pydantic
String? requiredHoursValidator(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return 'กรอกจำนวนชั่วโมง';
  final hours = double.tryParse(text);
  if (hours == null) return 'กรอกเป็นตัวเลข';
  if (hours <= 0) return 'ชั่วโมงต้องมากกว่า 0';
  return null;
}

class HourCategoryFormDialog extends StatefulWidget {
  final HourCategory? existing;
  const HourCategoryFormDialog({super.key, this.existing});

  @override
  State<HourCategoryFormDialog> createState() => _HourCategoryFormDialogState();
}

class _HourCategoryFormDialogState extends State<HourCategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hoursController;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _hoursController = TextEditingController(
      text: widget.existing == null ? '' : formatHours(widget.existing!.requiredHours),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = {
        'name': _nameController.text.trim(),
        'required_hours': double.parse(_hoursController.text.trim()),
      };
      if (_isEdit) {
        await ApiService.update('/hour-categories/${widget.existing!.id}', body, (json) => json);
      } else {
        await ApiService.create('/hour-categories', body, (json) => json);
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
      title: _isEdit ? 'แก้ไขหมวดชั่วโมง' : 'เพิ่มหมวดชั่วโมง',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'ชื่อหมวด'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _hoursController,
          decoration: const InputDecoration(
            labelText: 'ชั่วโมงที่ต้องการ',
            helperText: 'เกณฑ์ชั่วโมงรวมของหมวดนี้ที่นิสิตต้องสะสมให้ครบ',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: requiredHoursValidator,
        ),
      ],
    );
  }
}

class HourSubcategoryFormDialog extends StatefulWidget {
  /// หมวดใหญ่ทั้งหมด — ใช้เป็นตัวเลือกของ dropdown "อยู่ใต้หมวด"
  final List<HourCategory> categories;

  /// หมวดใหญ่ที่ตั้งไว้ให้ตอนเปิด (หมวดที่ผู้ใช้กดปุ่ม + มา)
  final int categoryId;
  final HourSubcategory? existing;

  const HourSubcategoryFormDialog({
    super.key,
    required this.categories,
    required this.categoryId,
    this.existing,
  });

  @override
  State<HourSubcategoryFormDialog> createState() => _HourSubcategoryFormDialogState();
}

class _HourSubcategoryFormDialogState extends State<HourSubcategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hoursController;
  late int _categoryId;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _hoursController = TextEditingController(
      text: widget.existing == null ? '' : formatHours(widget.existing!.requiredHours),
    );
    _categoryId = widget.categoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = {
        'category_id': _categoryId,
        'name': _nameController.text.trim(),
        'required_hours': double.parse(_hoursController.text.trim()),
      };
      if (_isEdit) {
        await ApiService.update(
          '/hour-subcategories/${widget.existing!.id}',
          body,
          (json) => json,
        );
      } else {
        await ApiService.create('/hour-subcategories', body, (json) => json);
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
      title: _isEdit ? 'แก้ไขหมวดย่อย' : 'เพิ่มหมวดย่อย',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        DropdownButtonFormField<int>(
          initialValue: _categoryId,
          isExpanded: true, // ชื่อหมวดยาว ต้องไม่ล้นกรอบ (แบบเดียวกับ E3)
          decoration: const InputDecoration(labelText: 'อยู่ใต้หมวด'),
          items: widget.categories
              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
              .toList(),
          onChanged: (value) => setState(() => _categoryId = value ?? _categoryId),
        ),
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'ชื่อหมวดย่อย'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _hoursController,
          decoration: const InputDecoration(
            labelText: 'ชั่วโมงที่ต้องการ',
            helperText: 'เกณฑ์ชั่วโมงของหมวดย่อยนี้',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: requiredHoursValidator,
        ),
      ],
    );
  }
}
