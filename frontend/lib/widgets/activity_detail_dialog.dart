import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/criteria_set.dart';
import '../models/hour_category.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_buttons.dart';
import 'app_card.dart';
import 'status_chip.dart';

/// สิ่งที่นิสิตกดออกมาจากหน้ารายละเอียด — หน้าที่เรียกเป็นคนทำจริง
///
/// ไดอะล็อกไม่ยิง API เอง เพื่อให้กติกาการสมัคร/ยกเลิก (ยืนยันซ้ำ, โหลดใหม่,
/// ข้อความ error) อยู่ที่เดียวกับปุ่มบนการ์ดเสมอ ไม่ใช่สองชุดที่เพี้ยนจากกันได้
enum ActivityDetailAction { register, cancel }

/// รายละเอียดกิจกรรมแบบเต็มก่อนตัดสินใจสมัคร
///
/// เดิมนิสิตกดสมัครได้จากการ์ดเลย โดยเห็นแค่ชื่อ/วัน/สถานที่แบบย่อ — หน้านี้รวม
/// ทุกอย่างที่ต้องรู้ก่อนกด: ได้กี่ชั่วโมง เข้าเกณฑ์รายการไหน (พร้อมหน่วยการเรียนรู้
/// และป้ายบังคับ/เลือก) ที่นั่งเหลือเท่าไร และหมวดนั้นตัวเองยังขาดอีกกี่ชั่วโมง
///
/// **ไม่มีช่อง "คำอธิบายกิจกรรม" เพราะ `activity` ยังไม่มีคอลัมน์นั้น** — ถ้าเพิ่ม
/// ในอนาคตให้วางต่อจากบล็อกที่นั่ง
class ActivityDetailDialog extends StatelessWidget {
  const ActivityDetailDialog({
    super.key,
    required this.activity,
    required this.categories,
    required this.criteriaSets,
    this.registered = false,
    this.evidenceStatus,
    this.closed = false,
    this.categoryProgress,
    this.countdown,
  });

  final Activity activity;
  final List<HourCategory> categories;
  final List<CriteriaSet> criteriaSets;

  /// นิสิตคนนี้สมัครกิจกรรมนี้ไว้แล้วหรือยัง
  final bool registered;

  /// สถานะหลักฐานของการสมัครนั้น (มีค่าเมื่อ [registered] เป็นจริง)
  final String? evidenceStatus;

  /// เลยวันจัดไปแล้ว — สมัครไม่ได้อีก
  final bool closed;

  /// "หมวดนี้คุณมี x/y ชม. ยังขาดอีก z" — null เมื่อไม่รู้จักหมวดของกิจกรรมนี้
  final String? categoryProgress;

  /// ป้ายนับถอยหลัง เช่น "อีก 3 วัน" — หน้าที่เรียกส่งมาเพื่อใช้กติกาเดียวกับการ์ด
  final String? countdown;

  /// รายการเกณฑ์ที่กิจกรรมนี้นับเข้า — ว่างแปลว่าเป็นกิจกรรมโครงเดิมที่มีแต่หมวดย่อย
  List<CriteriaRequirement> get _requirements {
    final byId = requirementsById(criteriaSets);
    return [
      for (final id in activity.requirementIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = activity.maxParticipants - activity.participantCount;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.frame)),
      // จอแคบ: เว้นขอบน้อยลงเพื่อให้เนื้อหากว้างพอ ไม่ต้องเลื่อนแนวนอน
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      contentPadding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.md),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              StatusChip(
                label: activity.activityType,
                palette: StatusPalette.neutral,
                dense: true,
              ),
              if (countdown != null)
                StatusChip(
                  label: countdown!,
                  palette: closed ? StatusPalette.neutral : StatusPalette.info,
                  dense: true,
                ),
              if (activity.isRequired)
                const StatusChip(
                  label: 'กิจกรรมบังคับ',
                  palette: StatusPalette.pending,
                  dense: true,
                ),
              if (registered && evidenceStatus != null)
                StatusChip.evidence(evidenceStatus!, dense: true),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(activity.name, style: theme.textTheme.titleLarge),
        ],
      ),
      content: ConstrainedBox(
        // กว้างพอให้ชื่อรายการเกณฑ์ยาว ๆ อ่านได้ แต่ไม่เกินจอแคบ
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _block(context, 'วันเวลาและสถานที่', [
                _row(Icons.event, formatThaiDateTimeRange(activity.startAt, activity.endAt)),
                _row(Icons.place_outlined, activity.location),
              ]),
              _block(context, 'ชั่วโมงที่ได้', [
                _row(Icons.schedule, '${formatHours(activity.hours)} ชั่วโมง'),
                _note(context, 'ชั่วโมงจะถูกนับเมื่อหลักฐานผ่านการอนุมัติ'),
              ]),
              _block(context, 'นับเข้าเกณฑ์', _criteriaRows(context)),
              _block(context, 'ที่นั่ง', [
                _row(
                  Icons.groups_outlined,
                  'รับ ${activity.participantCount}/${activity.maxParticipants} คน'
                  '${remaining > 0 ? ' • เหลือ $remaining ที่' : ''}',
                ),
                if (remaining <= 0)
                  _note(context, 'ที่นั่งเต็มแล้ว'),
                if (categoryProgress != null) _note(context, categoryProgress!),
              ]),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      actions: _actions(context),
    );
  }

  /// รายการเกณฑ์ที่กิจกรรมนับเข้า — ชุดใหม่แสดงทีละรายการพร้อมหน่วยการเรียนรู้
  /// ส่วนกิจกรรมโครงเดิมที่มีแต่หมวดย่อยยังแสดงเป็น "หมวดแม่ › หมวดย่อย" เหมือนหน้าอื่น
  List<Widget> _criteriaRows(BuildContext context) {
    final requirements = _requirements;
    if (requirements.isEmpty) {
      return [_row(Icons.category_outlined, subcategoryPath(categories, activity.subcategoryId))];
    }
    return [
      for (final r in requirements)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.check_circle_outline, size: 15, color: AppColors.muted),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.name, style: Theme.of(context).textTheme.bodyMedium),
                    if (r.learningUnitName != null)
                      Text(
                        'หน่วยการเรียนรู้: ${r.learningUnitName}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusChip(
                label: r.isMandatory ? 'บังคับ' : 'เลือก',
                palette: r.isMandatory ? StatusPalette.pending : StatusPalette.neutral,
                dense: true,
              ),
            ],
          ),
        ),
    ];
  }

  /// ปุ่มท้ายไดอะล็อก — สถานะเดียวกับปุ่มบนการ์ดเป๊ะ (สมัคร / ยกเลิก / เต็ม / ปิดรับ)
  List<Widget> _actions(BuildContext context) {
    final close = TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('ปิด'),
    );
    if (registered) {
      return [
        close,
        OutlinedButton.icon(
          icon: const Icon(Icons.close, size: 16),
          label: const Text('ยกเลิกการสมัคร'),
          style: AppButtonStyles.danger(context),
          onPressed: () => Navigator.pop(context, ActivityDetailAction.cancel),
        ),
      ];
    }
    if (activity.isFull) {
      return [
        const StatusChip(
          label: 'เต็มแล้ว',
          palette: StatusPalette.neutral,
          icon: Icons.group_off_outlined,
          dense: true,
        ),
        close,
      ];
    }
    if (closed) {
      return [
        const StatusChip(
          label: 'ปิดรับสมัครแล้ว',
          palette: StatusPalette.neutral,
          icon: Icons.lock_clock,
          dense: true,
        ),
        close,
      ];
    }
    return [
      close,
      FilledButton(
        onPressed: () => Navigator.pop(context, ActivityDetailAction.register),
        child: const Text('สมัครเข้าร่วม'),
      ),
    ];
  }

  Widget _block(BuildContext context, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.blueDark, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            ...children,
          ],
        ),
      );

  Widget _row(IconData icon, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: MetaItem(icon: icon, label: label),
      );

  Widget _note(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
      );
}
