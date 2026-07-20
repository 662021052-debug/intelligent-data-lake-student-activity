import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/participation.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../utils/evidence_status.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';

class ActivityParticipantsScreen extends StatefulWidget {
  final Activity activity;
  const ActivityParticipantsScreen({super.key, required this.activity});

  @override
  State<ActivityParticipantsScreen> createState() => _ActivityParticipantsScreenState();
}

class _ActivityParticipantsScreenState extends State<ActivityParticipantsScreen> {
  List<Participation> _participations = [];
  Map<int, Student> _studentsById = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final studentsPage =
          await ApiService.fetchPage('/students', Student.fromJson, query: {'limit': '200'});
      final participations = await ApiService.fetchList(
        '/activities/${widget.activity.id}/participations',
        Participation.fromJson,
      );
      setState(() {
        _studentsById = {for (final s in studentsPage.items) s.id!: s};
        _participations = participations;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEvidence(Participation p, String status) async {
    try {
      await ApiService.update(
        '/participations/${p.id}',
        {'evidence_status': status},
        Participation.fromJson,
      );
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  String _studentLabel(int studentId) => _studentsById[studentId]?.fullName ?? '#$studentId';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ผู้เข้าร่วม: ${widget.activity.name}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _participations.isEmpty
                  ? const Center(child: Text('ยังไม่มีผู้เข้าร่วม'))
                  : ListView.builder(
                      itemCount: _participations.length,
                      itemBuilder: (context, index) {
                        final p = _participations[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ListTile(
                            title: Text(_studentLabel(p.studentId)),
                            subtitle: Text(
                              'เช็คอิน: ${p.checkInTime?.toString() ?? "-"} • ชั่วโมง: ${formatHours(p.hoursEarned)}',
                            ),
                            isThreeLine: false,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(
                                  label: Text(evidenceLabel(p.evidenceStatus)),
                                  backgroundColor: evidenceColor(p.evidenceStatus),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.check_circle, color: Colors.green),
                                  tooltip: 'อนุมัติ',
                                  onPressed: () => _setEvidence(p, 'approved'),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.red),
                                  tooltip: 'ไม่อนุมัติ',
                                  onPressed: () => _setEvidence(p, 'rejected'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
