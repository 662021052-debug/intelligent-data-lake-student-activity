import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/hour_summary.dart';
import '../models/participation.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_buttons.dart';
import 'app_card.dart';
import 'empty_state.dart';

/// ชิ้นส่วนของแดชบอร์ดส่วนตัวของนิสิต (mockup หน้า 2)
///
/// แยกจากหน้าจอเพราะรับข้อมูลทางพารามิเตอร์ล้วน ๆ ไม่ยิง API เอง — เทสต์การคำนวณ
/// และหน้าตาได้โดยไม่ต้องจำลองทั้งหน้า

/// สรุปความคืบหน้าของนิสิตจากผลลัพธ์ `/students/me/hours-summary`
///
/// ใช้กติกาเดียวกับฝั่ง backend (`app/completion.py`): ชั่วโมงที่เกินเป้าของรายการหนึ่ง
/// **ไม่** ไปชดเชยรายการที่ยังขาด ตัวเลข 100% จึงแปลว่าครบเกณฑ์จริง ๆ ไม่ใช่แค่
/// เก็บชั่วโมงรวมถึงเป้า
class StudentProgressSummary {
  const StudentProgressSummary({
    required this.earned,
    required this.required_,
    required this.gaps,
  });

  /// ชั่วโมงที่นับเข้าเกณฑ์ (ตัดส่วนเกินรายรายการแล้ว)
  final double earned;

  /// เป้ารวมของชุดเกณฑ์ที่นิสิตสังกัด
  final double required_;

  /// รายการที่ยังไม่ครบ เรียงจากที่ขาดมากที่สุด
  final List<HourSubcategorySummary> gaps;

  factory StudentProgressSummary.from(List<HourCategorySummary> talents) {
    // รายการที่ตรวจความครบคือ "หมวดย่อย" ของแต่ละ Talent — Talent ที่ไม่มีหมวดย่อย
    // (ชุดเกณฑ์เดิมที่ไม่มี Talent) ให้ถือว่าตัวมันเองคือรายการ
    final items = <HourSubcategorySummary>[];
    for (final t in talents) {
      if (t.subcategories.isEmpty) {
        items.add(HourSubcategorySummary(
          id: t.id,
          name: t.name,
          requiredHours: t.requiredHours,
          earnedHours: t.earnedHours,
          completed: t.completed,
        ));
      } else {
        items.addAll(t.subcategories);
      }
    }

    var earned = 0.0;
    var required = 0.0;
    for (final i in items) {
      required += i.requiredHours;
      earned += i.earnedHours > i.requiredHours ? i.requiredHours : i.earnedHours;
    }

    final gaps = items.where((i) => !i.completed).toList()
      ..sort((a, b) => (b.requiredHours - b.earnedHours)
          .compareTo(a.requiredHours - a.earnedHours));

    return StudentProgressSummary(earned: earned, required_: required, gaps: gaps);
  }

  double get percent => required_ <= 0 ? 0 : (earned / required_ * 100);

  /// ไม่มีเกณฑ์ให้วัด = ยังตัดสินไม่ได้ว่าครบ — เหมือนฝั่ง backend
  bool get completed => required_ > 0 && gaps.isEmpty;

  Set<int> get gapItemIds => {for (final g in gaps) g.id};
}

/// กิจกรรมที่นิสิตสมัครไว้และยังไม่ถึงวันจัด
List<Activity> upcomingRegistered(
  List<Participation> participations,
  List<Activity> activities, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final byId = {
    for (final a in activities)
      if (a.id != null) a.id!: a,
  };
  final mine = <Activity>[
    for (final p in participations)
      if (byId[p.activityId] != null) byId[p.activityId]!,
  ];
  final upcoming = mine.where((a) => a.startAt.isAfter(at)).toList()
    ..sort((a, b) => a.startAt.compareTo(b.startAt));
  return upcoming;
}

/// กิจกรรมที่ควรแนะนำให้นิสิตไปเข้าร่วม
///
/// เลือกกิจกรรมที่ยังเปิดรับ ยังไม่ถึงวันจัด ยังไม่ได้สมัคร และ **นับเข้ารายการเกณฑ์
/// ที่ยังขาด** ถ้าไม่มีอันไหนตรงเลยก็ใช้กิจกรรมที่ใกล้ถึงที่สุดแทน ดีกว่าโชว์การ์ดว่าง
///
/// หมายเหตุ: รายการเกณฑ์ที่เป็น "กลุ่มแชร์เป้าชั่วโมง" (กฎ Social) ใช้ id ของสมาชิก
/// ตัวแรกเป็นตัวแทน กิจกรรมของสมาชิกอีกตัวจึงไม่ตรง id และจะตกไปเข้าทางสำรอง
List<Activity> recommendedActivities({
  required List<Activity> activities,
  required List<Participation> participations,
  required Set<int> gapItemIds,
  DateTime? now,
  int limit = 3,
}) {
  final at = now ?? DateTime.now();
  final registered = {for (final p in participations) p.activityId};

  final open = activities
      .where((a) =>
          a.id != null &&
          a.approvalStatus == 'approved' &&
          !a.isHidden &&
          !a.isFull &&
          a.startAt.isAfter(at) &&
          !registered.contains(a.id))
      .toList()
    ..sort((a, b) => a.startAt.compareTo(b.startAt));

  final matching =
      open.where((a) => a.requirementIds.any(gapItemIds.contains)).toList();
  final picked = matching.isNotEmpty ? matching : open;
  return picked.take(limit).toList();
}

/// การ์ด "ชั่วโมงตาม Talent / PLO" — หนึ่งแถบต่อหนึ่ง Talent
class TalentProgressCard extends StatelessWidget {
  const TalentProgressCard({super.key, required this.talents, this.onOpenDetail});

  final List<HourCategorySummary> talents;

  /// ปุ่ม "ใบประมวลผลกิจกรรม" — พาไปหน้ารายละเอียดชั่วโมง
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ชั่วโมงตาม Talent / PLO', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          if (talents.isEmpty)
            Text(
              'ยังไม่มีชั่วโมงสะสม — ชั่วโมงจะขึ้นเมื่อหลักฐานได้รับการอนุมัติ',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
            )
          else
            for (final t in talents) ...[
              ProgressRow(
                label: t.name,
                // ครบแล้วติดเครื่องหมายถูกตาม mockup
                value: '${formatHours(t.earnedHours)}/${formatHours(t.requiredHours)}'
                    '${t.completed ? ' ✓' : ''}',
                progress: t.requiredHours == 0 ? 1 : t.earnedHours / t.requiredHours,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          if (onOpenDetail != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: AppButtonStyles.dark(context),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('ใบประมวลผลกิจกรรม'),
                onPressed: onOpenDetail,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// การ์ด "แนะนำให้เข้าร่วม" — กิจกรรมเปิดรับที่เติมรายการเกณฑ์ที่ยังขาด
class SuggestedActivitiesCard extends StatelessWidget {
  const SuggestedActivitiesCard({
    super.key,
    required this.activities,
    this.matchedGaps = true,
    this.onSeeAll,
  });

  final List<Activity> activities;

  /// ยังมีรายการที่ขาดอยู่ไหม — ใช้เลือกคำโปรยให้ตรงความจริง
  final bool matchedGaps;

  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('แนะนำให้เข้าร่วม', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            matchedGaps ? 'เติมรายการที่ยังขาด' : 'ครบเกณฑ์แล้ว — กิจกรรมที่ใกล้ถึง',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          if (activities.isEmpty)
            const EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'ยังไม่มีกิจกรรมเปิดรับ',
              message: 'เมื่อมีกิจกรรมใหม่เปิดรับสมัคร จะขึ้นแนะนำตรงนี้',
            )
          else
            for (final a in activities) ...[
              _SuggestionTile(activity: a),
              const SizedBox(height: AppSpacing.sm),
            ],
          if (onSeeAll != null && activities.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onSeeAll, child: const Text('ดูกิจกรรมทั้งหมด →')),
            ),
        ],
      ),
    );
  }
}

/// กล่องกิจกรรมหนึ่งอันในการ์ดแนะนำ: ชื่อ + ชั่วโมง + วันที่ ตาม mockup
class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            activity.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _Meta(icon: Icons.schedule, text: '${formatHours(activity.hours)} ชม.'),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: _Meta(
                  icon: Icons.calendar_today_outlined,
                  text: formatThaiDate(activity.startAt),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.sub);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.sub),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
      ],
    );
  }
}
