import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/hour_category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../widgets/app_data_table.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/search_field.dart';
import '../widgets/status_chip.dart';
import '../widgets/subcategory_dropdown.dart';
import 'activity_participants_screen.dart';
import 'checkin_qr_screen.dart';

const _activityTypes = ['จิตอาสา', 'กีฬา', 'วิชาการ', 'ศิลปวัฒนธรรม', 'อบรม/สัมมนา'];

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}

String _trimHours(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toString();

/// ข้อความเดียวกับที่ backend ตอบ (400) เมื่อกันกิจกรรมย้อนหลัง — ฝั่ง UI กันเอง
/// ก่อนยิง API ด้วย จะได้ไม่ต้องรอ round-trip กว่าจะรู้ว่าเลือกวันไม่ได้
const kBackdatedActivityMessage = 'ไม่สามารถตั้งวันเวลากิจกรรมเป็นอดีตได้';

/// วันแรกที่เลือกเป็นวันจัดกิจกรรมได้ = วันนี้ (ตัดเวลาออก ให้เลือกวันนี้ได้ทั้งวัน)
///
/// รับ [now] เข้ามาได้เพื่อให้เทสต์ตรึงเวลาได้ ไม่ต้องพึ่งนาฬิกาเครื่องที่รันเทสต์
DateTime activityFirstSelectableDate([DateTime? now]) {
  final today = now ?? DateTime.now();
  return DateTime(today.year, today.month, today.day);
}

/// [startAt] ตกวันก่อนวันนี้หรือไม่ — เทียบระดับวันให้ตรงกับกฎฝั่ง backend
bool isBackdatedActivity(DateTime startAt, [DateTime? now]) =>
    startAt.isBefore(activityFirstSelectableDate(now));

/// error ที่ควรไปโผล่ใต้ช่อง "วันเวลาเริ่มกิจกรรม" แทนกล่อง error รวมท้ายฟอร์ม
/// — ผู้ใช้จะได้เห็นว่าปัญหาอยู่ที่ช่องไหน ไม่ต้องไล่หาเอง
bool isActivityDateError(String message) => message.contains('วันเวลากิจกรรมเป็นอดีต');

/// คอลัมน์ของตารางกิจกรรม — แยกเป็นฟังก์ชันบนสุดเพื่อให้เทสต์ยืนยันได้ว่ามุมมอง
/// นิสิตไม่มีคอลัมน์ "สถานะอนุมัติ" (หน้าจอเต็มต้องยิง API จริงจึงเทสต์ตรง ๆ ไม่ได้)
List<DataColumn> activityTableColumns(bool isStudent) => [
      const DataColumn(label: Text('ชื่อกิจกรรม')),
      const DataColumn(label: Text('ประเภท')),
      const DataColumn(label: Text('หมวดชั่วโมง')),
      const DataColumn(label: Text('ชั่วโมง')),
      const DataColumn(label: Text('บังคับ')),
      const DataColumn(label: Text('รับสูงสุด')),
      const DataColumn(label: Text('วันเวลา')),
      const DataColumn(label: Text('สถานที่')),
      // นิสิตเห็นเฉพาะกิจกรรมที่อนุมัติแล้ว (backend กรองให้) คอลัมน์นี้จึงเป็น
      // ค่าเดียวกันทุกแถว ไม่ให้ข้อมูลอะไร — ซ่อนเฉพาะมุมมองนิสิต
      if (!isStudent) const DataColumn(label: Text('สถานะอนุมัติ')),
      const DataColumn(label: Text('')),
    ];

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

  /// มุมมองนิสิตเริ่มต้นที่ "เฉพาะกิจกรรมที่ยังไม่ถึงวันจัด" — เปิดอันนี้เพื่อดูย้อนหลัง
  /// (ฝั่ง staff/admin ยังเห็นทุกกิจกรรมเรียงล่าสุดก่อนเหมือนเดิม)
  bool _includePast = false;

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
      // นิสิตเปิดหน้ามาต้องเจอกิจกรรมที่ยังสมัคร/เข้าร่วมทันได้ก่อน ไม่ใช่ของอีกปีหน้า
      // ที่บังเอิญวันจัดไกลสุด (ลำดับปกติเรียงวันจัดจากใหม่ไปเก่า)
      if (authService.role == 'student' && !_includePast) query['upcoming'] = 'true';
      final page = await ApiService.fetchPage('/activities', Activity.fromJson, query: query);
      // ผลลัพธ์เก่าที่มาช้ากว่าคำค้นหาล่าสุด ต้องไม่ทับของใหม่
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _activities = page.items;
        _total = page.total;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Activity? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ActivityFormDialog(existing: existing, categories: _categories),
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

  void _openCheckinQr(Activity a) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckinQrScreen(activityId: a.id!, activityName: a.name),
      ),
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
                if (isStudent)
                  FilterChip(
                    label: const Text('รวมกิจกรรมที่จัดไปแล้ว'),
                    selected: _includePast,
                    onSelected: (value) {
                      setState(() => _includePast = value);
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
                                  ? _buildTable(canWrite, isStudent)
                                  : _buildList(canWrite, isStudent);
                            },
                          ),
          ),
          if (_error == null && _activities.isNotEmpty) _buildPagination(),
        ],
      ),
    );
  }

  /// ไม่มีข้อมูล: แยกกรณี "ค้นหาไม่เจอ" / "ยังไม่มีอันที่กำลังจะถึง" / "ไม่มีเลย"
  Widget _emptyState(bool canWrite) {
    if (_search.isNotEmpty || _typeFilter != null) return EmptyState.noResults();
    // นิสิตที่ยังไม่ได้เปิดดูย้อนหลัง อาจมีกิจกรรมในระบบอยู่ แค่จัดไปหมดแล้ว
    if (!canWrite && !_includePast) {
      return const EmptyState(
        icon: Icons.event_busy,
        title: 'ยังไม่มีกิจกรรมที่กำลังจะถึง',
        message: 'เปิด "รวมกิจกรรมที่จัดไปแล้ว" เพื่อดูย้อนหลัง '
            'หรือรอเจ้าหน้าที่เพิ่มกิจกรรมใหม่',
      );
    }
    return EmptyState(
      icon: Icons.event_busy,
      title: 'ยังไม่มีกิจกรรม',
      message: canWrite
          ? 'กดปุ่ม + มุมขวาล่างเพื่อเพิ่มกิจกรรมแรก'
          : 'เมื่อเจ้าหน้าที่เพิ่มกิจกรรม รายการจะแสดงที่นี่',
    );
  }

  Widget _buildTable(bool canWrite, bool isStudent) {
    final scheme = Theme.of(context).colorScheme;
    return AppDataTable(
      columns: activityTableColumns(isStudent),
      rows: [
        for (final a in _activities)
          [
            DataCell(Text(a.name)),
            DataCell(Text(a.activityType)),
            DataCell(Text(subcategoryPath(_categories, a.subcategoryId))),
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
            if (!isStudent) DataCell(_approvalChip(a)),
            DataCell(canWrite ? _actionButtons(a) : const SizedBox.shrink()),
          ],
      ],
    );
  }

  Widget _buildList(bool canWrite, bool isStudent) {
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
                if (!isStudent) ...[
                  const SizedBox(width: 8),
                  _approvalChip(a),
                ],
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
          // แสดงเฉพาะกิจกรรมที่อนุมัติแล้ว — กิจกรรมที่ยังรออนุมัติสแกนไม่ผ่านอยู่ดี
          // (backend ตอบ "กิจกรรมนี้ยังไม่เปิดให้เช็กอิน") การโชว์ QR จึงมีแต่ทำให้เข้าใจผิด
          if (a.approvalStatus == 'approved')
            IconButton(
              icon: const Icon(Icons.qr_code_2, size: 20),
              tooltip: 'แสดง QR เช็กอิน',
              onPressed: () => _openCheckinQr(a),
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

/// ฟอร์มเพิ่ม/แก้ไขกิจกรรม — public เพื่อให้เทสต์ pump ตรง ๆ ได้ (หน้าเต็มต้องยิง
/// API จริง จึงเปิด dialog ผ่านหน้าจอในเทสต์ไม่ได้)
class ActivityFormDialog extends StatefulWidget {
  final Activity? existing;
  final List<HourCategory> categories;
  const ActivityFormDialog({super.key, this.existing, required this.categories});

  @override
  State<ActivityFormDialog> createState() => _ActivityFormDialogState();
}

class _ActivityFormDialogState extends State<ActivityFormDialog> {
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

  /// error ของช่องวันเวลาโดยเฉพาะ (แสดงใต้ช่องนั้น ไม่ใช่กล่องรวมท้ายฟอร์ม)
  String? _dateError;

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
    final today = activityFirstSelectableDate();
    final date = await showDatePicker(
      context: context,
      // กิจกรรมเดิมที่จัดไปแล้วมี _startAt เป็นอดีต ซึ่งใช้เป็น initialDate ไม่ได้
      // (ต้องไม่ก่อน firstDate) จึงเริ่มที่วันนี้แทน — แก้ field อื่นได้ตามปกติ
      // แต่ถ้าจะแตะวัน ต้องเลือกวันนี้ขึ้นไปเท่านั้น
      initialDate: _startAt.isBefore(today) ? today : _startAt,
      firstDate: today,
      lastDate: DateTime(today.year + 3, today.month, today.day),
    );
    if (date == null || !mounted) return;
    // พิมพ์เวลาอย่างเดียวแบบ 24 ชม. — `inputOnly` ตัดทั้งหน้าปัดนาฬิกาที่ลากเข็มยาก
    // และปุ่มสลับไปหน้าปัด ส่วน AM/PM ตัดด้วย alwaysUse24HourFormat
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startAt),
      initialEntryMode: TimePickerEntryMode.inputOnly,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _startAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _dateError = null;
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
    // กิจกรรมเก่าที่จัดไปแล้วยังแก้ field อื่นได้ — ห้ามเฉพาะการ "ย้ายวัน" ไปอดีต
    // (เงื่อนไขเดียวกับที่ backend บังคับ ไม่งั้นสองฝั่งจะตัดสินไม่ตรงกัน)
    final startChanged = widget.existing == null || widget.existing!.startAt != _startAt;
    if (startChanged && isBackdatedActivity(_startAt)) {
      setState(() => _dateError = kBackdatedActivityMessage);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _dateError = null;
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
      final message = friendlyError(e);
      setState(() {
        if (isActivityDateError(message)) {
          _dateError = message;
          _error = null;
        } else {
          _error = message;
        }
      });
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
          decoration: InputDecoration(
            labelText: 'วันเวลาเริ่มกิจกรรม',
            // แสดงใต้ช่องนี้เลย ทั้งของที่ UI กันเองและ 400 ที่ backend ตอบกลับมา
            errorText: _dateError,
          ),
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
