import 'package:flutter/material.dart';

import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/dialogs.dart';

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
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
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
      if (_statusFilter != null) query['status'] = _statusFilter!;
      final page = await ApiService.fetchPage('/students', Student.fromJson, query: query);
      setState(() {
        _students = page.items;
        _total = page.total;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'ค้นหาชื่อ/รหัสนิสิต',
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
                : _students.isEmpty
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
          DataColumn(label: Text('รหัสนิสิต')),
          DataColumn(label: Text('ชื่อ-สกุล')),
          DataColumn(label: Text('คณะ')),
          DataColumn(label: Text('สาขา')),
          DataColumn(label: Text('ชั้นปี')),
          DataColumn(label: Text('สถานะ')),
          DataColumn(label: Text('')),
        ],
        rows: _students
            .map((s) => DataRow(cells: [
                  DataCell(Text(s.studentId)),
                  DataCell(Text(s.fullName)),
                  DataCell(Text(s.faculty)),
                  DataCell(Text(s.major)),
                  DataCell(Text('${s.yearLevel}')),
                  DataCell(_statusChip(s.status)),
                  DataCell(canWrite ? _actionButtons(s) : const SizedBox.shrink()),
                ]))
            .toList(),
      ),
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
          IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _openForm(existing: s)),
          if (authService.isAdmin)
            IconButton(
              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
              onPressed: () => _delete(s),
            ),
        ],
      );

  Widget _statusChip(String status) => Chip(
        label: Text(status == 'active' ? 'กำลังศึกษา' : 'พ้นสภาพ'),
        backgroundColor: status == 'active' ? Colors.green.shade100 : Colors.grey.shade300,
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
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'เพิ่มนิสิต' : 'แก้ไขนิสิต'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  decoration: const InputDecoration(labelText: 'สถานะ'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('กำลังศึกษา')),
                    DropdownMenuItem(value: 'inactive', child: Text('พ้นสภาพ')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'active'),
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
