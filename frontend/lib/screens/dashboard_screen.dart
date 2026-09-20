import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/dashboard.dart';
import '../models/page.dart' as api;
import '../models/participation.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/chart_style.dart';
import '../utils/api_error.dart';
import '../utils/download_io.dart';
import '../utils/format.dart';
import '../utils/report_export.dart';
import '../widgets/admin_console.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_data_table.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/kpi_card.dart';
import '../widgets/status_chip.dart';
import 'activities_screen.dart';
import 'activity_calendar_screen.dart';
import 'app_shell.dart';
import 'evidence_review_screen.dart';
import 'hour_categories_screen.dart';
import 'participations_screen.dart';
import 'student_hours_screen.dart';
import 'students_screen.dart';
import 'users_screen.dart';

/// จุดที่ [index] ควรมีป้ายเดือนบนแกน X ของกราฟแนวโน้มหรือไม่
///
/// แยกเป็นฟังก์ชันบนสุดเพื่อให้เทสต์ยืนยันได้ว่าไม่มีเดือนไหนถูกวาดซ้ำและป้าย
/// ไม่ชิดกันเกินไป (หน้าจอเต็มต้องยิง API จริงจึงเทสต์ตรง ๆ ไม่ได้)
///
/// นับระยะจากจุดสุดท้ายย้อนกลับมา เดือนล่าสุดจึงมีป้ายเสมอ และช่วงห่างเท่ากันหมด
bool showsTrendLabel(int index, int pointCount) {
  if (pointCount <= 0 || index < 0 || index >= pointCount) return false;
  final step = (pointCount / 6).ceil().clamp(1, pointCount);
  return (pointCount - 1 - index) % step == 0;
}

/// แดชบอร์ดคอนโซลของผู้ดูแล — เป็น "หน้าแรก" ของ role admin ด้วย
///
/// อ่านตัวเลขทั้งหมดจาก Gold Layer (`/dashboard/*`) แล้ววาดปุ่มลัด แถบคู่มือ KPI
/// กราฟ ตารางกลุ่มเสี่ยง และการ์ดคิวงาน — แผงการ์ดเมนูเดิมของหน้าแรกถูกแทนด้วย
/// [ConsoleShortcutBar] ซึ่งต้องพาไปได้ครบทุกหน้าที่แผงนั้นเคยพาไป
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  /// ป้ายภาคเรียนที่ผู้ใช้เห็น — คีย์คือค่าที่ส่งให้ backend (`gold_dim_date.semester`)
  /// ซึ่งคำนวณจากเดือนของ `activity.start_at`: 1 = มิ.ย.–ต.ค., 2 = พ.ย.–มี.ค.,
  /// 3 = เม.ย.–พ.ค. เปลี่ยนได้เฉพาะข้อความ **ห้ามเปลี่ยนคีย์** ไม่งั้นแดชบอร์ดจะกรองผิดภาค
  static const Map<int, String> semesterLabels = {
    1: 'ภาคเรียนที่ 1',
    2: 'ภาคเรียนที่ 2',
    3: 'ภาคฤดูร้อน',
  };

  /// % ผ่านเกณฑ์คือตัวเลขที่ต้อง "เตือน" ได้: ต่ำกว่า 50% = แดง, ต่ำกว่า 80% = ส้ม
  static KpiTone passRateTone(double percent) {
    if (percent >= 80) return KpiTone.good;
    if (percent >= 50) return KpiTone.warning;
    return KpiTone.critical;
  }

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}


class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = false;
  String? _error;

  /// รูปแบบที่กำลังส่งออกอยู่ (null = ไม่ได้กำลังส่งออก) — กันกดซ้ำระหว่างรอไฟล์
  ReportFormat? _exporting;

  // filters
  String? _faculty;
  int? _yearLevel;
  int? _semester;
  List<String> _faculties = [];

  // data
  OverviewStats? _overview;
  List<CategoryStat> _byCategory = [];
  List<AtRiskStudent> _atRisk = [];
  List<LowParticipationActivity> _lowParticipation = [];
  List<TrendPoint> _trend = [];

  /// คิวงานของการ์ดสรุปสองใบ — มาจาก /activities และ /participations ไม่ใช่ Gold
  /// (ไม่มี endpoint แดชบอร์ดสำหรับงานค้าง และงานนี้ห้ามเพิ่มฝั่ง backend)
  ConsoleCounts _counts = const ConsoleCounts();

  /// เวลาที่โหลดตัวเลขชุดที่เห็นอยู่สำเร็จ — คอนโซลบอกไว้ว่าข้อมูลสดแค่ไหน
  DateTime? _loadedAt;

  bool _refreshingGold = false;

  @override
  void initState() {
    super.initState();
    _loadFaculties();
    _load();
  }

  Map<String, String> get _query {
    final q = <String, String>{};
    if (_faculty != null) q['faculty'] = _faculty!;
    if (_yearLevel != null) q['year_level'] = '$_yearLevel';
    if (_semester != null) q['semester'] = '$_semester';
    return q;
  }

  Future<void> _loadFaculties() async {
    try {
      // ต้องไล่ดูนิสิต "ทุกคน" ไม่ใช่แค่ 200 คนแรก ไม่งั้นคณะที่มีแต่นิสิตรหัสท้าย ๆ
      // จะหายไปจากตัวกรอง แล้วผู้ใช้กรองตามคณะนั้นไม่ได้เลย
      final students = await ApiService.fetchAll('/students', Student.fromJson);
      final set = <String>{for (final s in students) s.faculty};
      if (mounted) setState(() => _faculties = set.toList()..sort());
    } catch (_) {
      // faculty filter is optional; ignore load failure
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _query;
      final results = await Future.wait([
        ApiService.fetchObject('/dashboard/overview', OverviewStats.fromJson, query: q),
        ApiService.fetchList('/dashboard/by-category', CategoryStat.fromJson, query: q),
        ApiService.fetchList('/dashboard/at-risk', AtRiskStudent.fromJson, query: q),
        ApiService.fetchList('/dashboard/low-participation', LowParticipationActivity.fromJson,
            query: _semester != null ? {'semester': '$_semester'} : null),
        ApiService.fetchList('/dashboard/trend', TrendPoint.fromJson, query: q),
      ]);
      setState(() {
        _overview = results[0] as OverviewStats;
        _byCategory = results[1] as List<CategoryStat>;
        _atRisk = results[2] as List<AtRiskStudent>;
        _lowParticipation = results[3] as List<LowParticipationActivity>;
        _trend = results[4] as List<TrendPoint>;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _loadCounts();
  }

  /// คิวงานค้างของการ์ดสรุป — โหลดแยกจากตัวเลขหลัก
  ///
  /// ไม่ขึ้นกับตัวกรองคณะ/ชั้นปี/ภาคเรียน เพราะเป็น "งานที่ผู้ดูแลต้องทำ" ของทั้งระบบ
  /// และล้มแยกจากกันได้ — แดชบอร์ดพังทั้งหน้าเพราะนับงานค้างไม่ได้นั้นไม่คุ้ม
  Future<void> _loadCounts() async {
    try {
      final results = await Future.wait([
        ApiService.fetchAll('/activities', Activity.fromJson),
        ApiService.fetchPage(
          '/participations',
          Participation.fromJson,
          // นับเฉพาะที่ส่งไฟล์แล้ว — ตรงกับคิวในหน้าตรวจหลักฐานที่ todo นี้พาไป
          query: {'evidence_status': 'pending', 'has_evidence': 'true', 'limit': '1'},
        ),
      ]);
      final activities = results[0] as List<Activity>;
      final evidence = results[1] as api.Page<Participation>;
      final today = DateTime.now();

      if (!mounted) return;
      setState(() {
        _counts = ConsoleCounts(
          pendingActivities: activities.where((a) => a.approvalStatus == 'pending').length,
          pendingEvidence: evidence.total,
          approvedToday: activities.where((a) => _isSameDay(a.approvedAt, today)).length,
        );
      });
    } catch (_) {
      // คิวงานเป็นข้อมูลเสริม — โหลดไม่ได้ก็ปล่อยการ์ดเป็นศูนย์ไว้ ไม่ล้มทั้งหน้า
    }
  }

  static bool _isSameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  /// สร้างวิว gold_* ใหม่ (POST /gold/refresh) แล้วโหลดตัวเลขบนหน้าใหม่ทั้งหมด
  Future<void> _refreshGold() async {
    setState(() => _refreshingGold = true);
    try {
      await ApiService.create('/gold/refresh', const {}, (json) => json);
      if (mounted) showInfoSnackbar(context, 'รีเฟรช Gold Layer เรียบร้อย');
      await _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _refreshingGold = false);
    }
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  /// ดาวน์โหลดรายงานตามตัวกรองที่เลือกอยู่ (คณะ/ชั้นปี)
  Future<void> _export(ReportFormat format) async {
    setState(() => _exporting = format);
    try {
      final bytes = await ApiService.downloadBytes(
        format.path,
        query: reportQuery(faculty: _faculty, yearLevel: _yearLevel),
      );
      saveBytesAsFile(bytes, reportFileName(format), format.mediaType);
      if (mounted) showInfoSnackbar(context, 'ดาวน์โหลดไฟล์ ${format.displayName} เรียบร้อย');
    } catch (e) {
      if (mounted) showErrorSnackbar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!authService.isAdmin) {
      return const AppShell(
        activeId: 'dashboard',
        body: Center(child: Text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้')),
      );
    }

    return AdminPage(
      activeId: 'dashboard',
      title: 'Dashboard',
      subtitle: _headerSubtitle,
      actions: [
        ..._exportButtons(),
        AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: _load),
      ],
      // เปลี่ยนตัวกรองแล้วโหลดใหม่: คงหน้าเดิมไว้ + แถบบางด้านบน ไม่ล้างหน้าเป็น
      // สปินเนอร์ เพราะทำให้เลย์เอาต์กระโดดทุกครั้งที่กรอง
      busy: _loading && _overview != null,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        children: [
          // ปุ่มลัดกับคู่มือไม่ได้พึ่งข้อมูลแดชบอร์ด จึงอยู่นอกสถานะโหลด/ผิดพลาด —
          // แดชบอร์ดโหลดไม่ขึ้นแล้วผู้ดูแลต้องไปหน้าอื่นไม่ได้เลยคือทางตัน
          _buildShortcuts(),
          const SizedBox(height: AppSpacing.lg),
          GuideBanner(onOpen: () => showAdminGuide(context)),
          const SizedBox(height: AppSpacing.lg),
          ..._buildDataSections(),
        ],
      ),
    );
  }

  /// ส่วนที่ต้องมีข้อมูลจาก API ถึงจะวาดได้
  List<Widget> _buildDataSections() {
    // โหลดครั้งแรก (ยังไม่มีอะไรให้ดู) ค่อยแสดงสถานะกำลังโหลด
    if (_loading && _overview == null) {
      return const [LoadingState(message: 'กำลังโหลดแดชบอร์ด...')];
    }
    if (_error != null) return [ErrorState(message: _error!, onRetry: _load)];

    return [
      _buildFilters(),
      const SizedBox(height: AppSpacing.lg),
      _buildKpiRow(),
      const SizedBox(height: AppSpacing.lg),
      _buildCategoryChartCard(),
      const SizedBox(height: AppSpacing.lg),
      _buildTrendChartCard(),
      const SizedBox(height: AppSpacing.lg),
      _buildAtRiskCard(),
      const SizedBox(height: AppSpacing.lg),
      _buildLowParticipationCard(),
      const SizedBox(height: AppSpacing.lg),
      _buildQueueCards(),
    ];
  }

  // --------------------------- console header ---------------------------

  /// บรรทัดใต้หัวข้อตาม mockup + ตัวกรองที่ใช้อยู่ (mockup ไม่มีตัวกรอง แต่หน้าจริงมี
  /// จึงต้องบอกด้วยว่าตัวเลขที่เห็นเป็นของใคร)
  String get _headerSubtitle {
    final loaded = _loadedAt;
    final when = loaded == null ? 'กำลังโหลด...' : 'อัปเดต ${formatThaiDateTime(loaded)}';
    return 'ภาพรวมข้อมูลและงานที่ต้องดำเนินการทั้งระบบ · $_filterSummary · $when';
  }

  /// ปุ่มลัดแทนแผงการ์ดเมนูเดิมของหน้าแรก — สี่ปุ่มแรกเรียงตาม mockup
  ///
  /// ปฏิทินกิจกรรมกับการเข้าร่วมกิจกรรมไม่ได้อยู่บน mockup และไม่มีช่องบน sidebar
  /// ของแอดมิน แต่แผงการ์ดเดิมเป็นทางเข้าเดียวของสองหน้านี้ — ตัดออกแล้วจะกลายเป็น
  /// หน้ากำพร้าที่เข้าไม่ได้เลย จึงคงไว้ต่อท้าย
  Widget _buildShortcuts() => ConsoleShortcutBar(
        shortcuts: [
          ConsoleShortcut(
            icon: Icons.description_outlined,
            label: 'จัดการกิจกรรม',
            onTap: () => _open(const ActivitiesScreen()),
          ),
          ConsoleShortcut(
            icon: Icons.people_outline,
            label: 'จัดการผู้ใช้',
            onTap: () => _open(const UsersScreen()),
          ),
          ConsoleShortcut(
            icon: Icons.schedule_outlined,
            label: 'หมวดชั่วโมง',
            onTap: () => _open(const HourCategoriesScreen()),
          ),
          ConsoleShortcut(
            icon: Icons.sync,
            label: 'รีเฟรช Gold',
            onTap: _refreshGold,
            busy: _refreshingGold,
          ),
          ConsoleShortcut(
            icon: Icons.fact_check_outlined,
            label: 'การเข้าร่วมกิจกรรม',
            onTap: () => _open(const ParticipationsScreen()),
          ),
          ConsoleShortcut(
            icon: Icons.calendar_month_outlined,
            label: 'ปฏิทินกิจกรรม',
            onTap: () => _open(const ActivityCalendarScreen()),
          ),
        ],
      );

  // --------------------------- queue cards ---------------------------

  /// การ์ดคิวงานสองใบ — เรียงข้างกันบนจอกว้าง ซ้อนกันบนจอแคบ
  Widget _buildQueueCards() {
    final overview = StatusOverviewCard(counts: _counts);
    final todo = TodoCard(
      items: [
        TodoItem(
          label: 'อนุมัติ ${_counts.pendingActivities} กิจกรรมใหม่',
          count: _counts.pendingActivities,
          onTap: () => _open(const ActivitiesScreen()),
        ),
        TodoItem(
          label: 'ตรวจหลักฐาน ${_counts.pendingEvidence} รายการ',
          count: _counts.pendingEvidence,
          onTap: () => _open(const EvidenceReviewScreen()),
        ),
        TodoItem(
          label: 'ติดตามนิสิตกลุ่มเสี่ยง ${_atRisk.length} คน',
          count: _atRisk.length,
          onTap: () => _open(const StudentsScreen()),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [overview, const SizedBox(height: AppSpacing.lg), todo],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: overview),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: todo),
          ],
        );
      },
    );
  }

  // --------------------------- export ---------------------------

  /// ปุ่มส่งออกรายงาน — อยู่มุมขวาของหัวข้อหน้าเหมือนปุ่มหลักของหน้าจัดการอื่น ๆ
  ///
  /// ไฟล์ที่ได้ยึดตัวกรองคณะ/ชั้นปีที่เลือกอยู่ (รายงานเป็นชั่วโมง "สะสม" จึงไม่มี
  /// ภาคเรียนให้กรอง ต่างจากตัวเลขบนหน้าจอ) — บอกไว้ใน tooltip ของปุ่ม
  List<Widget> _exportButtons() => [
        for (final format in ReportFormat.values)
          Tooltip(
            message: 'รายงานชั่วโมงสะสมตามคณะ/ชั้นปีที่เลือก',
            child: OutlinedButton.icon(
              onPressed: _exporting != null ? null : () => _export(format),
              icon: _exporting == format
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(
                      format == ReportFormat.xlsx ? Icons.table_view : Icons.picture_as_pdf,
                      size: 16,
                    ),
              label: Text(format.label),
            ),
          ),
      ];

  // --------------------------- filters ---------------------------

  /// สรุปตัวกรองที่ใช้อยู่เป็นข้อความสั้น ๆ ให้รู้ทันทีว่าตัวเลขบนหน้าคือของใคร
  String get _filterSummary {
    final parts = [
      _faculty ?? 'ทุกคณะ',
      _yearLevel == null ? 'ทุกชั้นปี' : 'ปี $_yearLevel',
      _semester == null ? 'ทุกภาคเรียน' : DashboardScreen.semesterLabels[_semester]!,
    ];
    return parts.join(' • ');
  }

  Widget _buildFilters() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_alt_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('ตัวกรอง', style: theme.textTheme.titleSmall),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    _filterSummary,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _faculty,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'คณะ'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('ทุกคณะ')),
                      ..._faculties.map((f) => DropdownMenuItem(
                            value: f,
                            child: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() => _faculty = v);
                      _load();
                    },
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _yearLevel,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'ชั้นปี'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('ทุกชั้นปี')),
                      for (var y = 1; y <= 4; y++)
                        DropdownMenuItem(value: y, child: Text('ปี $y')),
                    ],
                    onChanged: (v) {
                      setState(() => _yearLevel = v);
                      _load();
                    },
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _semester,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'ภาคเรียน'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('ทุกภาคเรียน')),
                      ...DashboardScreen.semesterLabels.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                    ],
                    onChanged: (v) {
                      setState(() => _semester = v);
                      _load();
                    },
                  ),
                ),
                if (_faculty != null || _yearLevel != null || _semester != null)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _faculty = null;
                        _yearLevel = null;
                        _semester = null;
                      });
                      _load();
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('ล้างตัวกรอง'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------- KPI cards ---------------------------
  Widget _buildKpiRow() {
    final o = _overview;
    if (o == null) return const SizedBox.shrink();

    final avgProgress = o.requiredHoursTotal == 0 ? null : o.avgHours / o.requiredHoursTotal;
    final cards = [
      KpiCard(
        icon: Icons.verified_outlined,
        label: 'ผ่านเกณฑ์ (${formatHours(o.requiredHoursTotal)} ชม.)',
        value: '${formatHours(o.passedPercent)}%',
        sub: '${o.passedCount} จาก ${o.totalStudents} คน',
        tone: DashboardScreen.passRateTone(o.passedPercent),
        progress: o.passedPercent / 100,
        emphasized: true,
      ),
      KpiCard(
        icon: Icons.groups_outlined,
        label: 'นิสิตทั้งหมด',
        value: '${o.totalStudents}',
        sub: 'ตามตัวกรองปัจจุบัน',
      ),
      KpiCard(
        icon: Icons.timelapse,
        label: 'ชั่วโมงเฉลี่ย/คน',
        value: formatHours(o.avgHours),
        sub: 'จากเกณฑ์ ${formatHours(o.requiredHoursTotal)} ชม.',
        progress: avgProgress,
      ),
      KpiCard(
        icon: Icons.warning_amber_rounded,
        label: 'กลุ่มเสี่ยง',
        value: '${_atRisk.length}',
        sub: 'ชั่วโมงยังไม่ถึงครึ่งของเกณฑ์',
        tone: _atRisk.isEmpty ? KpiTone.good : KpiTone.warning,
      ),
      KpiCard(
        icon: Icons.event_available_outlined,
        label: 'จำนวนกิจกรรม',
        value: '${o.activityCount}',
        sub: 'ที่เปิดในช่วงที่เลือก',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= 1100 => 5,
          >= 860 => 3,
          >= 560 => 2,
          _ => 1,
        };
        final width =
            (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  // --------------------------- category bar chart ---------------------------

  /// แท่ง = ชั่วโมงเฉลี่ยที่นิสิตได้จริง, แถบจาง ๆ ด้านหลัง = เกณฑ์ของหมวดนั้น
  ///
  /// ใช้แถบพื้นหลังแทนการวางแท่ง "เกณฑ์" คู่กัน เพราะเกณฑ์คือ *เป้า* ไม่ใช่ชุดข้อมูล
  /// ที่มาแข่งกัน — อ่านง่ายกว่าและเหลือสีเดียวให้จำ
  Widget _buildCategoryChartCard() {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: 'ชั่วโมงเฉลี่ยต่อหมวด',
      subtitle: 'เทียบชั่วโมงเฉลี่ยที่นิสิตได้จริงกับเกณฑ์ของแต่ละหมวด',
      child: _byCategory.isEmpty
          ? const _EmptyHint()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 280, child: _buildCategoryBarChart()),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.sm,
                  children: [
                    ChartLegendKey(color: scheme.primary, label: 'เฉลี่ยที่ได้จริง'),
                    const ChartLegendKey(color: AppColors.blueBg, label: 'เกณฑ์'),
                  ],
                ),
                // ตัวเลขทุกตัวต้องอ่านได้โดยไม่ต้องเอาเมาส์ไปชี้กราฟ
                _ChartTableView(
                  columns: const ['หมวด', 'เฉลี่ยที่ได้', 'เกณฑ์', '% ของเกณฑ์'],
                  rows: [
                    for (final c in _byCategory)
                      [
                        c.categoryName,
                        '${formatHours(c.avgEarnedHours)} ชม.',
                        '${formatHours(c.requiredHours)} ชม.',
                        c.requiredHours == 0
                            ? '-'
                            : '${(c.avgEarnedHours / c.requiredHours * 100).round()}%',
                      ],
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryBarChart() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxY = _byCategory
        .map((c) => c.requiredHours > c.avgEarnedHours ? c.requiredHours : c.avgEarnedHours)
        .fold<double>(0, (m, v) => v > m ? v : m);
    final top = (maxY == 0 ? 1 : maxY) * 1.15;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: top,
        barTouchData: BarTouchData(
          touchTooltipData: ChartStyle.barTooltip(
            scheme,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final c = _byCategory[group.x];
              final percent = c.requiredHours == 0
                  ? 0
                  : (c.avgEarnedHours / c.requiredHours * 100).round();
              return BarTooltipItem(
                '${c.categoryName}\n'
                'เฉลี่ยที่ได้ ${formatHours(c.avgEarnedHours)} ชม.\n'
                'เกณฑ์ ${formatHours(c.requiredHours)} ชม. ($percent% ของเกณฑ์)',
                ChartStyle.tooltipText(scheme),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Text(
                  meta.formattedValue,
                  style: ChartStyle.axisLabel(context),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              // ชื่อหมวดจริงบนแกน (ตัดเหลือ 2 บรรทัด) แทนเลข 1..n ที่ต้องไปไล่หาในลิสต์
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= _byCategory.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _byCategory[i].categoryName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: ChartStyle.axisLabel(context),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: ChartStyle.grid(scheme),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < _byCategory.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _byCategory[i].avgEarnedHours,
                  color: scheme.primary,
                  width: ChartStyle.barWidth,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: _byCategory[i].requiredHours,
                    // ฟ้าอ่อนของธีม: เป็น "ค่าเดียวกันคนละสถานะ" ไม่ใช่ชุดข้อมูลใหม่
                    color: AppColors.blueBg,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // --------------------------- trend line chart ---------------------------
  Widget _buildTrendChartCard() {
    return _SectionCard(
      title: 'แนวโน้มการเข้าร่วมรายเดือน',
      subtitle: 'นับเฉพาะการเข้าร่วมที่หลักฐานได้รับการอนุมัติแล้ว',
      child: _trend.isEmpty
          ? const _EmptyHint()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 260, child: _buildTrendLineChart()),
                _ChartTableView(
                  columns: const ['เดือน', 'จำนวนครั้ง'],
                  rows: [
                    for (final p in _trend) [p.period, '${p.count}'],
                  ],
                ),
              ],
            ),
    );
  }

  /// ป้ายเดือนของกราฟแนวโน้ม — TrendPoint ส่งปี/เดือนมาเป็นตัวเลขอยู่แล้ว
  /// จึงไม่ต้องแกะจากสตริง `period` ("2025-08")
  String _trendLabel(TrendPoint p) => formatMonthLabel(DateTime(p.year, p.month));

  Widget _buildTrendLineChart() {
    final scheme = Theme.of(context).colorScheme;
    final maxY = _trend.fold<double>(0, (m, p) => p.count > m ? p.count.toDouble() : m);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: (maxY == 0 ? 1 : maxY) * 1.2,
        lineTouchData: LineTouchData(
          touchTooltipData: ChartStyle.lineTooltip(
            scheme,
            getTooltipItems: (spots) => spots.map((s) {
              final p = _trend[s.x.toInt()];
              return LineTooltipItem(
                '${_trendLabel(p)}\n${p.count} ครั้ง',
                ChartStyle.tooltipText(scheme),
              );
            }).toList(),
          ),
          getTouchedSpotIndicator: (barData, indexes) => indexes
              .map((_) => TouchedSpotIndicatorData(
                    FlLine(color: scheme.outline, strokeWidth: 1),
                    FlDotData(
                      getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                        radius: 5,
                        color: scheme.primary,
                        strokeWidth: 2,
                        strokeColor: scheme.surface,
                      ),
                    ),
                  ))
              .toList(),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                // จำนวนครั้งเป็นจำนวนเต็มเสมอ ไม่ต้องมีทศนิยมบนแกน
                if (value != value.roundToDouble()) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Text(
                    meta.formattedValue,
                    style: ChartStyle.axisLabel(context),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // ต้องล็อก interval = 1 (หนึ่งจุดข้อมูล) ไม่งั้น fl_chart เลือกระยะ
              // เป็นทศนิยมเอง เช่น 0.4/0.8/1.2 แล้ว value.toInt() ปัดลงมาชนกัน
              // เป็น index เดิม ป้ายเดือนเดียวกันจึงถูกวาดซ้ำหลายรอบทับกัน
              interval: 1,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (!showsTrendLabel(i, _trend.length)) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(_trendLabel(_trend[i]), style: ChartStyle.axisLabel(context)),
                );
              },
            ),
          ),
        ),
        gridData: ChartStyle.grid(scheme),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < _trend.length; i++)
                FlSpot(i.toDouble(), _trend[i].count.toDouble()),
            ],
            isCurved: true,
            curveSmoothness: 0.2,
            color: scheme.primary,
            barWidth: ChartStyle.lineWidth,
            dotData: FlDotData(
              // จุดมีวงแหวนสีพื้นหลัง จะได้ไม่จมไปกับเส้นตอนจุดชิดกัน
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 4,
                color: scheme.primary,
                strokeWidth: 2,
                strokeColor: scheme.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------- at-risk table ---------------------------
  Widget _buildAtRiskCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _SectionCard(
      title: 'กลุ่มเสี่ยง',
      subtitle: 'นิสิตที่ชั่วโมงสะสมยังไม่ถึง 50% ของเกณฑ์ — คลิกแถวเพื่อดูรายคน',
      trailing: _atRisk.isEmpty
          ? null
          : Text(
              '${_atRisk.length} คน',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: StatusPalette.rejected.foreground),
            ),
      child: _atRisk.isEmpty
          ? const EmptyState(
              icon: Icons.sentiment_satisfied_alt,
              title: 'ไม่มีนิสิตกลุ่มเสี่ยง',
              message: 'ทุกคนตามตัวกรองปัจจุบันมีชั่วโมงเกินครึ่งของเกณฑ์แล้ว',
            )
          : Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('รหัสนิสิต')),
                    DataColumn(label: Text('ชื่อ')),
                    DataColumn(label: Text('คณะ')),
                    DataColumn(label: Text('ปี'), numeric: true),
                    DataColumn(label: Text('สะสม'), numeric: true),
                    DataColumn(label: Text('% ของเกณฑ์'), numeric: true),
                    DataColumn(label: Text('ยังขาดอีก'), numeric: true),
                  ],
                  rows: _atRisk.map((s) {
                    return DataRow(
                      // แถวโปร่งเหมือนตารางอื่นของแอป — ความรุนแรงไปอยู่ที่ชิป %
                      // ของแต่ละคนแทน (พื้นแดงทั้งตารางทำให้แยกไม่ออกว่าใครหนักกว่า)
                      color: appRowColor(scheme),
                      onSelectChanged: (_) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StudentHoursScreen(
                            studentId: s.studentKey,
                            studentName: s.fullName,
                          ),
                        ),
                      ),
                      cells: [
                        DataCell(Text(s.studentCode)),
                        DataCell(Text(s.fullName)),
                        DataCell(Text(s.faculty)),
                        DataCell(Text('${s.yearLevel}')),
                        DataCell(Text('${formatHours(s.earnedHours)} ชม.')),
                        DataCell(_percentOfTarget(s.percent)),
                        DataCell(Text(
                          '${formatHours(s.missingHours)} ชม.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }

  /// % ของเกณฑ์ + แถบสั้น ๆ ให้เห็นความห่างจากเป้าโดยไม่ต้องอ่านตัวเลข
  ///
  /// ต่ำกว่า 25% = แดง (เร่งด่วน) ส่วน 25–50% = เหลือง — ทั้งกลุ่มยังไม่ถึงเกณฑ์
  /// เหมือนกัน แต่คนที่เกือบไม่มีชั่วโมงเลยต้องเด้งออกมาก่อน
  static StatusPalette atRiskPalette(double percent) =>
      percent < 25 ? StatusPalette.rejected : StatusPalette.pending;

  Widget _percentOfTarget(double percent) {
    final palette = atRiskPalette(percent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.page,
              valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        StatusChip(label: '${formatHours(percent)}%', palette: palette, dense: true),
      ],
    );
  }

  // --------------------------- low participation table ---------------------------
  Widget _buildLowParticipationCard() {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: 'กิจกรรมที่มีผู้เข้าร่วมน้อย',
      subtitle: 'ใช้ดูว่าควรประชาสัมพันธ์เพิ่มหรือปรับจำนวนที่รับ',
      child: _lowParticipation.isEmpty
          ? const _EmptyHint()
          : Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('กิจกรรม')),
                    DataColumn(label: Text('ประเภท')),
                    DataColumn(label: Text('เข้าร่วม'), numeric: true),
                    DataColumn(label: Text('รับสูงสุด'), numeric: true),
                    DataColumn(label: Text('% เต็ม'), numeric: true),
                  ],
                  rows: [
                    for (final a in _lowParticipation)
                      DataRow(
                        color: appRowColor(scheme),
                        cells: [
                          DataCell(Text(a.name)),
                          DataCell(Text(a.activityType)),
                          DataCell(Text('${a.participantCount}')),
                          DataCell(Text('${a.maxParticipants}')),
                          DataCell(Text('${formatHours(a.fillPercent)}%')),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

// --------------------------- small reusable widgets ---------------------------

/// การ์ดหนึ่งส่วนของแดชบอร์ด: หัวข้อ + คำอธิบายสั้น (+ ตัวเลขมุมขวา) + เนื้อหา
class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium?.copyWith(fontSize: 16)),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        ),
      ),
    );
  }
}

/// ตารางคู่กับกราฟ (พับเก็บไว้) — ให้อ่านตัวเลขได้ทุกตัวโดยไม่ต้องใช้เมาส์ชี้
class _ChartTableView extends StatelessWidget {
  const _ChartTableView({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      // ตัดเส้นคั่นของ ExpansionTile ออก ให้กลืนไปกับการ์ด
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text('ดูเป็นตาราง', style: Theme.of(context).textTheme.labelLarge),
        children: [
          Scrollbar(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [for (final c in columns) DataColumn(label: Text(c))],
                rows: [
                  for (final row in rows)
                    DataRow(
                      color: appRowColor(scheme),
                      cells: [for (final cell in row) DataCell(Text(cell))],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.insights_outlined,
      title: 'ยังไม่มีข้อมูลสำหรับตัวกรองนี้',
      message: 'ลองล้างตัวกรอง หรือเลือกภาคเรียนอื่นดู',
    );
  }
}
