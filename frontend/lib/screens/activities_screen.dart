import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/hour_category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/dialogs.dart';
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
  final _searchController = TextEditingController();

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, String>{'skip': '$_skip', 'limit': '$_limit'};
      if (_search.isNotEmpty) query['search'] = _search;
      if (_typeFilter != null) query['activity_type'] = _typeFilter!;
      final page = await ApiService.fetchPage('/activities', Activity.fromJson, query: query);
      setState(() {
        _activities = page.items;
        _total = page.total;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
    return Scaffold(
      appBar: AppBar(title: const Text('จัดการกิจกรรม')),
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
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'ค้นหาชื่อกิจกรรม',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      _search = v.trim();
                      _skip = 0;
                      _load();
                    },
                  ),
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
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _activities.isEmpty
                    ? const Center(child: Text('ไม่พบข้อมูล'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return constraints.maxWidth > 800
                              ? _buildTable(canWrite)
                              : _buildList(canWrite);
                        },
                      ),
          ),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildTable(bool canWrite) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('ชื่อกิจกรรม')),
          DataColumn(label: Text('ประเภท')),
          DataColumn(label: Text('หมวดชั่วโมง')),
          DataColumn(label: Text('บังคับ')),
          DataColumn(label: Text('รับสูงสุด')),
          DataColumn(label: Text('วันเวลา')),
          DataColumn(label: Text('สถานที่')),
          DataColumn(label: Text('สถานะอนุมัติ')),
          DataColumn(label: Text('')),
        ],
        rows: _activities
            .map((a) => DataRow(cells: [
                  DataCell(Text(a.name)),
                  DataCell(Text(a.activityType)),
                  DataCell(Text(_subcategoryLabel(_categories, a.subcategoryId))),
                  DataCell(Icon(a.isRequired ? Icons.check : Icons.close,
                      size: 18, color: a.isRequired ? Colors.green : Colors.grey)),
                  DataCell(Text('${a.maxParticipants}')),
                  DataCell(Text(_formatDateTime(a.startAt))),
                  DataCell(Text(a.location)),
                  DataCell(_approvalChip(a)),
                  DataCell(canWrite ? _actionButtons(a) : const SizedBox.shrink()),
                ]))
            .toList(),
      ),
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
              '${a.activityType} • ${_formatDateTime(a.startAt)} • ${a.location}\n'
              'รับ ${a.maxParticipants} คน${a.isRequired ? " • บังคับ" : ""}',
            ),
            isThreeLine: true,
            trailing: canWrite ? _actionButtons(a) : null,
          ),
        );
      },
    );
  }

  Widget _approvalChip(Activity a) => Chip(
        label: Text(a.approvalStatus == 'approved' ? 'อนุมัติแล้ว' : 'รออนุมัติ'),
        backgroundColor:
            a.approvalStatus == 'approved' ? Colors.green.shade100 : Colors.amber.shade100,
      );

  Widget _actionButtons(Activity a) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (authService.isAdmin && a.approvalStatus != 'approved')
            IconButton(
              icon: const Icon(Icons.check_circle, size: 20, color: Colors.green),
              tooltip: 'อนุมัติ',
              onPressed: () => _approve(a),
            ),
          IconButton(
            icon: const Icon(Icons.groups, size: 20),
            tooltip: 'ดูผู้เข้าร่วม',
            onPressed: () => _openParticipants(a),
          ),
          IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _openForm(existing: a)),
          IconButton(
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
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
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': _nameController.text.trim(),
      'activity_type': _activityType,
      'subcategory_id': _subcategoryId,
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
    return AlertDialog(
      title: Text(widget.existing == null ? 'เพิ่มกิจกรรม' : 'แก้ไขกิจกรรม'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'ชื่อกิจกรรม'),
                  validator: requiredValidator,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _activityType,
                  decoration: const InputDecoration(labelText: 'ประเภท'),
                  items: _activityTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _activityType = v ?? _activityTypes.first),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _subcategoryId,
                  decoration: const InputDecoration(labelText: 'หมวดชั่วโมง'),
                  items: [
                    for (final category in widget.categories)
                      for (final sub in category.subcategories)
                        DropdownMenuItem(
                          value: sub.id,
                          child: Text('${category.name} › ${sub.name}', overflow: TextOverflow.ellipsis),
                        ),
                  ],
                  onChanged: (v) => setState(() => _subcategoryId = v),
                  validator: (v) => v == null ? 'กรุณาเลือกหมวดชั่วโมง' : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('กิจกรรมบังคับ'),
                  value: _isRequired,
                  onChanged: (v) => setState(() => _isRequired = v),
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('วันเวลาเริ่มกิจกรรม'),
                  subtitle: Text(_formatDateTime(_startAt)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: _pickDateTime,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('บันทึก'),
        ),
      ],
    );
  }
}
