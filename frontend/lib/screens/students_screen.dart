import 'package:flutter/material.dart';

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
    final result = await showDialog<StudentSaveResult>(
      context: context,
      builder: (_) => StudentFormDialog(existing: existing),
    );
    if (result == null) return;
    _load();
    // บอกชื่อผู้ใช้ที่เพิ่งสร้างทันที ผู้ดูแลจะได้แจ้งนิสิตต่อได้โดยไม่ต้องเปิด
    // หน้าจัดการผู้ใช้ไปหาเอง
    final username = result.username;
    if (username != null && mounted) {
      showInfoSnackbar(
        context,
        accountCreatedMessage(username, customPassword: result.customPassword),
      );
    }
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
      return const AppShell(
        activeId: 'students',
        body: Center(child: Text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้')),
      );
    }
    final canWrite = authService.canWrite;
    return AdminPage(
      activeId: 'students',
      title: 'จัดการนิสิต',
      subtitle: 'นิสิตทั้งหมด $_total คน',
      actions: [
        if (canWrite)
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('เพิ่มนิสิต'),
          ),
      ],
      filters: [
        DebouncedSearchField(label: 'ค้นหาชื่อ/รหัสนิสิต', onSearch: _onSearch),
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
        AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: _load),
      ],
      // แถบบางบอกว่ากำลังโหลดผลค้นหา โดยไม่ต้องล้างตารางเดิมทิ้ง
      busy: _loading && _students.isNotEmpty,
      footer: _error == null && _students.isNotEmpty ? _buildPagination() : null,
      child: _loading && _students.isEmpty
          ? const LoadingState(message: 'กำลังโหลดข้อมูลนิสิต...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _students.isEmpty
                  ? _emptyState()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return constraints.maxWidth > 800
                            ? TableCard(child: _buildTable(canWrite))
                            : _buildList(canWrite);
                      },
                    ),
    );
  }

  Widget _emptyState() {
    if (_search.isNotEmpty || _statusFilter != null) return EmptyState.noResults();
    return const EmptyState(
      icon: Icons.people_outline,
      title: 'ยังไม่มีข้อมูลนิสิต',
      message: 'กดปุ่ม "เพิ่มนิสิต" ด้านบนเพื่อเพิ่มนิสิตคนแรก',
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
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
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

  Widget _actionButtons(Student s) => Wrap(
        spacing: AppSpacing.xs,
        children: [
          AppIconButton(
            icon: Icons.edit,
            tooltip: 'แก้ไข',
            onPressed: () => _openForm(existing: s),
          ),
          if (authService.isAdmin)
            AppIconButton(
              icon: Icons.delete,
              danger: true,
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

/// ผลลัพธ์ของการบันทึกฟอร์มนิสิต
///
/// [username] มีค่าเฉพาะตอนที่เพิ่งสร้างบัญชีเข้าใช้งานให้ด้วย — ใช้บอกผู้ดูแล
/// ว่านิสิตคนนี้จะล็อกอินด้วยชื่ออะไร (เป็น null ตอนแก้ไข หรือตอนไม่ได้ขอบัญชี)
class StudentSaveResult {
  final String? username;

  /// true = ผู้ดูแลตั้งรหัสผ่านเอง (ข้อความแจ้งจะได้ไม่ไปบอกว่าเป็นรหัสนิสิต)
  final bool customPassword;

  const StudentSaveResult({this.username, this.customPassword = false});
}

/// ข้อความแจ้งหลังสร้างบัญชีให้นิสิตสำเร็จ
///
/// แยกเป็นฟังก์ชันเพื่อให้เทสต์ได้โดยไม่ต้องประกอบทั้งหน้าจอ
String accountCreatedMessage(String username, {required bool customPassword}) {
  final password = customPassword ? 'ตามที่กำหนดไว้' : 'รหัสนิสิต';
  return 'สร้างบัญชีนิสิตแล้ว · ชื่อผู้ใช้: $username · '
      'รหัสผ่านเริ่มต้น: $password (แนะนำให้เปลี่ยนหลังเข้าใช้ครั้งแรก)';
}

/// ตรวจรูปแบบรหัสนิสิต — ตัวเลขล้วน 9 หลักตามรูปแบบของมหาวิทยาลัย
String? studentIdValidator(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return 'กรอกรหัสนิสิต';
  if (!RegExp(r'^\d{9}$').hasMatch(text)) return 'รหัสนิสิตต้องเป็นตัวเลข 9 หลัก';
  return null;
}

class StudentFormDialog extends StatefulWidget {
  final Student? existing;
  const StudentFormDialog({super.key, this.existing});

  @override
  State<StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<StudentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _studentIdController;
  late final TextEditingController _fullNameController;
  late final TextEditingController _facultyController;
  late final TextEditingController _majorController;
  late final TextEditingController _yearLevelController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  String _status = 'active';
  // นิสิตใหม่ควรได้บัญชีเข้าใช้งานไปพร้อมกัน ไม่ต้องไปสร้างต่ออีกหน้าแล้วลืมผูก
  bool _createUser = true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _studentIdController = TextEditingController(text: e?.studentId ?? '');
    _fullNameController = TextEditingController(text: e?.fullName ?? '');
    _facultyController = TextEditingController(text: e?.faculty ?? '');
    _majorController = TextEditingController(text: e?.major ?? '');
    _yearLevelController = TextEditingController(text: e != null ? '${e.yearLevel}' : '1');
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _status = e?.status ?? 'active';
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _fullNameController.dispose();
    _facultyController.dispose();
    _majorController.dispose();
    _yearLevelController.dispose();
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
    final studentId = _studentIdController.text.trim();
    // เว้นว่าง = ให้ backend ใช้รหัสนิสิตเป็นค่าเริ่มต้น จึงไม่ส่งคีย์ไปเลย
    // (ส่งสตริงว่างไปก็ได้ผลเหมือนกัน แต่ไม่ส่งอ่านเจตนาได้ชัดกว่า)
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final wantsAccount = _isNew && _createUser;

    final body = {
      'student_id': studentId,
      'full_name': _fullNameController.text.trim(),
      'faculty': _facultyController.text.trim(),
      'major': _majorController.text.trim(),
      'year_level': int.parse(_yearLevelController.text.trim()),
      'status': _status,
      // ส่งเฉพาะตอนสร้างใหม่ — backend ไม่รับฟิลด์นี้ตอนแก้ไข
      if (_isNew) 'create_user': _createUser,
      if (wantsAccount && username.isNotEmpty) 'username': username,
      if (wantsAccount && password.isNotEmpty) 'password': password,
    };
    try {
      if (_isNew) {
        final created = await ApiService.create<Map<String, dynamic>>(
          '/students',
          body,
          (json) => json,
        );
        if (!mounted) return;
        Navigator.pop(
          context,
          StudentSaveResult(
            username: created['username'] as String?,
            customPassword: password.isNotEmpty,
          ),
        );
      } else {
        await ApiService.update('/students/${widget.existing!.id}', body, Student.fromJson);
        if (mounted) Navigator.pop(context, const StudentSaveResult());
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// ป้ายช่องแบบเดียวกันทั้งฟอร์ม
  ///
  /// M3 จะเก็บ label ไว้ "ข้างใน" ช่องที่ยังว่าง แล้วค่อยลอยขึ้นเมื่อมีค่า —
  /// ฟอร์มนี้จึงเคยดูไม่สม่ำเสมอ (ชั้นปี/สถานะ มีค่าเริ่มต้นอยู่แล้วเลยลอย
  /// ส่วนช่องที่เหลือว่างจึงดูเหมือน placeholder) บังคับ `always` ให้ label
  /// อยู่ด้านบนเหมือนกันหมด แล้วใช้ hint เป็นตัวอย่างข้างในช่องแทน
  InputDecoration _decoration(
    String label, {
    bool required = false,
    String? hint,
    String? helper,
  }) =>
      InputDecoration(
        labelText: required ? '$label *' : '$label (ไม่บังคับ)',
        hintText: hint,
        helperText: helper,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppFormDialog(
      title: widget.existing == null ? 'เพิ่มนิสิต' : 'แก้ไขนิสิต',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        const FormSectionHeader(
          'ข้อมูลนิสิต',
          note: 'ช่องที่มีเครื่องหมาย * จำเป็นต้องกรอก',
          first: true,
        ),
        TextFormField(
          controller: _studentIdController,
          decoration: _decoration('รหัสนิสิต', required: true, hint: 'ตัวเลข 9 หลัก'),
          keyboardType: TextInputType.number,
          validator: studentIdValidator,
        ),
        TextFormField(
          controller: _fullNameController,
          decoration: _decoration('ชื่อ-สกุล', required: true, hint: 'เช่น สมชาย ใจดี'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _facultyController,
          decoration: _decoration('คณะ', required: true, hint: 'เช่น วิศวกรรมศาสตร์'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _majorController,
          decoration: _decoration('สาขา', required: true, hint: 'เช่น วิศวกรรมคอมพิวเตอร์'),
          validator: requiredValidator,
        ),
        TextFormField(
          controller: _yearLevelController,
          decoration: _decoration('ชั้นปี', required: true),
          keyboardType: TextInputType.number,
          validator: (v) => int.tryParse(v ?? '') == null ? 'กรอกตัวเลข' : null,
        ),
        DropdownButtonFormField<String>(
          initialValue: _status,
          isExpanded: true,
          decoration: _decoration('สถานะ', required: true),
          items: const [
            DropdownMenuItem(value: 'active', child: Text('กำลังศึกษา')),
            DropdownMenuItem(value: 'inactive', child: Text('พ้นสภาพ')),
          ],
          onChanged: (v) => setState(() => _status = v ?? 'active'),
        ),
        // เฉพาะตอนสร้างใหม่ — บัญชีที่มีอยู่แล้วต้องไปจัดการที่หน้าจัดการผู้ใช้
        if (_isNew) ...[
          const FormSectionHeader('บัญชีเข้าใช้งาน'),
          CheckboxListTile(
            value: _createUser,
            onChanged: (v) => setState(() => _createUser = v ?? false),
            title: const Text('สร้างบัญชีเข้าใช้งานให้ด้วย'),
            subtitle: Text(
              _createUser
                  ? 'เว้นช่องด้านล่างว่างไว้ = ใช้รหัสนิสิตเป็นทั้งชื่อผู้ใช้และรหัสผ่านเริ่มต้น'
                  : 'ต้องไปสร้างบัญชีและผูกเองที่หน้าจัดการผู้ใช้',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            // ดึงตัวติ๊กกับข้อความให้ชิดซ้ายติดกัน ไม่เหลือช่องว่างกลางแถว
            visualDensity: VisualDensity.compact,
            dense: true,
          ),
          // ช่องกำหนดเอง โผล่เฉพาะตอนที่จะสร้างบัญชีจริง ๆ เพื่อไม่ให้ฟอร์มรก
          if (_createUser) ...[
            TextFormField(
              controller: _usernameController,
              decoration: _decoration(
                'ชื่อผู้ใช้',
                hint: 'รหัสนิสิต',
                helper: 'เว้นว่าง = ใช้รหัสนิสิต',
              ),
            ),
            TextFormField(
              controller: _passwordController,
              decoration: _decoration(
                'รหัสผ่านเริ่มต้น',
                helper: 'เว้นว่าง = ใช้รหัสนิสิต · แนะนำให้นิสิตเปลี่ยนหลังเข้าใช้ครั้งแรก',
              ),
            ),
          ],
        ],
      ],
    );
  }
}
