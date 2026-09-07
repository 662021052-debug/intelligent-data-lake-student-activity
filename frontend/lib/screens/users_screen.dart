import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/app_data_table.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/search_field.dart';
import '../widgets/status_chip.dart';
import 'app_shell.dart';

/// สิทธิ์ที่สร้างได้จากหน้านี้ — ไม่มี "นิสิต"
///
/// บัญชีนิสิตต้องมาคู่กับข้อมูลนิสิตเสมอ จึงสร้างได้ทางเดียวคือฟอร์มเพิ่มนิสิต
/// ที่หน้าจัดการนิสิต (backend ก็ปฏิเสธ role=student ที่ endpoint นี้อยู่แล้ว)
const creatableRoles = ['staff', 'admin'];

/// สีป้ายบทบาทตาม mockup — นิสิตฟ้า เจ้าหน้าที่เขียว แอดมินม่วง
/// (คนละความหมายกับชิป "สถานะ" จึงไม่ใช้ StatusPalette ชุดสถานะ)
const _rolePalettes = <String, StatusPalette>{
  'admin': StatusPalette(Color(0xFFF3EAF7), Color(0xFF6B2E86), Color(0xFF6B2E86)),
  'staff': StatusPalette(Color(0xFFEAF3E9), Color(0xFF2E6B33), Color(0xFF2E6B33)),
  'student': StatusPalette.info,
};

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
  static const int _limit = 50;

  List<AppUser> _users = [];
  List<Student> _students = [];
  int _total = 0;
  int _skip = 0;
  bool _loading = false;
  String? _error;
  String? _studentsError;
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
    _skip = 0;
    _load();
  }

  /// รายชื่อนิสิตใช้แค่แปลง student_id เป็นชื่อและเป็นตัวเลือกใน dropdown
  /// — ต้องได้ครบทุกคน จึงไล่ดึงทีละหน้าแทนการขอ limit ก้อนใหญ่ครั้งเดียว
  /// (ขอเกินเพดาน 200 ของ backend จะได้ 422 แล้ว dropdown ว่างจนสร้างบัญชีนิสิตไม่ได้)
  Future<void> _loadStudents() async {
    try {
      final students = await ApiService.fetchAll('/students', Student.fromJson);
      if (mounted) setState(() => _students = students);
    } catch (e) {
      // ไม่ร้ายแรงพอจะบล็อกทั้งหน้า แต่ต้องเตือน ไม่งั้นฟอร์มพังเงียบ ๆ
      if (mounted) setState(() => _studentsError = friendlyError(e));
    }
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
      final page = await ApiService.fetchPage('/auth/users', AppUser.fromJson, query: query);
      // ผลลัพธ์เก่าที่มาช้ากว่าคำค้นหาล่าสุด ต้องไม่ทับของใหม่
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _users = page.items;
        _total = page.total;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  String _studentLabel(int? studentId) {
    // บัญชีนิสิตที่ยังไม่ผูกต้องอ่านออกว่า "ยังไม่ผูก" ไม่ใช่ปล่อยว่างจนเหลือ "นิสิต • "
    if (studentId == null) return 'ยังไม่ผูกข้อมูลนิสิต';
    for (final s in _students) {
      if (s.id == studentId) return '${s.studentId} ${s.fullName}';
    }
    return '#$studentId';
  }

  Future<void> _openForm({AppUser? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => UserFormDialog(existing: existing),
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
      return const AppShell(
        activeId: 'users',
        body: Center(child: Text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้')),
      );
    }
    return AdminPage(
      activeId: 'users',
      title: 'จัดการผู้ใช้',
      subtitle: 'บัญชีทั้งหมด $_total คน',
      actions: [
        FilledButton.icon(
          onPressed: () => _openForm(),
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('เพิ่มผู้ใช้'),
        ),
      ],
      filters: [
        DebouncedSearchField(label: 'ค้นหาชื่อผู้ใช้', onSearch: _onSearch),
        AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: _load),
      ],
      // แถบบางบอกว่ากำลังโหลดผลค้นหา โดยไม่ต้องล้างรายการเดิมทิ้ง
      busy: _loading && _users.isNotEmpty,
      footer: _error == null && _users.isNotEmpty
          ? PaginationBar(
              skip: _skip,
              limit: _limit,
              total: _total,
              onChanged: (skip) {
                setState(() => _skip = skip);
                _load();
              },
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // รายชื่อนิสิตใช้แปลง student_id เป็นชื่อในรายการเท่านั้น โหลดไม่ได้ก็ยัง
          // ใช้หน้านี้ได้ แต่ต้องบอก ไม่ใช่ปล่อยให้ขึ้นเป็นรหัสภายในเงียบ ๆ
          if (_studentsError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'โหลดรายชื่อนิสิตไม่สำเร็จ ($_studentsError) — '
                      'ช่องนิสิตของบัญชีนิสิตจะแสดงเป็นรหัสภายในแทนชื่อ',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading && _users.isEmpty
                ? const LoadingState(message: 'กำลังโหลดบัญชีผู้ใช้...')
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _users.isEmpty
                        ? _emptyState()
                        : LayoutBuilder(
                            builder: (context, constraints) => constraints.maxWidth > 720
                                ? TableCard(child: _buildTable())
                                : _buildList(),
                          ),
          ),
        ],
      ),
    );
  }

  /// ตารางแบบ mockup: ชื่อผู้ใช้ / ชื่อ-นามสกุล / บทบาท / จัดการ
  ///
  /// ชื่อ-นามสกุลมีเฉพาะบัญชีที่ผูกกับข้อมูลนิสิต — บัญชีเจ้าหน้าที่/แอดมินไม่มี
  /// ชื่อจริงเก็บไว้ในระบบ จึงแสดงขีดแทนการเดา
  Widget _buildTable() {
    return AppDataTable(
      columns: const [
        DataColumn(label: Text('ชื่อผู้ใช้')),
        DataColumn(label: Text('ชื่อ-นามสกุล')),
        DataColumn(label: Text('บทบาท')),
        DataColumn(label: Text('จัดการ')),
      ],
      rows: [
        for (final u in _users)
          [
            DataCell(Text(
              u.username + (_isSelf(u) ? ' (คุณ)' : ''),
              style: const TextStyle(fontWeight: FontWeight.w600),
            )),
            DataCell(Text(
              u.role == 'student' ? _studentLabel(u.studentId) : '-',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.sub),
            )),
            DataCell(_roleChip(u.role)),
            DataCell(_actionButtons(u)),
          ],
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final u = _users[index];
        final subtitle = u.role == 'student'
            ? '${_roleLabel(u.role)} • ${_studentLabel(u.studentId)}'
            : _roleLabel(u.role);
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(u.username + (_isSelf(u) ? ' (คุณ)' : '')),
            subtitle: Text(subtitle),
            trailing: _actionButtons(u),
          ),
        );
      },
    );
  }

  bool _isSelf(AppUser u) => u.username == authService.username;

  Widget _roleChip(String role) => StatusChip(
        label: _roleLabel(role),
        palette: _rolePalettes[role] ?? StatusPalette.neutral,
        dense: true,
      );

  Widget _actionButtons(AppUser u) => Wrap(
        spacing: AppSpacing.xs,
        children: [
          AppIconButton(
            icon: Icons.edit,
            tooltip: 'แก้ไข',
            onPressed: () => _openForm(existing: u),
          ),
          // no self-delete (backend also blocks it)
          if (!_isSelf(u))
            AppIconButton(
              icon: Icons.delete,
              danger: true,
              tooltip: 'ลบ',
              onPressed: () => _delete(u),
            ),
        ],
      );

  Widget _emptyState() {
    if (_search.isNotEmpty) return EmptyState.noResults();
    return const EmptyState(
      icon: Icons.manage_accounts_outlined,
      title: 'ยังไม่มีผู้ใช้',
      message: 'กดปุ่ม + มุมขวาล่างเพื่อสร้างบัญชีผู้ใช้',
    );
  }
}

class UserFormDialog extends StatefulWidget {
  final AppUser? existing;
  const UserFormDialog({super.key, this.existing});

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  late String _role;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  /// บัญชีนิสิตที่มีอยู่แล้ว — แก้ได้แค่รหัสผ่าน สิทธิ์กับการผูกข้อมูลนิสิต
  /// ต้องไปจัดการที่หน้าจัดการนิสิต
  bool get _isStudentAccount => widget.existing?.role == 'student';

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.existing?.username ?? '');
    _role = widget.existing?.role ?? 'staff';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        // ไม่ส่ง student_id อีกแล้ว — backend ตัดฟิลด์นี้ออกจาก UserUpdate และ
        // ตอบ 422 ถ้าส่งมา การผูกบัญชีกับนิสิตเกิดที่เดียวคือตอนสร้างนิสิต
        final body = <String, dynamic>{
          // บัญชีนิสิตเปลี่ยนสิทธิ์จากหน้านี้ไม่ได้ จึงไม่ส่ง role ไปด้วยซ้ำ
          if (!_isStudentAccount) 'role': _role,
        };
        if (_passwordController.text.isNotEmpty) body['password'] = _passwordController.text;
        await ApiService.update('/auth/users/${widget.existing!.id}', body, (json) => json);
      } else {
        final body = <String, dynamic>{
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
          'role': _role,
        };
        await ApiService.create('/auth/register', body, (json) => json);
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
        // บัญชีนิสิตเดิม: แสดงสิทธิ์แบบอ่านอย่างเดียว เปลี่ยนจากหน้านี้ไม่ได้
        if (_isStudentAccount)
          TextFormField(
            initialValue: _roleLabel('student'),
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'สิทธิ์ (role)',
              helperText: 'บัญชีนิสิตแก้ได้เฉพาะรหัสผ่าน — ข้อมูลนิสิตแก้ที่หน้าจัดการนิสิต',
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: creatableRoles.contains(_role) ? _role : creatableRoles.first,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'สิทธิ์ (role)'),
            items: creatableRoles
                .map((r) => DropdownMenuItem(value: r, child: Text(_roleLabel(r))))
                .toList(),
            onChanged: (v) => setState(() => _role = v ?? creatableRoles.first),
          ),
        // บอกทางแทน dropdown "นิสิตที่ผูกบัญชี" ที่ถูกตัดออกไป
        if (!_isEdit)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'ต้องการเพิ่มนิสิต? ไปที่หน้าจัดการนิสิต → เพิ่มนิสิต '
                    '(ระบบจะสร้างบัญชีเข้าใช้งานให้พร้อมข้อมูลนิสิตในขั้นตอนเดียว)',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
