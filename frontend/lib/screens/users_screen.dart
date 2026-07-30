import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/search_field.dart';

const _roles = ['student', 'staff', 'admin'];

String _roleLabel(String role) {
  switch (role) {
    case 'admin':
      return 'ผู้ดูแลระบบ';
    case 'staff':
      return 'เจ้าหน้าที่';
    default:
      return 'นิสิต';
  }
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser> _users = [];
  List<Student> _students = [];
  bool _loading = false;
  String? _error;
  String _search = '';
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadStudents();
    _load();
  }

  void _onSearch(String value) {
    _search = value;
    _load();
  }

  /// รายชื่อนิสิตใช้แค่แปลง student_id เป็นชื่อในรายการ — โหลดครั้งเดียวพอ
  /// ไม่ต้องดึงใหม่ทุกครั้งที่ค้นหา
  Future<void> _loadStudents() async {
    try {
      final studentsPage = await ApiService.fetchPage(
        '/students',
        Student.fromJson,
        query: {'limit': '500'},
      );
      if (mounted) setState(() => _students = studentsPage.items);
    } catch (_) {
      // ไม่ร้ายแรง: รายการจะแสดงเป็น #id แทนชื่อนิสิต
    }
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, String>{'limit': '200'};
      if (_search.isNotEmpty) query['search'] = _search;
      final page = await ApiService.fetchPage('/auth/users', AppUser.fromJson, query: query);
      // ผลลัพธ์เก่าที่มาช้ากว่าคำค้นหาล่าสุด ต้องไม่ทับของใหม่
      if (!mounted || requestId != _requestId) return;
      setState(() => _users = page.items);
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  String _studentLabel(int? studentId) {
    if (studentId == null) return '';
    for (final s in _students) {
      if (s.id == studentId) return '${s.studentId} ${s.fullName}';
    }
    return '#$studentId';
  }

  Future<void> _openForm({AppUser? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(existing: existing, students: _students),
    );
    if (result == true) _load();
  }

  Future<void> _delete(AppUser user) async {
    final confirmed = await confirmDelete(context, user.username);
    if (confirmed != true) return;
    try {
      await ApiService.delete('/auth/users/${user.id}');
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!authService.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('จัดการผู้ใช้')),
        body: const Center(child: Text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('จัดการผู้ใช้')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                DebouncedSearchField(label: 'ค้นหาชื่อผู้ใช้', onSearch: _onSearch),
                IconButton(
                  onPressed: _load,
                  tooltip: 'โหลดใหม่',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          // แถบบางบอกว่ากำลังโหลดผลค้นหา โดยไม่ต้องล้างรายการเดิมทิ้ง
          SizedBox(
            height: 2,
            child: _loading && _users.isNotEmpty
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          Expanded(
            child: _loading && _users.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _users.isEmpty
                        ? _emptyState()
                        : ListView.builder(
                            itemCount: _users.length,
                            itemBuilder: (context, index) {
                              final u = _users[index];
                              final isSelf = u.username == authService.username;
                              final subtitle = u.role == 'student'
                                  ? '${_roleLabel(u.role)} • ${_studentLabel(u.studentId)}'
                                  : _roleLabel(u.role);
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: ListTile(
                                  leading: const Icon(Icons.person),
                                  title: Text(u.username + (isSelf ? ' (คุณ)' : '')),
                                  subtitle: Text(subtitle),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 20),
                                        tooltip: 'แก้ไข',
                                        onPressed: () => _openForm(existing: u),
                                      ),
                                      // no self-delete (backend also blocks it)
                                      if (!isSelf)
                                        IconButton(
                                          icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                          tooltip: 'ลบ',
                                          onPressed: () => _delete(u),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    if (_search.isNotEmpty) return EmptyState.noResults();
    return const EmptyState(
      icon: Icons.manage_accounts_outlined,
      title: 'ยังไม่มีผู้ใช้',
      message: 'กดปุ่ม + มุมขวาล่างเพื่อสร้างบัญชีผู้ใช้',
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  final AppUser? existing;
  final List<Student> students;
  const _UserFormDialog({this.existing, required this.students});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  late String _role;
  int? _studentId;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.existing?.username ?? '');
    _role = widget.existing?.role ?? 'staff';
    _studentId = widget.existing?.studentId;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == 'student' && _studentId == null) {
      setState(() => _error = 'บัญชีนิสิตต้องเลือกนิสิตที่ผูก');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        final body = <String, dynamic>{
          'role': _role,
          'student_id': _role == 'student' ? _studentId : null,
        };
        if (_passwordController.text.isNotEmpty) body['password'] = _passwordController.text;
        await ApiService.update('/auth/users/${widget.existing!.id}', body, (json) => json);
      } else {
        final body = <String, dynamic>{
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
          'role': _role,
          if (_role == 'student') 'student_id': _studentId,
        };
        await ApiService.create('/auth/register', body, (json) => json);
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
      title: _isEdit ? 'แก้ไขผู้ใช้' : 'เพิ่มผู้ใช้',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        TextFormField(
          controller: _usernameController,
          enabled: !_isEdit, // username is the identity; not editable
          decoration: const InputDecoration(labelText: 'ชื่อผู้ใช้'),
          validator: _isEdit ? null : requiredValidator,
        ),
        TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: _isEdit ? 'รหัสผ่านใหม่ (เว้นว่างไว้ถ้าไม่เปลี่ยน)' : 'รหัสผ่าน',
          ),
          obscureText: true,
          validator: (v) {
            if (_isEdit && (v == null || v.isEmpty)) return null; // keep current
            return (v == null || v.length < 6) ? 'รหัสผ่านอย่างน้อย 6 ตัวอักษร' : null;
          },
        ),
        DropdownButtonFormField<String>(
          initialValue: _role,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'สิทธิ์ (role)'),
          items: _roles
              .map((r) => DropdownMenuItem(value: r, child: Text(_roleLabel(r))))
              .toList(),
          onChanged: (v) => setState(() => _role = v ?? 'staff'),
        ),
        // D1: a student account must be linked to a student record
        if (_role == 'student')
          DropdownButtonFormField<int>(
            initialValue: _studentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'นิสิตที่ผูกบัญชี'),
            items: widget.students
                .map((s) => DropdownMenuItem(
                      value: s.id,
                      child: Text('${s.studentId} ${s.fullName}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _studentId = v),
            validator: (v) => v == null ? 'กรุณาเลือกนิสิต' : null,
          ),
      ],
    );
  }
}
