import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/chart_style.dart';
import '../utils/api_error.dart';
import '../utils/format.dart';
import '../widgets/app_data_table.dart';
import '../widgets/empty_state.dart';
import '../widgets/kpi_card.dart';
import 'student_hours_screen.dart';

/// Phase 12 — Executive dashboard (admin only). Reads the Gold-Layer
/// dashboard API and renders KPI cards, charts and drill-down tables.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  /// % ผ่านเกณฑ์คือตัวเลขที่ต้อง "เตือน" ได้: ต่ำกว่า 50% = แดง, ต่ำกว่า 80% = ส้ม
  static KpiTone passRateTone(double percent) {
    if (percent >= 80) return KpiTone.good;
    if (percent >= 50) return KpiTone.warning;
    return KpiTone.critical;
  }

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

const _semesterLabels = {1: 'ภาคต้น', 2: 'ภาคปลาย', 3: 'ภาคฤดูร้อน'};

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = false;
  String? _error;

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
      final page = await ApiService.fetchPage(
        '/students',
        Student.fromJson,
        query: {'limit': '200'},
      );
      final set = <String>{for (final s in page.items) s.faculty};
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
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!authService.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('แดชบอร์ดผู้บริหาร')),
        body: const Center(child: Text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('แดชบอร์ดผู้บริหาร'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'โหลดใหม่',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // โหลดครั้งแรก (ยังไม่มีอะไรให้ดู) ค่อยแสดงวงกลมหมุนเต็มหน้า
    if (_loading && _overview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final content = RefreshIndicator(
      onRefresh: _load,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
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
            ],
          ),
        ),
      ),
    );

    if (!_loading) return content;

    // เปลี่ยนตัวกรองแล้วโหลดใหม่: คงหน้าเดิมไว้แบบจาง ๆ + แถบโหลดด้านบน
    // ไม่ล้างหน้าเป็นสปินเนอร์ เพราะทำให้เลย์เอาต์กระโดดทุกครั้งที่กรอง
    return Stack(
      children: [
        IgnorePointer(child: Opacity(opacity: 0.45, child: content)),
        const Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(minHeight: 3),
        ),
      ],
    );
  }

  // --------------------------- filters ---------------------------

  /// สรุปตัวกรองที่ใช้อยู่เป็นข้อความสั้น ๆ ให้รู้ทันทีว่าตัวเลขบนหน้าคือของใคร
  String get _filterSummary {
    final parts = [
      _faculty ?? 'ทุกคณะ',
      _yearLevel == null ? 'ทุกชั้นปี' : 'ปี $_yearLevel',
      _semester == null ? 'ทุกภาคเรียน' : _semesterLabels[_semester]!,
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
                      ..._semesterLabels.entries
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
        icon: Icons.event_available_outlined,
        label: 'จำนวนกิจกรรม',
        value: '${o.activityCount}',
        sub: 'ที่เปิดในช่วงที่เลือก',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= 1000 => 4,
          >= 640 => 2,
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
                    ChartLegendKey(color: scheme.surfaceContainerHighest, label: 'เกณฑ์'),
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
                    color: scheme.surfaceContainerHighest,
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

  Widget _buildTrendLineChart() {
    final scheme = Theme.of(context).colorScheme;
    final maxY = _trend.fold<double>(0, (m, p) => p.count > m ? p.count.toDouble() : m);
    // แสดงป้ายเดือนเว้นระยะเมื่อจุดเยอะ ป้ายจะได้ไม่ทับกัน
    final labelStep = (_trend.length / 6).ceil().clamp(1, _trend.length);

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
                '${p.period}\n${p.count} ครั้ง',
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
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= _trend.length) return const SizedBox.shrink();
                if (i % labelStep != 0 && i != _trend.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(_trend[i].period, style: ChartStyle.axisLabel(context)),
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
                      // แถวกลุ่มเสี่ยงใช้พื้นแดงอ่อน และเข้มขึ้นเมื่อเมาส์ชี้
                      color: WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.hovered)
                              ? StatusPalette.rejected.background
                              : StatusPalette.rejected.background.withValues(alpha: 0.45)),
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
  Widget _percentOfTarget(double percent) {
    final theme = Theme.of(context);
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
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(StatusPalette.rejected.foreground),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '${formatHours(percent)}%',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: StatusPalette.rejected.foreground,
          ),
        ),
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
                    for (final (index, a) in _lowParticipation.indexed)
                      DataRow(
                        color: zebraRowColor(scheme, index),
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
                      Text(title, style: theme.textTheme.titleMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  for (final (index, row) in rows.indexed)
                    DataRow(
                      color: zebraRowColor(scheme, index),
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
