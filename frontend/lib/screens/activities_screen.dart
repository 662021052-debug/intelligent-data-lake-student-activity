import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/hour_category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_data_table.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/search_field.dart';
import '../widgets/status_chip.dart';
import '../widgets/subcategory_dropdown.dart';
import 'activity_participants_screen.dart';

const _activityTypes = ['จิตอาสา', 'กีฬา', 'วิชาการ', 'ศิลปวัฒนธรรม', 'อบรม/สัมมนา'];

String _subcategoryLabel(List<HourCategory> categories, int? subcategoryId) {
  if (subcategoryId == null) return '-';
  for (final category in categories) {
    for (final sub in category.subcategories) {
      if (sub.id == subcategoryId) return '${category.name} › ${sub.name}';
    }
  }
  return '-';
}

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}

String _trimHours(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toString();

class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key});

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  static const int _limit = 10;

  List<Activity> _activities = [];
  List<HourCategory> _categories = [];
  int _total = 0;
  int _skip = 0;
  bool _loading = false;
  String? _error;
  String _search = '';
  String? _typeFilter;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService.fetchList('/hour-categories', HourCategory.fromJson);
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
      // non-fatal: table falls back to "-" and the form dialog shows an empty picker
    }
  }

  void _onSearch(String value) {
    _search = value;
    _skip = 0;
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, String>{'skip': '$_skip', 'limit': '$_limit'};
      if (_search.isNotEmpty) query['search'] = _search;
      if (_typeFilter != null) query['activity_type'] = _typeFilter!;
      final page = await ApiService.fetchPage('/activities', Activity.fromJson, query: query);
      // ผลลัพธ์เก่าที่มาช้ากว่าคำค้นหาล่าสุด ต้องไม่ทับของใหม่
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _activities = page.items;
        _total = page.total;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Activity? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ActivityFormDialog(existing: existing, categories: _categories),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Activity a) async {
    final confirmed = await confirmDelete(context, a.name);
    if (confirmed != true) return;
    try {
      await ApiService.delete('/activities/${a.id}');
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  Future<void> _approve(Activity a) async {
    try {
      await ApiService.patch('/activities/${a.id}/approve', Activity.fromJson);
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  void _openParticipants(Activity a) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ActivityParticipantsScreen(activity: a)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = authService.canWrite;
    final isStudent = authService.role == 'student';
    return Scaffold(
      appBar: AppBar(title: Text(isStudent ? 'กิจกรรม' : 'จัดการกิจกรรม')),
      floatingActionButton: canWrite
          ? FloatingActionButton(onPressed: () => _openForm(), child: const Icon(Icons.add))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DebouncedSearchField(
                  label: 'ค้นหาชื่อกิจกรรม',
                  onSearch: _onSearch,
                ),
                DropdownButton<String?>(
                  value: _typeFilter,
                  hint: const Text('ประเภททั้งหมด'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('ประเภททั้งหมด')),
                    ..._activityTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))),
                  ],
                  onChanged: (v) {
                    setState(() => _typeFilter = v);
                    _skip = 0;
                    _load();
                  },
                ),
                IconButton(
                  onPressed: _load,
                  tooltip: 'โหลดใหม่',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          // แถบบางบอกว่ากำลังโหลดผลค้นหา โดยไม่ต้องล้างตารางเดิมทิ้ง
          SizedBox(
            height: 2,
            child: _loading && _activities.isNotEmpty
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          Expanded(
            child: _loading && _activities.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _activities.isEmpty
                        ? _emptyState(canWrite)
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return constraints.maxWidth > 800
                                  ? _buildTable(canWrite)
                                  : _buildList(canWrite);
                            },
                          ),
          ),
          if (_error == null && _activities.isNotEmpty) _buildPagination(),
        ],
      ),
    );
  }

  /// ไม่มีข้อมูล: แยกกรณี "ค้นหาไม่เจอ" ออกจาก "ยังไม่มีกิจกรรมเลย"
  Widget _emptyState(bool canWrite) {
    if (_search.isNotEmpty || _typeFilter != null) return EmptyState.noResults();
    return EmptyState(
      icon: Icons.event_busy,
      title: 'ยังไม่มีกิจกรรม',
      message: canWrite
          ? 'กดปุ่ม + มุมขวาล่างเพื่อเพิ่มกิจกรรมแรก'
          : 'เมื่อเจ้าหน้าที่เพิ่มกิจกรรม รายการจะแสดงที่นี่',
    );
  }

  Widget _buildTable(bool canWrite) {
    final scheme = Theme.of(context).colorScheme;
    return AppDataTable(
      columns: const [
        DataColumn(label: Text('ชื่อกิจกรรม')),
        DataColumn(label: Text('ประเภท')),
        DataColumn(label: Text('หมวดชั่วโมง')),
        DataColumn(label: Text('ชั่วโมง')),
        DataColumn(label: Text('บังคับ')),
        DataColumn(label: Text('รับสูงสุด')),
        DataColumn(label: Text('วันเวลา')),
        DataColumn(label: Text('สถานที่')),
        DataColumn(label: Text('สถานะอนุมัติ')),
        DataColumn(label: Text('')),
      ],
      rows: [
        for (final a in _activities)
          [
            DataCell(Text(a.name)),
            DataCell(Text(a.activityType)),
            DataCell(Text(_subcategoryLabel(_categories, a.subcategoryId))),
            DataCell(Text(_trimHours(a.hours))),
            DataCell(Tooltip(
              message: a.isRequired ? 'กิจกรรมบังคับ' : 'ไม่บังคับ',
              child: Icon(
                a.isRequired ? Icons.check : Icons.close,
                size: 18,
                color: a.isRequired ? StatusPalette.approved.foreground : scheme.outline,
              ),
            )),
            DataCell(Text('${a.maxParticipants}')),
            DataCell(Text(_formatDateTime(a.startAt))),
            DataCell(Text(a.location)),
            DataCell(_approvalChip(a)),
            DataCell(canWrite ? _actionButtons(a) : const SizedBox.shrink()),
          ],
      ],
    );
  }

  Widget _buildList(bool canWrite) {
    return ListView.builder(
      itemCount: _activities.length,
      itemBuilder: (context, index) {
        final a = _activities[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            onTap: canWrite ? () => _openParticipants(a) : null,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(a.name)),
                const SizedBox(width: 8),
                _approvalChip(a),
              ],
            ),
            subtitle: Text(
              '${a.activityType} • ได้ ${_trimHours(a.hours)} ชม. • ${_formatDateTime(a.startAt)}\n'
              '${a.location} • รับ ${a.maxParticipants} คน${a.isRequired ? " • บังคับ" : ""}',
            ),
            isThreeLine: true,
            trailing: canWrite ? _actionButtons(a) : null,
          ),
        );
      },
    );
  }

  Widget _approvalChip(Activity a) => StatusChip.activityApproval(a.approvalStatus, dense: true);

  Widget _actionButtons(Activity a) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (authService.isAdmin && a.approvalStatus != 'approved')
            IconButton(
              icon: Icon(Icons.check_circle,
                  size: 20, color: StatusPalette.approved.foreground),
              tooltip: 'อนุมัติกิจกรรม',
              onPressed: () => _approve(a),
            ),
          IconButton(
            icon: const Icon(Icons.groups, size: 20),
            tooltip: 'ดูผู้เข้าร่วม',
            onPressed: () => _openParticipants(a),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: 'แก้ไข',
            onPressed: () => _openForm(existing: a),
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
            tooltip: 'ลบ',
            onPressed: () => _delete(a),
          ),
        ],
      );

  Widget _buildPagination() {
    final start = _total == 0 ? 0 : _skip + 1;
    final end = (_skip + _limit) > _total ? _total : (_skip + _limit);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$start-$end จาก $_total'),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _skip > 0
                ? () {
                    setState(() => _skip = (_skip - _limit).clamp(0, _total));
                    _load();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: (_skip + _limit) < _total
                ? () {
                    setState(() => _skip += _limit);
                    _load();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _ActivityFormDialog extends StatefulWidget {
  final Activity? existing;
  final List<HourCategory> categories;
  const _ActivityFormDialog({this.existing, required this.categories});

  @override
  State<_ActivityFormDialog> createState() => _ActivityFormDialogState();
}

class _ActivityFormDialogState extends State<_ActivityFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _maxParticipantsController;
  late final TextEditingController _locationController;
  late final TextEditingController _hoursController;
  String _activityType = _activityTypes.first;
  int? _subcategoryId;
  bool _isRequired = false;
  late DateTime _startAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _maxParticipantsController =
        TextEditingController(text: e != null ? '${e.maxParticipants}' : '50');
    _locationController = TextEditingController(text: e?.location ?? '');
    _hoursController = TextEditingController(
      text: e != null && e.hours > 0 ? _trimHours(e.hours) : '3',
    );
    _activityType = e?.activityType ?? _activityTypes.first;
    _subcategoryId = e?.subcategoryId ??
        (widget.categories.isNotEmpty && widget.categories.first.subcategories.isNotEmpty
            ? widget.categories.first.subcategories.first.id
            : null);
    _isRequired = e?.isRequired ?? false;
    _startAt = e?.startAt ?? DateTime.now().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _maxParticipantsController.dispose();
    _locationController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startAt),
    );
    if (time == null) return;
    setState(() {
      _startAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_subcategoryId == null) {
      setState(() => _error = 'กรุณาเลือกหมวดชั่วโมง');
      return;
    }
    final hours = double.tryParse(_hoursController.text.trim());
    if (hours == null || hours <= 0) {
      setState(() => _error = 'กรุณากรอกจำนวนชั่วโมงมากกว่า 0');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': _nameController.text.trim(),
      'activity_type': _activityType,
      'subcategory_id': _subcategoryId,
      'hours': hours,
      'is_required': _isRequired,
      'max_participants': int.parse(_maxParticipantsController.text.trim()),
      'start_at': _startAt.toIso8601String(),
      'location': _locationController.text.trim(),
    };
    try {
      if (widget.existing == null) {
        await ApiService.create('/activities', body, Activity.fromJson);
      } else {
        await ApiService.update('/activities/${widget.existing!.id}', body, Activity.fromJson);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFormDialog(
      title: widget.existing == null ? 'เพิ่มกิจกรรม' : 'แก้ไขกิจกรรม',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'ชื่อกิจกรรม'),
          validator: requiredValidator,
        ),
        DropdownButtonFormField<String>(
          initialValue: _activityType,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'ประเภท'),
          items: _activityTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _activityType = v ?? _activityTypes.first),
        ),
        // E3: dropdown หมวดชั่วโมง — ชื่อสั้นในช่อง ชื่อเต็มในรายการ ไม่ล้นกรอบ
        SubcategoryDropdown(
          categories: widget.categories,
          value: _subcategoryId,
          onChanged: (v) => setState(() => _subcategoryId = v),
        ),
        TextFormField(
          controller: _hoursController,
          decoration: const InputDecoration(
            labelText: 'ชั่วโมงที่ได้รับเมื่อเข้าร่วม',
            hintText: 'เช่น 4',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            final n = double.tryParse((v ?? '').trim());
            return (n == null || n <= 0) ? 'กรอกจำนวนชั่วโมงมากกว่า 0' : null;
          },
        ),
        TextFormField(
          controller: _maxParticipantsController,
          decoration: const InputDecoration(labelText: 'จำนวนที่รับ'),
          keyboardType: TextInputType.number,
          validator: (v) => int.tryParse(v ?? '') == null ? 'กรอกตัวเลข' : null,
        ),
        TextFormField(
          controller: _locationController,
          decoration: const InputDecoration(labelText: 'สถานที่'),
          validator: requiredValidator,
        ),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'วันเวลาเริ่มกิจกรรม'),
          child: InkWell(
            onTap: _pickDateTime,
            child: Row(
              children: [
                Expanded(child: Text(_formatDateTime(_startAt))),
                const Icon(Icons.calendar_today, size: 18),
              ],
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('กิจกรรมบังคับ'),
          subtitle: const Text('นิสิตทุกคนต้องเข้าร่วม'),
          value: _isRequired,
          onChanged: (v) => setState(() => _isRequired = v),
        ),
      ],
    );
  }
}
