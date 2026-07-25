import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/participation.dart';
import '../services/api_service.dart';
import '../utils/evidence_status.dart';
import '../widgets/dialogs.dart';

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}

String _trimHours(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toString();

class RegisterActivitiesScreen extends StatefulWidget {
  const RegisterActivitiesScreen({super.key});

  @override
  State<RegisterActivitiesScreen> createState() => _RegisterActivitiesScreenState();
}

class _RegisterActivitiesScreenState extends State<RegisterActivitiesScreen> {
  List<Activity> _activities = [];
  Map<int, Participation> _ownParticipationByActivity = {};
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
      final activitiesPage =
          await ApiService.fetchPage('/activities', Activity.fromJson, query: {'limit': '200'});
      final participationsPage = await ApiService.fetchPage(
        '/participations',
        Participation.fromJson,
        query: {'limit': '200'},
      );
      setState(() {
        _activities = activitiesPage.items..sort((a, b) => a.startAt.compareTo(b.startAt));
        _ownParticipationByActivity = {
          for (final p in participationsPage.items) p.activityId: p,
        };
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register(Activity a) async {
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการสมัคร',
      message: 'สมัครเข้าร่วม "${a.name}" ?\n'
          'จะได้รับ ${_trimHours(a.hours)} ชั่วโมงเมื่อหลักฐานผ่านการอนุมัติ',
      confirmLabel: 'สมัคร',
    );
    if (confirmed != true) return;
    try {
      await ApiService.create(
        '/participations/register',
        {'activity_id': a.id},
        Participation.fromJson,
      );
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  Future<void> _cancel(Participation p, Activity a) async {
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการยกเลิก',
      message: 'ยกเลิกการสมัคร "${a.name}" ?',
      confirmLabel: 'ยกเลิกการสมัคร',
      confirmColor: Colors.red,
    );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('กิจกรรมที่เปิดรับสมัคร'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _activities.isEmpty
                  ? const Center(child: Text('ยังไม่มีกิจกรรมที่เปิดรับสมัคร'))
                  : ListView.builder(
                      itemCount: _activities.length,
                      itemBuilder: (context, index) {
                        final a = _activities[index];
                        final participation = _ownParticipationByActivity[a.id];
                        final closed = a.startAt.isBefore(DateTime.now());
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ListTile(
                            title: Text(a.name),
                            subtitle: Text(
                              '${a.activityType} • ได้ ${_trimHours(a.hours)} ชม. • ${_formatDateTime(a.startAt)}\n'
                              '${a.location} • รับ ${a.participantCount}/${a.maxParticipants} คน',
                            ),
                            isThreeLine: true,
                            trailing: _buildTrailing(a, participation, closed),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildTrailing(Activity a, Participation? participation, bool closed) {
    if (participation != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(
            label: Text(evidenceLabel(participation.evidenceStatus)),
            backgroundColor: evidenceColor(participation.evidenceStatus),
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red),
            tooltip: 'ยกเลิกการสมัคร',
            onPressed: () => _cancel(participation, a),
          ),
        ],
      );
    }
    if (a.isFull) {
      return const Chip(label: Text('เต็มแล้ว'));
    }
    if (closed) {
      return const Chip(label: Text('ปิดรับสมัครแล้ว'));
    }
    return FilledButton(onPressed: () => _register(a), child: const Text('สมัคร'));
  }
}
