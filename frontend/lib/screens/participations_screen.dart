import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/activity.dart';
import '../models/participation.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/api_error.dart';
import '../utils/evidence_status.dart';
import '../utils/format.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/app_data_table.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/duplicate_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/evidence_actions.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/search_field.dart';
import '../widgets/status_chip.dart';
import 'app_shell.dart';

const _evidenceStatuses = ['pending', 'approved', 'rejected'];

/// query ของ `GET /participations` สำหรับหน้านี้
///
/// นิสิต: ขอให้รายการที่ยังต้องส่งหลักฐาน (pending/rejected — แถวที่มีปุ่มอัปโหลด) ขึ้นก่อน
/// ต้องให้ backend เรียงเพราะแบ่งหน้าที่นั่น เรียงในแอปจะได้แค่ภายในหน้าเดียว และไม่ใช้
/// ตัวกรอง "รอตรวจสอบ" เป็นค่าเริ่ม เพราะจะซ่อนใบที่ถูกปฏิเสธซึ่งต้องอัปโหลดใหม่เหมือนกัน
Map<String, String> participationListQuery({
  required bool isStudent,
  required int skip,
  required int limit,
  int? studentId,
  int? activityId,
  String? status,
  String search = '',
}) =>
    {
      'skip': '$skip',
      'limit': '$limit',
      if (isStudent) 'needs_evidence_first': 'true',
      if (studentId != null) 'student_id': '$studentId',
      if (activityId != null) 'activity_id': '$activityId',
      'evidence_status': ?status,
      if (search.isNotEmpty) 'search': search,
    };

class ParticipationsScreen extends StatefulWidget {
  const ParticipationsScreen({super.key});

  @override
  State<ParticipationsScreen> createState() => _ParticipationsScreenState();
}

class _ParticipationsScreenState extends State<ParticipationsScreen> {
  static const int _limit = 10;

  List<Participation> _participations = [];
  Map<int, Student> _studentsById = {};
  Map<int, Activity> _activitiesById = {};
  int _total = 0;
  int _skip = 0;
  bool _loading = false;
  String? _error;
  int? _studentFilter;
  int? _activityFilter;
  String? _statusFilter;
  String _search = '';
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadLookups().then((_) => _load());
  }

  void _onSearch(String value) {
    _search = value;
    _skip = 0;
    _load();
  }

  Future<void> _loadLookups() async {
    try {
      // ตารางนี้ต้องแปลง id → ชื่อของ "ทุก" แถวที่แสดง จึงต้องได้ข้อมูลครบทุกหน้า
      final students = await ApiService.fetchAll('/students', Student.fromJson);
      final activities = await ApiService.fetchAll('/activities', Activity.fromJson);
      setState(() {
        _studentsById = {for (final s in students) s.id!: s};
        _activitiesById = {for (final a in activities) a.id!: a};
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = participationListQuery(
        isStudent: authService.role == 'student',
        skip: _skip,
        limit: _limit,
        studentId: _studentFilter,
        activityId: _activityFilter,
        status: _statusFilter,
        search: _search,
      );
      final page =
          await ApiService.fetchPage('/participations', Participation.fromJson, query: query);
      // ผลลัพธ์เก่าที่มาช้ากว่าคำค้นหาล่าสุด ต้องไม่ทับของใหม่
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _participations = page.items;
        _total = page.total;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Participation? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ParticipationFormDialog(
        existing: existing,
        students: _studentsById.values.toList()..sort((a, b) => a.fullName.compareTo(b.fullName)),
        activities: _activitiesById.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
      ),
    );
    if (result == true) _load();
  }

  Future<void> _uploadEvidence(Participation p) async {
    if (p.id == null) return;
    final uploaded = await uploadEvidenceFlow(context, p.id!);
    if (uploaded) _load();
  }

  Future<void> _delete(Participation p) async {
    final label =
        '${_studentsById[p.studentId]?.fullName ?? p.studentId} - ${_activitiesById[p.activityId]?.name ?? p.activityId}';
    final confirmed = await confirmDelete(context, label);
    if (confirmed != true) return;
    try {
      await ApiService.delete('/participations/${p.id}');
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = authService.canWrite;
    final isStudent = authService.role == 'student';
    return AdminPage(
      activeId: 'participations',
      title: 'การเข้าร่วมกิจกรรม',
      subtitle: 'ทั้งหมด $_total รายการ',
      actions: [
        if (canWrite)
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('บันทึกการเข้าร่วม'),
          ),
      ],
      filters: [
        DebouncedSearchField(
                  label: 'ค้นหาชื่อ/รหัสนิสิต หรือกิจกรรม',
                  width: 280,
                  onSearch: _onSearch,
                ),
                // นิสิตที่ role student จะเห็นข้อมูลของตัวเองอยู่แล้ว (backend กรองให้)
                // จึงไม่ต้องมี dropdown ให้เลือกดูของนิสิตคนอื่น
                if (!isStudent)
                  DropdownButton<int?>(
                    value: _studentFilter,
                    hint: const Text('นิสิตทั้งหมด'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('นิสิตทั้งหมด')),
                      ..._studentsById.values
                          .map((s) => DropdownMenuItem(value: s.id, child: Text(s.fullName))),
                    ],
                    onChanged: (v) {
                      setState(() => _studentFilter = v);
                      _skip = 0;
                      _load();
                    },
                  ),
                DropdownButton<int?>(
                  value: _activityFilter,
                  hint: const Text('กิจกรรมทั้งหมด'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('กิจกรรมทั้งหมด')),
                    ..._activitiesById.values
                        .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))),
                  ],
                  onChanged: (v) {
                    setState(() => _activityFilter = v);
                    _skip = 0;
                    _load();
                  },
                ),
                DropdownButton<String?>(
                  value: _statusFilter,
                  hint: const Text('สถานะทั้งหมด'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('สถานะทั้งหมด')),
                    ..._evidenceStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(evidenceLabel(s)))),
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
      busy: _loading && _participations.isNotEmpty,
      footer: _error == null && _participations.isNotEmpty ? _buildPagination() : null,
      child: _loading && _participations.isEmpty
          ? const LoadingState(message: 'กำลังโหลดการเข้าร่วม...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _participations.isEmpty
                  ? _emptyState(isStudent)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return constraints.maxWidth > 800
                            ? TableCard(child: _buildTable(canWrite))
                            : _buildList(canWrite);
                      },
                    ),
    );
  }

  String _studentLabel(int id) => _studentsById[id]?.fullName ?? '#$id';

  // E1: prefer the name the API returns (works even for pending activities that
  // a student can't list), falling back to the lookup table then "#id".
  String _activityName(Participation p) =>
      p.activityName ?? _activitiesById[p.activityId]?.name ?? '#${p.activityId}';

  // E4: only approved participations have counted hours; others show "–".
  String _hoursDisplay(Participation p) =>
      p.evidenceStatus == 'approved' ? formatHours(p.hoursEarned) : '–';

  Widget _emptyState(bool isStudent) {
    final filtered = _search.isNotEmpty ||
        _studentFilter != null ||
        _activityFilter != null ||
        _statusFilter != null;
    if (filtered) return EmptyState.noResults();
    return EmptyState(
      icon: Icons.fact_check_outlined,
      title: 'ยังไม่มีรายการเข้าร่วม',
      message: isStudent
          ? 'เมื่อสมัครกิจกรรมแล้ว รายการจะแสดงที่นี่'
          : 'กดปุ่ม + มุมขวาล่างเพื่อบันทึกการเข้าร่วมรายการแรก',
    );
  }

  Widget _buildTable(bool canWrite) {
    final isStudent = authService.role == 'student';
    return AppDataTable(
      columns: const [
        DataColumn(label: Text('นิสิต')),
        DataColumn(label: Text('กิจกรรม')),
        DataColumn(label: Text('เช็คอิน')),
        DataColumn(label: Text('ชั่วโมงที่ได้'), numeric: true),
        DataColumn(label: Text('สถานะหลักฐาน')),
        DataColumn(label: Text('')),
      ],
      rows: [
        for (final p in _participations)
          [
            DataCell(Text(_studentLabel(p.studentId))),
            DataCell(Text(_activityName(p))),
            DataCell(Text(p.checkInTime == null ? '-' : p.checkInTime.toString())),
            DataCell(Text(_hoursDisplay(p))),
            DataCell(StatusChip.evidence(p.evidenceStatus, dense: true)),
            DataCell(canWrite
                ? _actionButtons(p)
                : isStudent
                    ? _studentActions(p)
                    : const SizedBox.shrink()),
          ],
      ],
    );
  }

  Widget _buildList(bool canWrite) {
    final isStudent = authService.role == 'student';
    return ListView.builder(
      itemCount: _participations.length,
      itemBuilder: (context, index) {
        final p = _participations[index];
        final evidenceNote =
            isStudent && p.evidenceStatus != 'approved' && !p.hasEvidence
                ? ' • ยังไม่ได้อัปโหลดหลักฐาน'
                : '';
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text('${_studentLabel(p.studentId)} → ${_activityName(p)}'),
            subtitle: Text(
              'ชั่วโมง: ${_hoursDisplay(p)} • ${evidenceLabel(p.evidenceStatus)}$evidenceNote',
            ),
            trailing: canWrite
                ? _actionButtons(p)
                : isStudent
                    ? _studentActions(p)
                    : null,
          ),
        );
      },
    );
  }

  Widget _actionButtons(Participation p) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: 'แก้ไข',
            onPressed: () => _openForm(existing: p),
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
            tooltip: 'ลบ',
            onPressed: () => _delete(p),
          ),
        ],
      );

  // Students can upload evidence while a participation is still pending, and view
  // whatever they have already uploaded.
  Widget _studentActions(Participation p) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.hasEvidence)
            IconButton(
              icon: const Icon(Icons.image_search, size: 20),
              tooltip: 'ดูหลักฐาน',
              onPressed: () => viewEvidenceFlow(context, p.id!),
            ),
          // B2: students can (re)upload while pending OR after a rejection
          if (p.evidenceStatus == 'pending' || p.evidenceStatus == 'rejected')
            IconButton(
              icon: const Icon(Icons.upload_file, size: 20),
              tooltip: p.hasEvidence ? 'อัปโหลดหลักฐานใหม่' : 'อัปโหลดหลักฐาน',
              onPressed: () => _uploadEvidence(p),
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

class _ParticipationFormDialog extends StatefulWidget {
  final Participation? existing;
  final List<Student> students;
  final List<Activity> activities;

  const _ParticipationFormDialog({
    this.existing,
    required this.students,
    required this.activities,
  });

  @override
  State<_ParticipationFormDialog> createState() => _ParticipationFormDialogState();
}

class _ParticipationFormDialogState extends State<_ParticipationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hoursController;
  int? _studentId;
  int? _activityId;
  String _evidenceStatus = 'pending';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _hoursController = TextEditingController(text: e != null ? formatHours(e.hoursEarned) : '0');
    _studentId = e?.studentId ?? (widget.students.isNotEmpty ? widget.students.first.id : null);
    _activityId = e?.activityId ?? (widget.activities.isNotEmpty ? widget.activities.first.id : null);
    _evidenceStatus = e?.evidenceStatus ?? 'pending';
  }

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_studentId == null || _activityId == null) {
      setState(() => _error = 'กรุณาเลือกนิสิตและกิจกรรม');
      return;
    }
    // เปลี่ยนใบที่ผล OCR เป็นไฟล์ซ้ำให้เป็น "อนุมัติ" ต้องรับรู้ก่อน (ทางเดียวกับหน้าตรวจหลักฐาน)
    final existing = widget.existing;
    if (existing != null &&
        existing.ocrDecision == 'flagged' &&
        existing.evidenceStatus != 'approved' &&
        _evidenceStatus == 'approved') {
      try {
        final ocr = await ApiService.fetchOcrResult(existing.id!);
        if (!mounted || !await confirmApproveIfDuplicate(context, ocr)) return;
      } catch (e) {
        setState(() => _error = friendlyError(e));
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final checkInTime = _evidenceStatus == 'pending' ? null : DateTime.now().toIso8601String();
    final body = {
      'student_id': _studentId,
      'activity_id': _activityId,
      'check_in_time': checkInTime,
      'hours_earned': int.parse(_hoursController.text.trim()),
      'evidence_status': _evidenceStatus,
    };
    try {
      if (widget.existing == null) {
        await ApiService.create('/participations', body, Participation.fromJson);
      } else {
        await ApiService.update(
            '/participations/${widget.existing!.id}', body, Participation.fromJson);
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
      title: widget.existing == null ? 'เพิ่มการเข้าร่วม' : 'แก้ไขการเข้าร่วม',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        DropdownButtonFormField<int>(
          initialValue: _studentId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'นิสิต'),
          items: widget.students
              .map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _studentId = v),
          validator: (v) => v == null ? 'กรุณาเลือกนิสิต' : null,
        ),
        DropdownButtonFormField<int>(
          initialValue: _activityId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'กิจกรรม'),
          items: widget.activities
              .map((a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _activityId = v),
          validator: (v) => v == null ? 'กรุณาเลือกกิจกรรม' : null,
        ),
        TextFormField(
          controller: _hoursController,
          decoration: const InputDecoration(labelText: 'ชั่วโมงที่ได้'),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) => int.tryParse(v ?? '') == null ? 'กรอกจำนวนเต็ม' : null,
        ),
        DropdownButtonFormField<String>(
          initialValue: _evidenceStatus,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'สถานะหลักฐาน'),
          items: _evidenceStatuses
              .map((s) => DropdownMenuItem(value: s, child: Text(evidenceLabel(s))))
              .toList(),
          onChanged: (v) => setState(() => _evidenceStatus = v ?? 'pending'),
        ),
      ],
    );
  }
}
