import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/format.dart';
import 'student_hours_screen.dart';

/// Phase 12 — Executive dashboard (admin only). Reads the Gold-Layer
/// dashboard API and renders KPI cards, charts and drill-down tables.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

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
      setState(() => _error = e.toString());
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
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildFilters(),
                      const SizedBox(height: 16),
                      _buildKpiRow(),
                      const SizedBox(height: 16),
                      _buildCategoryChartCard(),
                      const SizedBox(height: 16),
                      _buildTrendChartCard(),
                      const SizedBox(height: 16),
                      _buildAtRiskCard(),
                      const SizedBox(height: 16),
                      _buildLowParticipationCard(),
                    ],
                  ),
                ),
    );
  }

  // --------------------------- filters ---------------------------
  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                initialValue: _faculty,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'คณะ', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('ทุกคณะ')),
                  ..._faculties.map((f) => DropdownMenuItem(value: f, child: Text(f))),
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
                decoration: const InputDecoration(labelText: 'ชั้นปี', border: OutlineInputBorder()),
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
                decoration: const InputDecoration(labelText: 'ภาคเรียน', border: OutlineInputBorder()),
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
      ),
    );
  }

  // --------------------------- KPI cards ---------------------------
  Widget _buildKpiRow() {
    final o = _overview;
    if (o == null) return const SizedBox.shrink();
    final cards = [
      _StatCard(
        icon: Icons.groups,
        label: 'นิสิตทั้งหมด',
        value: '${o.totalStudents}',
        color: Colors.blue,
      ),
      _StatCard(
        icon: Icons.verified,
        label: 'ผ่านเกณฑ์ (${formatHours(o.requiredHoursTotal)} ชม.)',
        value: '${formatHours(o.passedPercent)}%',
        sub: '${o.passedCount} คน',
        color: Colors.green,
      ),
      _StatCard(
        icon: Icons.timelapse,
        label: 'ชั่วโมงเฉลี่ย/คน',
        value: formatHours(o.avgHours),
        color: Colors.orange,
      ),
      _StatCard(
        icon: Icons.event_available,
        label: 'จำนวนกิจกรรม',
        value: '${o.activityCount}',
        color: Colors.purple,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final width = isWide ? (constraints.maxWidth - 3 * 12) / 4 : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((c) => SizedBox(width: width, child: c)).toList(),
        );
      },
    );
  }

  // --------------------------- category bar chart ---------------------------
  Widget _buildCategoryChartCard() {
    return _SectionCard(
      title: 'ชั่วโมงเฉลี่ยต่อหมวด (เฉลี่ย เทียบ เกณฑ์)',
      child: _byCategory.isEmpty
          ? const _EmptyHint()
          : Column(
              children: [
                SizedBox(height: 260, child: _buildCategoryBarChart()),
                const SizedBox(height: 12),
                _buildCategoryLegend(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    _LegendDot(color: Colors.teal, label: 'เฉลี่ยที่ได้'),
                    SizedBox(width: 16),
                    _LegendDot(color: Colors.grey, label: 'เกณฑ์'),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryBarChart() {
    final maxY = _byCategory
        .map((c) => c.requiredHours > c.avgEarnedHours ? c.requiredHours : c.avgEarnedHours)
        .fold<double>(0, (m, v) => v > m ? v : m);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxY == 0 ? 1 : maxY) * 1.2,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final c = _byCategory[group.x];
              final label = rodIndex == 0 ? 'เฉลี่ย' : 'เกณฑ์';
              return BarTooltipItem(
                '${c.categoryName}\n$label: ${formatHours(rod.toY)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 32),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${value.toInt() + 1}', style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < _byCategory.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 4,
              barRods: [
                BarChartRodData(toY: _byCategory[i].avgEarnedHours, color: Colors.teal, width: 10),
                BarChartRodData(toY: _byCategory[i].requiredHours, color: Colors.grey, width: 10),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _byCategory.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('${i + 1}. ${_byCategory[i].categoryName}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  // --------------------------- trend line chart ---------------------------
  Widget _buildTrendChartCard() {
    return _SectionCard(
      title: 'แนวโน้มการเข้าร่วม (อนุมัติแล้ว) รายเดือน',
      child: _trend.isEmpty
          ? const _EmptyHint()
          : SizedBox(height: 240, child: _buildTrendLineChart()),
    );
  }

  Widget _buildTrendLineChart() {
    final maxY = _trend.fold<double>(0, (m, p) => p.count > m ? p.count.toDouble() : m);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: (maxY == 0 ? 1 : maxY) * 1.2,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final p = _trend[s.x.toInt()];
              return LineTooltipItem(
                '${p.period}\n${p.count} ครั้ง',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 32),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= _trend.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_trend[i].period, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < _trend.length; i++)
                FlSpot(i.toDouble(), _trend[i].count.toDouble()),
            ],
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------- at-risk table ---------------------------
  Widget _buildAtRiskCard() {
    return _SectionCard(
      title: 'กลุ่มเสี่ยง (ชั่วโมงสะสม < 50% ของเกณฑ์)',
      child: _atRisk.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: Text('ไม่มีนิสิตกลุ่มเสี่ยงตามตัวกรองปัจจุบัน 🎉'),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('รหัสนิสิต')),
                  DataColumn(label: Text('ชื่อ')),
                  DataColumn(label: Text('คณะ')),
                  DataColumn(label: Text('ปี')),
                  DataColumn(label: Text('สะสม'), numeric: true),
                  DataColumn(label: Text('% เกณฑ์'), numeric: true),
                  DataColumn(label: Text('ขาดอีก'), numeric: true),
                ],
                rows: _atRisk.map((s) {
                  return DataRow(
                    color: WidgetStatePropertyAll(Colors.red.withValues(alpha: 0.06)),
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
                      DataCell(Text(formatHours(s.earnedHours))),
                      DataCell(Text('${formatHours(s.percent)}%',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                      DataCell(Text(formatHours(s.missingHours))),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }

  // --------------------------- low participation table ---------------------------
  Widget _buildLowParticipationCard() {
    return _SectionCard(
      title: 'กิจกรรมที่มีผู้เข้าร่วมน้อย',
      child: _lowParticipation.isEmpty
          ? const _EmptyHint()
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('กิจกรรม')),
                  DataColumn(label: Text('ประเภท')),
                  DataColumn(label: Text('เข้าร่วม'), numeric: true),
                  DataColumn(label: Text('รับสูงสุด'), numeric: true),
                  DataColumn(label: Text('% เต็ม'), numeric: true),
                ],
                rows: _lowParticipation.map((a) {
                  return DataRow(cells: [
                    DataCell(Text(a.name)),
                    DataCell(Text(a.activityType)),
                    DataCell(Text('${a.participantCount}')),
                    DataCell(Text('${a.maxParticipants}')),
                    DataCell(Text('${formatHours(a.fillPercent)}%')),
                  ]);
                }).toList(),
              ),
            ),
    );
  }
}

// --------------------------- small reusable widgets ---------------------------
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  if (sub != null)
                    Text(sub!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(8),
      child: Text('ยังไม่มีข้อมูลสำหรับตัวกรองนี้'),
    );
  }
}
