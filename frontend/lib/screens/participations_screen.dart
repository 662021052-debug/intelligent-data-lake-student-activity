import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/activity.dart';
import '../models/participation.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/evidence_status.dart';
import '../utils/format.dart';
import '../widgets/app_data_table.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/evidence_actions.dart';
import '../widgets/status_chip.dart';

const _evidenceStatuses = ['pending', 'approved', 'rejected'];

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

  @override
  void initState() {
    super.initState();
    _loadLookups().then((_) => _load());
  }

  Future<void> _loadLookups() async {
    try {
      final studentsPage =
          await ApiService.fetchPage('/students', Student.fromJson, query: {'limit': '200'});
      final activitiesPage =
          await ApiService.fetchPage('/activities', Activity.fromJson, query: {'limit': '200'});
      setState(() {
        _studentsById = {for (final s in studentsPage.items) s.id!: s};
        _activitiesById = {for (final a in activitiesPage.items) a.id!: a};
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, String>{'skip': '$_skip', 'limit': '$_limit'};
      if (_studentFilter != null) query['student_id'] = '$_studentFilter';
      if (_activityFilter != null) query['activity_id'] = '$_activityFilter';
      if (_statusFilter != null) query['evidence_status'] = _statusFilter!;
      final page =
          await ApiService.fetchPage('/participations', Participation.fromJson, query: query);
      setState(() {
        _participations = page.items;
        _total = page.total;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
    return Scaffold(
      appBar: AppBar(title: const Text('การเข้าร่วมกิจกรรม')),
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
                IconButton(
                  onPressed: _load,
                  tooltip: 'โหลดใหม่',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _participations.isEmpty
                        ? _emptyState(isStudent)
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return constraints.maxWidth > 800
                                  ? _buildTable(canWrite)
                                  : _buildList(canWrite);
                            },
                          ),
          ),
          if (_error == null && _participations.isNotEmpty) _buildPagination(),
        ],
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
    final filtered = _studentFilter != null || _activityFilter != null || _statusFilter != null;
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
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
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
