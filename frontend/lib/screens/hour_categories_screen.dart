import 'package:flutter/material.dart';

import '../models/criteria_set.dart';
import '../models/hour_category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../utils/format.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/search_field.dart';
import '../widgets/status_chip.dart';
import 'app_shell.dart';

/// หน้า "หมวดชั่วโมงกิจกรรม" (admin เท่านั้น) — แสดงเกณฑ์ **ทั้งสองชุดพร้อมกัน**
///
/// นิสิตที่เรียนอยู่ตอนนี้ใช้เกณฑ์คนละชุดกันตามรหัส ผู้ดูแลจึงต้องเห็นทั้งคู่ในหน้าเดียว
/// ไม่งั้นจะตอบคำถามนิสิตปี 4 ด้วยโครงสร้างของปี 1 โดยไม่รู้ตัว:
///
/// * **โครงสร้าง 2567** (รหัส 67 ขึ้นไป) — Talent/PLO → รายการเกณฑ์ ดึงจาก
///   `GET /criteria-sets` เป็น **อ่านอย่างเดียว** เพราะนิยามชุดนี้ seed เข้าฐาน
///   (`seed_criteria.py`) และยังไม่มี API สำหรับแก้ ปุ่มเพิ่ม/แก้/ลบจึงไม่โผล่ที่ส่วนนี้
///   แทนที่จะโผล่มาแล้วกดไม่ได้จริง
/// * **เกณฑ์เดิม** (รหัส 66 ลงไป) — หน่วยการเรียนรู้ → หมวดย่อย ดึงจาก
///   `GET /hour-categories` ซึ่งแก้ได้ ปุ่มจัดการทั้งหมดอยู่ในส่วนนี้ส่วนเดียว
///
/// ต่างจากหน้า list อื่นตรงที่ **ไม่มีการแบ่งหน้า**: ทั้งสอง endpoint คืนต้นไม้ทั้งก้อน
/// ในครั้งเดียว และการแบ่งหน้าจะตัดหมวดย่อยขาดจากหมวดแม่ ช่องค้นหาจึงกรองในเครื่องแทน
class HourCategoriesScreen extends StatefulWidget {
  const HourCategoriesScreen({super.key});

  @override
  State<HourCategoriesScreen> createState() => _HourCategoriesScreenState();
}

class _HourCategoriesScreenState extends State<HourCategoriesScreen> {
  List<HourCategory> _categories = [];
  List<CriteriaSet> _criteriaSets = [];
  bool _loading = false;
  String? _error;
  String _search = '';

  /// ชุดเกณฑ์ที่จัดกลุ่มด้วย Talent/PLO = โครงสร้าง 2567 (null ถ้ายังโหลดไม่สำเร็จ)
  CriteriaSet? get _talentSet {
    for (final set in _criteriaSets) {
      if (set.groupedBy == 'talent') return set;
    }
    return null;
  }

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
      // ยิงพร้อมกัน — สองส่วนของหน้าไม่ได้ขึ้นต่อกัน ไม่ควรรอกันเป็นทอด ๆ
      final results = await Future.wait([
        ApiService.fetchList('/hour-categories', HourCategory.fromJson),
        ApiService.fetchList('/criteria-sets', CriteriaSet.fromJson),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<HourCategory>;
        _criteriaSets = results[1] as List<CriteriaSet>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// หมวดที่ตรงคำค้น — ชื่อหมวดใหญ่ตรง หรือมีหมวดย่อยชื่อตรงอยู่ข้างใน
  List<HourCategory> get _visible {
    if (_search.isEmpty) return _categories;
    final needle = _search.toLowerCase();
    return _categories
        .where((c) =>
            c.name.toLowerCase().contains(needle) ||
            c.subcategories.any((s) => s.name.toLowerCase().contains(needle)))
        .toList();
  }

  Future<void> _openCategoryForm({HourCategory? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => HourCategoryFormDialog(existing: existing),
    );
    if (saved == true) _load();
  }

  Future<void> _openSubcategoryForm({
    required HourCategory category,
    HourSubcategory? existing,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => HourSubcategoryFormDialog(
        categories: _categories,
        categoryId: category.id,
        existing: existing,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteCategory(HourCategory category) async {
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการลบหมวด',
      message: 'ต้องการลบหมวด "${category.name}" ใช่หรือไม่?',
      detail: 'ลบได้เฉพาะหมวดที่ไม่มีหมวดย่อยเหลืออยู่ และลบแล้วกู้คืนไม่ได้',
      confirmLabel: 'ลบ',
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (confirmed != true) return;
    await _runDelete('/hour-categories/${category.id}');
  }

  Future<void> _deleteSubcategory(HourSubcategory subcategory) async {
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการลบหมวดย่อย',
      message: 'ต้องการลบหมวดย่อย "${subcategory.name}" ใช่หรือไม่?',
      detail: 'ลบได้เฉพาะหมวดย่อยที่ยังไม่มีกิจกรรมใช้อยู่ และลบแล้วกู้คืนไม่ได้',
      confirmLabel: 'ลบ',
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (confirmed != true) return;
    await _runDelete('/hour-subcategories/${subcategory.id}');
  }

  /// ลบแล้วโหลดใหม่ — ข้อความ 400 ของ backend ("มีกิจกรรมใช้อยู่ n รายการ")
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

    final visible = _visible;
    final talentSet = _talentSet;

    return AdminPage(
      activeId: 'hour_categories',
      title: 'หมวดชั่วโมงกิจกรรม',
      subtitle: 'โครงสร้างเกณฑ์ 2 ชุดที่ใช้อยู่พร้อมกัน — คนละชุดตามรหัสนิสิต',
      actions: [
        FilledButton.icon(
          onPressed: () => _openCategoryForm(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('เพิ่มหมวดใหญ่'),
        ),
      ],
      filters: [
        DebouncedSearchField(
          label: 'ค้นหาหมวด/หมวดย่อย',
          onSearch: (value) => setState(() => _search = value),
        ),
        AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: _load),
      ],
      busy: _loading && _categories.isNotEmpty,
      child: _loading && _categories.isEmpty
          ? const LoadingState(message: 'กำลังโหลดโครงสร้างเกณฑ์...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  children: [
                    _talentSection(context, talentSet),
                    const SizedBox(height: AppSpacing.xl),
                    _legacySection(context, visible),
                  ],
                ),
    );
  }

  // ---------------- ส่วนที่ 1: โครงสร้าง 2567 (อ่านอย่างเดียว) ----------------

  Widget _talentSection(BuildContext context, CriteriaSet? set) {
    final groups = set == null ? <CriteriaGroup>[] : filterCriteriaGroups(set.groups, _search);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CriteriaSetHeader(
          badge: 'ชุดที่ 1',
          title: 'โครงสร้าง 2567',
          audience: 'สำหรับนิสิตรหัส 67 ขึ้นไป (ปัจจุบัน ปี 1-3)',
          totalHours: set?.totalRequiredHours ?? 0,
          palette: StatusPalette.info,
          note: 'นิยามชุดนี้กำหนดไว้ในระบบ แก้ผ่านหน้านี้ไม่ได้',
        ),
        if (set == null)
          _sectionMessage('ยังโหลดโครงสร้าง 2567 ไม่ได้ — กดโหลดใหม่อีกครั้ง')
        else if (groups.isEmpty)
          _sectionMessage(
            _search.isEmpty
                ? 'ยังไม่มีรายการเกณฑ์ในชุดนี้'
                : 'ไม่พบรายการที่ตรงกับคำค้นในชุดนี้',
          )
        else
          for (final group in groups) _talentCard(context, group),
      ],
    );
  }

  Widget _talentCard(BuildContext context, CriteriaGroup group) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        key: PageStorageKey('criteria-group-${group.key}-$_search'),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: EdgeInsets.zero,
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text(group.name, style: theme.textTheme.titleSmall),
            if (group.subtitle != null)
              StatusChip(
                label: group.subtitle!,
                palette: StatusPalette.info,
                dense: true,
              ),
          ],
        ),
        subtitle: Text(
          'รายการเกณฑ์ ${group.requirements.length} รายการ',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        children: [
          for (final requirement in group.requirements)
            _requirementRow(context, requirement),
        ],
      ),
    );
  }

  Widget _requirementRow(BuildContext context, CriteriaRequirement requirement) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap ไม่ใช่ Row — ชื่อรายการเกณฑ์ยาวมาก บนจอแคบต้องตกบรรทัดได้
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                requirement.name,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.sub),
              ),
              Text(
                '${formatHours(requirement.requiredHours)} ชม.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              StatusChip(
                label: requirement.isMandatory ? 'บังคับ' : 'เลือก',
                palette: requirement.isMandatory
                    ? StatusPalette.pending
                    : StatusPalette.neutral,
                dense: true,
              ),
            ],
          ),
          if (requirement.learningUnitName != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'นับเข้าหน่วยการเรียนรู้: ${requirement.learningUnitName}',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ),
          if (requirement.groupName != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'กฎกลุ่ม: ${requirement.groupName} — '
                'ครบเมื่อยอดรวมของกลุ่มถึง ${formatHours(requirement.requiredHours)} ชม.',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.blueDark),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------- ส่วนที่ 2: เกณฑ์เดิม (แก้ไขได้) ----------------

  Widget _legacySection(BuildContext context, List<HourCategory> visible) {
    final totalHours = _categories.fold<double>(0, (sum, c) => sum + c.requiredHours);
    final subcategoryCount =
        _categories.fold<int>(0, (sum, c) => sum + c.subcategories.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CriteriaSetHeader(
          badge: 'ชุดที่ 2',
          title: 'เกณฑ์เดิม',
          audience: 'สำหรับนิสิตรหัส 66 ลงไป (ปัจจุบัน ปี 4)',
          totalHours: totalHours,
          palette: StatusPalette.neutral,
          note: '${_categories.length} หน่วยการเรียนรู้ · $subcategoryCount หมวดย่อย '
              '· แก้ไขได้จากปุ่มในส่วนนี้',
        ),
        if (visible.isEmpty)
          _sectionMessage(
            _search.isEmpty
                ? 'ยังไม่มีหน่วยการเรียนรู้ — กดปุ่ม "เพิ่มหมวดใหญ่" ด้านบน'
                : 'ไม่พบหมวดที่ตรงกับคำค้นในชุดนี้',
          )
        else
          for (final category in visible) _categoryTile(context, category),
      ],
    );
  }

  Widget _sectionMessage(String message) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
      );

  Widget _categoryTile(BuildContext context, HourCategory category) {
    final theme = Theme.of(context);
    final totalSubHours =
        category.subcategories.fold<double>(0, (sum, s) => sum + s.requiredHours);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // เปิดค้างไว้ตอนกำลังค้นหา ผู้ใช้จะได้เห็นหมวดย่อยที่ตรงคำค้นทันที
        initiallyExpanded: _search.isNotEmpty,
        key: PageStorageKey('hour-category-${category.id}-$_search'),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: EdgeInsets.zero,
        title: Text(category.name, style: theme.textTheme.titleSmall),
        subtitle: Text(
          'ต้องการ ${formatHours(category.requiredHours)} ชม. • '
          'หมวดย่อย ${category.subcategories.length} รายการ '
          '(รวม ${formatHours(totalSubHours)} ชม.)',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        trailing: Wrap(
          spacing: AppSpacing.xs,
          children: [
            AppIconButton(
              icon: Icons.add,
              tooltip: 'เพิ่มหมวดย่อย',
              onPressed: () => _openSubcategoryForm(category: category),
            ),
            AppIconButton(
              icon: Icons.edit,
              tooltip: 'แก้ไขหมวด',
              onPressed: () => _openCategoryForm(existing: category),
            ),
            AppIconButton(
              icon: Icons.delete,
              danger: true,
              tooltip: 'ลบหมวด',
              onPressed: () => _deleteCategory(category),
            ),
          ],
        ),
        children: category.subcategories.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.fromLTRB(42, 0, AppSpacing.lg, AppSpacing.md),
                  child: Text(
                    'ยังไม่มีหมวดย่อย — กดปุ่ม + เพื่อเพิ่ม',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ),
              ]
            : [
                for (final sub in category.subcategories)
                  Container(
                    padding: const EdgeInsets.fromLTRB(42, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.line)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sub.name,
                            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.sub),
                          ),
                        ),
                        Text(
                          '${formatHours(sub.requiredHours)} ชม.',
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.sub),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        AppIconButton(
                          icon: Icons.edit,
                          size: 28,
                          tooltip: 'แก้ไขหมวดย่อย',
                          onPressed: () =>
                              _openSubcategoryForm(category: category, existing: sub),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        AppIconButton(
                          icon: Icons.delete,
                          size: 28,
                          danger: true,
                          tooltip: 'ลบหมวดย่อย',
                          onPressed: () => _deleteSubcategory(sub),
                        ),
                      ],
                    ),
                  ),
              ],
      ),
    );
  }

}

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

/// หัวข้อของชุดเกณฑ์หนึ่งชุด — ป้ายสี + ชื่อชุด + บอกว่าใช้กับนิสิตรุ่นไหน + ชั่วโมงรวม
///
/// ทั้งสองส่วนในหน้านี้หน้าตาคล้ายกันมาก (การ์ดพับได้เหมือนกัน) ถ้าไม่มีแถบสีคั่น
/// ผู้ดูแลจะเลื่อนผ่านแล้วอ่านต่อเป็นชุดเดียวกัน — ป้ายกับสีจึงเป็นตัวบอกเขตแดน
class CriteriaSetHeader extends StatelessWidget {
  const CriteriaSetHeader({
    super.key,
    required this.badge,
    required this.title,
    required this.audience,
    required this.totalHours,
    required this.palette,
    this.note,
  });

  final String badge;
  final String title;

  /// ใช้กับนิสิตกลุ่มไหน — เป็นสิ่งที่ผู้ดูแลต้องรู้ก่อนอ่านตัวเกณฑ์
  final String audience;
  final double totalHours;
  final StatusPalette palette;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        // แถบสีด้านซ้ายทำให้เห็นขอบเขตของส่วนได้แม้เลื่อนเร็ว ๆ
        border: Border(left: BorderSide(color: palette.accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              StatusChip(label: badge, palette: palette, dense: true),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.foreground,
                ),
              ),
              Text(
                '· รวม ${formatHours(totalHours)} ชม.',
                style: theme.textTheme.titleSmall?.copyWith(color: palette.foreground),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            audience,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.ink),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                note!,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.sub),
              ),
            ),
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
