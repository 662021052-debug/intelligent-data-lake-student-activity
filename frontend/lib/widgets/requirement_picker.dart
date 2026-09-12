import 'package:flutter/material.dart';

import '../models/criteria_set.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// ช่องเลือก "รายการเกณฑ์ที่กิจกรรมนี้นับชั่วโมงให้" ของฟอร์มกิจกรรม
///
/// เลือกได้หลายรายการและข้ามชุดเกณฑ์ได้ (กิจกรรมงานเดียวมักนับให้ทั้งรุ่นเก่าและรุ่นใหม่)
/// จัดกลุ่มตามที่ backend ส่งมา: ชุด 2567 = Talent/PLO → รายการ · ชุดเดิม = หน่วยการเรียนรู้
/// → รายการ ผู้ใช้จึงเห็นโครงเดียวกับเอกสารเกณฑ์ของแต่ละรุ่น
///
/// กล่องรายการมีความสูงจำกัดและเลื่อนในตัวเอง — ชุดเกณฑ์ทั้งระบบมีหลายสิบรายการ
/// ถ้าปล่อยยาวเต็มจะดัน dialog จนปุ่มบันทึกหลุดจอ
class RequirementPicker extends StatefulWidget {
  const RequirementPicker({
    super.key,
    required this.criteriaSets,
    required this.selected,
    required this.onChanged,
    this.maxListHeight = 260,
  });

  final List<CriteriaSet> criteriaSets;

  /// id ของรายการเกณฑ์ที่เลือกไว้
  final Set<int> selected;

  final ValueChanged<Set<int>> onChanged;

  final double maxListHeight;

  @override
  State<RequirementPicker> createState() => _RequirementPickerState();
}

class _RequirementPickerState extends State<RequirementPicker> {
  /// กลุ่มที่กางอยู่ — เริ่มต้นกางเฉพาะกลุ่มที่มีรายการถูกเลือกไว้แล้ว (โหมดแก้ไข)
  /// ที่เหลือพับไว้ให้เห็นภาพรวมทั้งชุดก่อน
  late final Set<String> _expanded = {
    for (final set in widget.criteriaSets)
      for (final group in set.groups)
        if (group.requirements.any((r) => widget.selected.contains(r.id))) group.key,
  };

  void _toggle(int requirementId, bool checked) {
    final next = {...widget.selected};
    if (checked) {
      next.add(requirementId);
    } else {
      next.remove(requirementId);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.selected.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'รายการเกณฑ์ที่กิจกรรมนี้นับชั่วโมงให้',
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (count > 0)
              TextButton(
                onPressed: () => widget.onChanged(<int>{}),
                child: const Text('ล้างทั้งหมด'),
              ),
          ],
        ),
        Text(
          count == 0
              ? 'ยังไม่ได้เลือก — เลือกได้หลายรายการ ชั่วโมงจะเข้าให้ทุกรายการที่เลือก'
              : 'เลือกแล้ว $count รายการ',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (widget.criteriaSets.isEmpty)
          _EmptyNote(theme: theme)
        else
          Container(
            constraints: BoxConstraints(maxHeight: widget.maxListHeight),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(AppRadius.field),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final set in widget.criteriaSets) ...[
                  _SetHeader(criteriaSet: set),
                  for (final group in set.groups)
                    _GroupTile(
                      group: group,
                      expanded: _expanded.contains(group.key),
                      selected: widget.selected,
                      onExpand: (open) => setState(() {
                        if (open) {
                          _expanded.add(group.key);
                        } else {
                          _expanded.remove(group.key);
                        }
                      }),
                      onToggle: _toggle,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppRadius.field),
          color: AppColors.fieldFill,
        ),
        child: Text(
          'ยังไม่มีชุดเกณฑ์ในระบบ — ใช้หมวดชั่วโมงโครงเดิมด้านล่างไปก่อน',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
      );
}

/// แถบชื่อชุดเกณฑ์ — คั่นให้เห็นว่ารายการข้างล่างเป็นของรุ่นไหน
class _SetHeader extends StatelessWidget {
  const _SetHeader({required this.criteriaSet});

  final CriteriaSet criteriaSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.blueBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            criteriaSet.name,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.blueDark,
            ),
          ),
          Text(
            'จัดกลุ่มตาม${criteriaSet.groupNoun} · '
            'รวม ${formatHours(criteriaSet.totalRequiredHours)} ชม.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.sub),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.expanded,
    required this.selected,
    required this.onExpand,
    required this.onToggle,
  });

  final CriteriaGroup group;
  final bool expanded;
  final Set<int> selected;
  final ValueChanged<bool> onExpand;
  final void Function(int requirementId, bool checked) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = group.requirements.where((r) => selected.contains(r.id)).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => onExpand(!expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: AppColors.sub),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    group.subtitle == null ? group.name : '${group.name} (${group.subtitle})',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
                  ),
                ),
                if (chosen > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Text(
                      'เลือก $chosen',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.blueDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final requirement in group.requirements)
            _RequirementTile(
              requirement: requirement,
              checked: selected.contains(requirement.id),
              onChanged: (v) => onToggle(requirement.id, v),
            ),
        const Divider(height: 1, color: AppColors.line),
      ],
    );
  }
}

class _RequirementTile extends StatelessWidget {
  const _RequirementTile({
    required this.requirement,
    required this.checked,
    required this.onChanged,
  });

  final CriteriaRequirement requirement;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = [
      if (requirement.requiredHours > 0) 'เป้า ${formatHours(requirement.requiredHours)} ชม.',
      if (requirement.isMandatory) 'บังคับ',
      if (requirement.groupName != null) 'รวมกับ${requirement.groupName}',
      if (requirement.learningUnitName != null) requirement.learningUnitName!,
    ].join(' · ');

    return CheckboxListTile(
      value: checked,
      onChanged: (v) => onChanged(v ?? false),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.md),
      title: Text(
        requirement.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: notes.isEmpty
          ? null
          : Text(
              notes,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.sub),
            ),
    );
  }
}
