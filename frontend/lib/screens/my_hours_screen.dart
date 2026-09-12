import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/hour_summary.dart';
import '../models/participation.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/chart_style.dart';
import '../utils/api_error.dart';
import '../utils/format.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/hour_summary_view.dart';
import '../widgets/kpi_card.dart';
import '../widgets/participation_history.dart';
import 'app_shell.dart';
import 'chatbot_screen.dart';
import 'register_activities_screen.dart';

/// แดชบอร์ดชั่วโมงของนิสิต (คนละอันกับแดชบอร์ดผู้บริหารที่เป็นภาพรวมทั้งมหาวิทยาลัย)
///
/// ยกระดับจากหน้า "ชั่วโมงสะสมของฉัน" เดิม: เพิ่ม KPI รวม กราฟเทียบเกณฑ์รายหมวด
/// และปุ่มลัดไปหาสิ่งที่ต้องทำต่อ โดยยังใช้ข้อมูลชุดเดิมจาก
/// `GET /students/me/hours-summary` (ไม่แตะ logic/permission ฝั่ง backend)
class MyHoursScreen extends StatefulWidget {
  const MyHoursScreen({super.key});

  @override
  State<MyHoursScreen> createState() => _MyHoursScreenState();
}

class _MyHoursScreenState extends State<MyHoursScreen> {
  List<HourCategorySummary> _categories = [];

  /// ประวัติการเข้าร่วม — ย้ายมาจากหน้าแรกของนิสิตตอนที่หน้าแรกกลายเป็นแดชบอร์ด
  List<Participation> _participations = [];
  Map<int, Activity> _activityById = {};

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
      final categories = await ApiService.fetchList(
        '/students/me/hours-summary',
        HourCategorySummary.fromJson,
      );
      setState(() => _categories = categories);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _loadHistory();
  }

  /// ประวัติการเข้าร่วมเป็นข้อมูลเสริมของหน้านี้ — โหลดไม่ได้ก็ยังดูชั่วโมงได้
  Future<void> _loadHistory() async {
    try {
      final participations =
          await ApiService.fetchAll('/participations', Participation.fromJson);
      final activities = await ApiService.fetchAll('/activities', Activity.fromJson);
      final byId = {
        for (final a in activities)
          if (a.id != null) a.id!: a,
      };
      sortParticipationsByRecent(participations, byId);
      if (!mounted) return;
      setState(() {
        _participations = participations;
        _activityById = byId;
      });
    } catch (_) {
      // ไม่ล้มทั้งหน้าเพราะโหลดประวัติไม่ได้
    }
  }

  double get _totalRequired =>
      _categories.fold<double>(0, (sum, c) => sum + c.requiredHours);

  /// ชั่วโมงที่นับได้จริง — เกินเกณฑ์ของหมวดไหนก็ไม่เอาส่วนเกินมาถัวหมวดอื่น
  double get _totalEarned => _categories.fold<double>(
        0,
        (sum, c) => sum + (c.earnedHours > c.requiredHours ? c.requiredHours : c.earnedHours),
      );

  int get _completedCount => _categories.where((c) => c.completed).length;

  double get _remaining {
    final left = _totalRequired - _totalEarned;
    return left > 0 ? left : 0;
  }

  /// หมวดที่ยังไม่ครบ เรียงจากที่ขาดมากที่สุด — ใช้เป็นคำแนะนำว่าควรไปทำอะไรก่อน
  List<HourCategorySummary> get _incomplete {
    final list = _categories.where((c) => !c.completed).toList();
    list.sort((a, b) =>
        (b.requiredHours - b.earnedHours).compareTo(a.requiredHours - a.earnedHours));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeId: 'my_hours',
      body: _loading
          ? const LoadingState(message: 'กำลังโหลดชั่วโมงของคุณ...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _categories.isEmpty
                  ? const EmptyState(
                      icon: Icons.timelapse,
                      title: 'ยังไม่มีข้อมูลชั่วโมง',
                      message: 'เมื่อหลักฐานการเข้าร่วมได้รับการอนุมัติ ชั่วโมงจะแสดงที่นี่',
                    )
                  : _buildDashboard(),
    );
  }

  Widget _buildDashboard() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionHeader(
          title: 'รายละเอียดชั่วโมง',
          subtitle: 'ชั่วโมงสะสมของคุณเทียบเกณฑ์ที่ต้องเก็บ',
          actions: [
            AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: _load),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildKpiRow(),
        const SizedBox(height: AppSpacing.lg),
        _buildNextStepCard(),
        const SizedBox(height: AppSpacing.lg),
        _buildChartCard(),
        const SizedBox(height: AppSpacing.lg),
        Text('รายละเอียดแต่ละหมวด', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        HourSummaryView(categories: _categories, embedded: true),
        const SizedBox(height: AppSpacing.lg),
        ParticipationHistoryCard(
          participations: _participations,
          activityById: _activityById,
          onReload: _load,
        ),
      ],
    );
  }

  Widget _buildKpiRow() {
    final progress = _totalRequired == 0 ? 0.0 : _totalEarned / _totalRequired;
    final done = _remaining == 0;
    final cards = [
      KpiCard(
        icon: Icons.timelapse,
        label: 'ชั่วโมงสะสม',
        value: '${formatHours(_totalEarned)}/${formatHours(_totalRequired)}',
        sub: '${(progress * 100).round()}% ของเกณฑ์ทั้งหมด',
        tone: done ? KpiTone.good : KpiTone.neutral,
        progress: progress,
        emphasized: true,
      ),
      KpiCard(
        icon: Icons.checklist,
        label: 'หมวดที่ผ่านแล้ว',
        value: '$_completedCount/${_categories.length}',
        sub: done ? 'ครบทุกหมวดแล้ว' : 'ยังไม่ครบ ${_categories.length - _completedCount} หมวด',
        tone: done ? KpiTone.good : KpiTone.neutral,
      ),
      KpiCard(
        icon: Icons.pending_actions,
        label: 'ยังขาดอีก',
        value: '${formatHours(_remaining)} ชม.',
        sub: done ? 'ไม่ต้องเก็บเพิ่มแล้ว' : 'รวมทุกหมวดที่ยังไม่ครบ',
        tone: done ? KpiTone.good : KpiTone.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= 900 => 3,
          >= 600 => 2,
          _ => 1,
        };
        final width = (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [for (final card in cards) SizedBox(width: width, child: card)],
        );
      },
    );
  }

  /// บอกตรง ๆ ว่าควรทำอะไรต่อ พร้อมปุ่มลัดไปทำจริง
  Widget _buildNextStepCard() {
    final theme = Theme.of(context);
    final incomplete = _incomplete;
    final message = incomplete.isEmpty
        ? 'เก็บชั่วโมงครบทุกหมวดแล้ว 🎉'
        : 'หมวดที่ยังขาดมากที่สุดคือ "${incomplete.first.name}" '
            '(ขาดอีก ${formatHours(incomplete.first.requiredHours - incomplete.first.earnedHours)} ชม.)';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ก้าวต่อไป', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: _askChatbotForRecommendations,
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: const Text('แนะนำกิจกรรมที่ยังขาด'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterActivitiesScreen()),
                  ),
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('ดูกิจกรรมที่เปิดรับสมัคร'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _askChatbotForRecommendations() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ChatbotScreen(initialQuestion: 'แนะนำกิจกรรมที่ยังขาดให้หน่อย'),
      ),
    );
    // กลับมาแล้วอาจเพิ่งสมัครกิจกรรมใหม่ — โหลดตัวเลขใหม่ให้ตรง
    if (mounted) _load();
  }

  // --------------------------- กราฟเทียบเกณฑ์รายหมวด ---------------------------

  /// แท่ง = ชั่วโมงที่ได้จริง, แถบจางด้านหลัง = เกณฑ์ของหมวดนั้น
  /// (ใช้แบบเดียวกับแดชบอร์ดผู้บริหาร เพื่อให้กราฟทั้งแอปอ่านเหมือนกัน)
  Widget _buildChartCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ชั่วโมงที่ได้เทียบเกณฑ์ รายหมวด', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            SizedBox(height: 260, child: _buildBarChart()),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.sm,
              children: [
                ChartLegendKey(color: scheme.primary, label: 'ชั่วโมงที่ได้'),
                const ChartLegendKey(color: AppColors.page, label: 'เกณฑ์'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    final scheme = Theme.of(context).colorScheme;
    final maxY = _categories
        .map((c) => c.requiredHours > c.earnedHours ? c.requiredHours : c.earnedHours)
        .fold<double>(0, (m, v) => v > m ? v : m);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxY == 0 ? 1 : maxY) * 1.15,
        barTouchData: BarTouchData(
          touchTooltipData: ChartStyle.barTooltip(
            scheme,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final c = _categories[group.x];
              return BarTooltipItem(
                '${c.name}\n'
                'ได้ ${formatHours(c.earnedHours)} ชม.\n'
                'เกณฑ์ ${formatHours(c.requiredHours)} ชม.'
                '${c.completed ? ' (ครบแล้ว)' : ''}',
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
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= _categories.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _categories[i].name,
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
          for (var i = 0; i < _categories.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _categories[i].earnedHours,
                  // หมวดที่ครบแล้วใช้สีเดียวกับเครื่องหมายติ๊กในรายการด้านล่าง
                  color: _categories[i].completed ? StatusPalette.approved.accent : scheme.primary,
                  width: ChartStyle.barWidth,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: _categories[i].requiredHours,
                    color: AppColors.page,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
