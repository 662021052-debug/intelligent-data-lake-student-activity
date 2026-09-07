import 'package:flutter/material.dart';

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
import 'app_shell.dart';

/// หน้า "จัดการหมวดชั่วโมงกิจกรรม" (admin เท่านั้น)
///
/// หมวดชั่วโมงคือเกณฑ์ที่ทั้งระบบอ้างอิง — ฟอร์มกิจกรรมเลือกหมวดย่อยจากที่นี่
/// สรุปชั่วโมงของนิสิตและกราฟรายหมวดบนแดชบอร์ดก็นับตามที่นี่ เดิมแก้ได้ทางเดียว
/// คือแก้ `seed.py` แล้ว seed ใหม่
///
/// ต่างจากหน้า list อื่นตรงที่ **ไม่มีการแบ่งหน้า**: `GET /hour-categories` คืน
/// ต้นไม้ทั้งก้อนในครั้งเดียว (ของจริงมี 5 หมวด ~13 หมวดย่อย) และการแบ่งหน้า
/// จะตัดหมวดย่อยขาดจากหมวดแม่ ช่องค้นหาจึงกรองในเครื่องแทน
class HourCategoriesScreen extends StatefulWidget {
  const HourCategoriesScreen({super.key});

  @override
  State<HourCategoriesScreen> createState() => _HourCategoriesScreenState();
}

class _HourCategoriesScreenState extends State<HourCategoriesScreen> {
  List<HourCategory> _categories = [];
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
      final categories = await ApiService.fetchList('/hour-categories', HourCategory.fromJson);
      if (!mounted) return;
      setState(() => _categories = categories);
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
    final subcategoryCount =
        _categories.fold<int>(0, (sum, c) => sum + c.subcategories.length);

    return AdminPage(
      activeId: 'hour_categories',
      title: 'หมวดชั่วโมงกิจกรรม',
      subtitle: '${_categories.length} หมวดใหญ่ · $subcategoryCount หมวดย่อย',
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
          ? const LoadingState(message: 'กำลังโหลดหมวดชั่วโมง...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : visible.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      itemCount: visible.length,
                      itemBuilder: (context, index) =>
                          _categoryTile(context, visible[index]),
                    ),
    );
  }

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

  Widget _emptyState() {
    if (_search.isNotEmpty) return EmptyState.noResults();
    return const EmptyState(
      icon: Icons.category_outlined,
      title: 'ยังไม่มีหมวดชั่วโมง',
      message: 'กดปุ่ม "เพิ่มหมวดใหญ่" ด้านบนเพื่อสร้างหมวดแรก',
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
