import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/hour_category.dart';
import '../models/hour_summary.dart';
import '../models/participation.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/search_field.dart';
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
  List<HourCategory> _categories = [];
  List<HourCategorySummary> _myHours = [];
  Map<int, Participation> _ownParticipationByActivity = {};
  bool _loading = false;
  String? _error;
  String _search = '';

  /// กิจกรรมที่ผ่านช่องค้นหา — กรองในเครื่องเพราะโหลดรายการมาครบแล้ว
  List<Activity> get _visible {
    if (_search.isEmpty) return _activities;
    final needle = _search.toLowerCase();
    return _activities.where((a) {
      final haystack = '${a.name} ${a.activityType} ${a.location} '
              '${subcategoryPath(_categories, a.subcategoryId)}'
          .toLowerCase();
      return haystack.contains(needle);
    }).toList();
  }

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
      // ชื่อหมวดชั่วโมง + ชั่วโมงสะสมของตัวเอง ใช้บอกว่า "สมัครแล้วได้อะไร เข้าหมวดที่ยังขาดไหม"
      final categories = await ApiService.fetchList('/hour-categories', HourCategory.fromJson);
      final myHours = await ApiService.fetchList(
        '/students/me/hours-summary',
        HourCategorySummary.fromJson,
      );
      setState(() {
        _activities = activities..sort((a, b) => a.startAt.compareTo(b.startAt));
        _categories = categories;
        _myHours = myHours;
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

  /// สรุปสถานะหมวดของกิจกรรมนี้เทียบกับชั่วโมงที่นิสิตมีอยู่ (null ถ้าไม่รู้จักหมวด)
  String? _categoryProgress(Activity a) {
    final parent = parentCategoryOf(_categories, a.subcategoryId);
    if (parent == null) return null;
    for (final summary in _myHours) {
      if (summary.id != parent.id) continue;
      if (summary.completed) {
        return 'หมวดนี้คุณครบแล้ว (${_trimHours(summary.earnedHours)}/'
            '${_trimHours(summary.requiredHours)} ชม.)';
      }
      final remaining = summary.requiredHours - summary.earnedHours;
      return 'หมวดนี้คุณมี ${_trimHours(summary.earnedHours)}/'
          '${_trimHours(summary.requiredHours)} ชม. — ยังขาดอีก ${_trimHours(remaining)} ชม.';
    }
    return null;
  }

  Future<void> _register(Activity a) async {
    final categoryPath = subcategoryPath(_categories, a.subcategoryId);
    final progress = _categoryProgress(a);
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการสมัคร',
      message: 'สมัครเข้าร่วม "${a.name}"\n'
          'วันเวลา ${_formatDateTime(a.startAt)} • ${a.location}\n\n'
          'ได้ ${_trimHours(a.hours)} ชั่วโมง\n'
          'เข้าหมวด $categoryPath',
      detail: [
        'ชั่วโมงจะถูกนับเมื่อหลักฐานผ่านการอนุมัติ',
        ?progress,
      ].join('\n'),
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
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: DebouncedSearchField(
                          label: 'ค้นหากิจกรรม/หมวด/สถานที่',
                          onSearch: (value) => setState(() => _search = value),
                        ),
                      ),
                      if (_visible.isEmpty)
                        Expanded(child: EmptyState.noResults())
                      else
                      Expanded(
                        child: ListView.builder(
                      itemCount: _visible.length,
                      itemBuilder: (context, index) {
                        final a = _visible[index];
                        final participation = _ownParticipationByActivity[a.id];
                        final closed = a.startAt.isBefore(DateTime.now());
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ListTile(
                            title: Text(a.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${a.activityType} • ${_formatDateTime(a.startAt)}'),
                                Text('${a.location} • รับ ${a.participantCount}/'
                                    '${a.maxParticipants} คน'),
                                // นิสิตต้องรู้ก่อนกดสมัครว่าได้กี่ชั่วโมงและเข้าหมวดไหน
                                _buildHoursAndCategory(a),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: _buildTrailing(a, participation, closed),
                          ),
                        );
                      },
                        ),
                      ),
                    ]),
    );
  }

  /// บรรทัด "ได้ X ชม. • หมวด › หมวดย่อย" — เน้นสีให้อ่านง่ายกว่าข้อความรายละเอียดอื่น
  Widget _buildHoursAndCategory(Activity a) {
    final theme = Theme.of(context);
    final path = subcategoryPath(_categories, a.subcategoryId);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'ได้ ${_trimHours(a.hours)} ชม. • $path',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
