import 'package:flutter/material.dart';

import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/api_error.dart';
import '../widgets/app_data_table.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/search_field.dart';
import '../widgets/status_chip.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  static const int _limit = 10;

  List<Student> _students = [];
  int _total = 0;
  int _skip = 0;
  bool _loading = false;
  String? _error;
  String _search = '';
  String? _statusFilter;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
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
      if (_statusFilter != null) query['status'] = _statusFilter!;
      final page = await ApiService.fetchPage('/students', Student.fromJson, query: query);
      // ผลลัพธ์เก่าที่มาช้ากว่าคำค้นหาล่าสุด ต้องไม่ทับของใหม่
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _students = page.items;
        _total = page.total;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Student? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _StudentFormDialog(existing: existing),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Student s) async {
    final confirmed = await confirmDelete(context, s.fullName);
    if (confirmed != true) return;
    try {
      await ApiService.delete('/students/${s.id}');
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!authService.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('จัดการนิสิต')),
        body: const Center(child: Text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้')),
      );
    }
    final canWrite = authService.canWrite;
    return Scaffold(
      appBar: AppBar(title: const Text('จัดการนิสิต')),
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
                  label: 'ค้นหาชื่อ/รหัสนิสิต',
                  onSearch: _onSearch,
                ),
                DropdownButton<String?>(
                  value: _statusFilter,
                  hint: const Text('สถานะทั้งหมด'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('สถานะทั้งหมด')),
                    DropdownMenuItem(value: 'active', child: Text('กำลังศึกษา')),
                    DropdownMenuItem(value: 'inactive', child: Text('พ้นสภาพ')),
                  ],
                  onChanged: (v) {
                    setState(() => _statusFilter = v);
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
            child: _loading && _students.isNotEmpty
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          Expanded(
            child: _loading && _students.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _students.isEmpty
                        ? _emptyState()
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return constraints.maxWidth > 800
                                  ? _buildTable(canWrite)
                                  : _buildList(canWrite);
                            },
                          ),
          ),
          if (_error == null && _students.isNotEmpty) _buildPagination(),
        ],
      ),
    );
  }

  Widget _emptyState() {
    if (_search.isNotEmpty || _statusFilter != null) return EmptyState.noResults();
    return const EmptyState(
      icon: Icons.people_outline,
      title: 'ยังไม่มีข้อมูลนิสิต',
      message: 'กดปุ่ม + มุมขวาล่างเพื่อเพิ่มนิสิตคนแรก',
    );
  }

  Widget _buildTable(bool canWrite) {
    return AppDataTable(
      columns: const [
        DataColumn(label: Text('รหัสนิสิต')),
        DataColumn(label: Text('ชื่อ-สกุล')),
        DataColumn(label: Text('คณะ')),
        DataColumn(label: Text('สาขา')),
        DataColumn(label: Text('ชั้นปี'), numeric: true),
        DataColumn(label: Text('สถานะ')),
        DataColumn(label: Text('')),
      ],
      rows: [
        for (final s in _students)
          [
            DataCell(Text(s.studentId)),
            DataCell(Text(s.fullName)),
            DataCell(Text(s.faculty)),
            DataCell(Text(s.major)),
            DataCell(Text('${s.yearLevel}')),
            DataCell(_statusChip(s.status)),
            DataCell(canWrite ? _actionButtons(s) : const SizedBox.shrink()),
          ],
      ],
    );
  }

  Widget _buildList(bool canWrite) {
    return ListView.builder(
      itemCount: _students.length,
      itemBuilder: (context, index) {
        final s = _students[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text(s.fullName),
            subtitle: Text('${s.studentId} • ${s.faculty} / ${s.major} • ปี ${s.yearLevel}'),
            trailing: canWrite
                ? _actionButtons(s)
                : _statusChip(s.status),
          ),
        );
      },
    );
  }

  Widget _actionButtons(Student s) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: 'แก้ไข',
            onPressed: () => _openForm(existing: s),
          ),
          if (authService.isAdmin)
            IconButton(
              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
              tooltip: 'ลบ',
              onPressed: () => _delete(s),
            ),
        ],
      );

  Widget _statusChip(String status) => StatusChip.studentStatus(status, dense: true);

  Widget _buildPagination() => PaginationBar(
        skip: _skip,
        limit: _limit,
        total: _total,
        onChanged: (skip) {
          setState(() => _skip = skip);
          _load();
        },
      );
}

class _StudentFormDialog extends StatefulWidget {
  final Student? existing;
  const _StudentFormDialog({this.existing});

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _studentIdController;
  late final TextEditingController _fullNameController;
  late final TextEditingController _facultyController;
  late final TextEditingController _majorController;
  late final TextEditingController _yearLevelController;
  String _status = 'active';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _studentIdController = TextEditingController(text: e?.studentId ?? '');
    _fullNameController = TextEditingController(text: e?.fullName ?? '');
    _facultyController = TextEditingController(text: e?.faculty ?? '');
    _majorController = TextEditingController(text: e?.major ?? '');
    _yearLevelController = TextEditingController(text: e != null ? '${e.yearLevel}' : '1');
    _status = e?.status ?? 'active';
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _fullNameController.dispose();
    _facultyController.dispose();
    _majorController.dispose();
    _yearLevelController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'student_id': _studentIdController.text.trim(),
      'full_name': _fullNameController.text.trim(),
      'faculty': _facultyController.text.trim(),
      'major': _majorController.text.trim(),
      'year_level': int.parse(_yearLevelController.text.trim()),
      'status': _status,
    };
    try {
      if (widget.existing == null) {
        await ApiService.create('/students', body, Student.fromJson);
      } else {
        await ApiService.update('/students/${widget.existing!.id}', body, Student.fromJson);
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
      title: widget.existing == null ? 'เพิ่มนิสิต' : 'แก้ไขนิสิต',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        TextFormField(
          controller: _studentIdController,
          decoration: const InputDecoration(labelText: 'รหัสนิสิต'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _fullNameController,
          decoration: const InputDecoration(labelText: 'ชื่อ-สกุล'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _facultyController,
          decoration: const InputDecoration(labelText: 'คณะ'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _majorController,
          decoration: const InputDecoration(labelText: 'สาขา'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _yearLevelController,
          decoration: const InputDecoration(labelText: 'ชั้นปี'),
          keyboardType: TextInputType.number,
          validator: (v) => int.tryParse(v ?? '') == null ? 'กรอกตัวเลข' : null,
        ),
        DropdownButtonFormField<String>(
          initialValue: _status,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'สถานะ'),
          items: const [
            DropdownMenuItem(value: 'active', child: Text('กำลังศึกษา')),
            DropdownMenuItem(value: 'inactive', child: Text('พ้นสภาพ')),
          ],
          onChanged: (v) => setState(() => _status = v ?? 'active'),
        ),
      ],
    );
  }
}
