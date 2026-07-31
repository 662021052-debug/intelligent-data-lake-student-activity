import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/participation.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';

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
      // นิสิตต้องเห็นกิจกรรมที่เปิดรับ "ทั้งหมด" และรู้ว่าตัวเองสมัครอันไหนไปแล้ว
      final activities = await ApiService.fetchAll('/activities', Activity.fromJson);
      final participations = await ApiService.fetchAll('/participations', Participation.fromJson);
      setState(() {
        _activities = activities..sort((a, b) => a.startAt.compareTo(b.startAt));
        _ownParticipationByActivity = {
          for (final p in participations) p.activityId: p,
        };
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register(Activity a) async {
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการสมัคร',
      message: 'สมัครเข้าร่วม "${a.name}"\n'
          'วันเวลา ${_formatDateTime(a.startAt)} • ${a.location}',
      detail: 'จะได้รับ ${_trimHours(a.hours)} ชั่วโมง เมื่อหลักฐานผ่านการอนุมัติ',
      confirmLabel: 'สมัคร',
      icon: Icons.how_to_reg,
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
      message: 'ยกเลิกการสมัคร "${a.name}"',
      detail: 'รายการนี้จะถูกลบออกจากประวัติการเข้าร่วม ถ้าเปลี่ยนใจต้องสมัครใหม่',
      confirmLabel: 'ยกเลิกการสมัคร',
      icon: Icons.cancel_outlined,
      destructive: true,
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
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'โหลดใหม่',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _activities.isEmpty
                  ? const EmptyState(
                      icon: Icons.event_available_outlined,
                      title: 'ยังไม่มีกิจกรรมที่เปิดรับสมัคร',
                      message: 'ลองกลับมาดูใหม่ภายหลัง หรือกดโหลดใหม่มุมขวาบน',
                    )
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
          StatusChip.evidence(participation.evidenceStatus, dense: true),
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red),
            tooltip: 'ยกเลิกการสมัคร',
            onPressed: () => _cancel(participation, a),
          ),
        ],
      );
    }
    if (a.isFull) {
      return const StatusChip(
        label: 'เต็มแล้ว',
        palette: StatusPalette.neutral,
        icon: Icons.group_off_outlined,
        dense: true,
      );
    }
    if (closed) {
      return const StatusChip(
        label: 'ปิดรับสมัครแล้ว',
        palette: StatusPalette.neutral,
        icon: Icons.lock_clock,
        dense: true,
      );
    }
    return FilledButton(onPressed: () => _register(a), child: const Text('สมัคร'));
  }
}
