import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/participation.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_buttons.dart';
import 'app_card.dart';
import 'app_data_table.dart';
import 'empty_state.dart';
import 'status_chip.dart';

/// ตาราง "กิจกรรมที่เข้าร่วม" ของนิสิตคนที่ล็อกอินอยู่
///
/// เดิมอยู่บนหน้าแรก แต่หน้าแรกเปลี่ยนเป็นแดชบอร์ดส่วนตัวตาม mockup แล้ว ตารางนี้
/// จึงย้ายมาอยู่หน้า "รายละเอียดชั่วโมง" ซึ่งเป็นที่ที่นิสิตมาดูของละเอียดอยู่แล้ว
/// — ย้าย ไม่ใช่ลบ ประวัติการเข้าร่วมยังต้องหาเจอได้
class ParticipationHistoryCard extends StatelessWidget {
  const ParticipationHistoryCard({
    super.key,
    required this.participations,
    required this.activityById,
    this.onReload,
  });

  final List<Participation> participations;

  /// ใช้เติมสถานที่/วันที่ให้แต่ละแถว — กิจกรรมที่หาไม่เจอ (ถูกซ่อน/ลบ) แสดง "-"
  final Map<int, Activity> activityById;

  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionHeader(
            title: 'กิจกรรมที่เข้าร่วม',
            subtitle: 'ทั้งหมด ${participations.length} รายการ',
            actions: [
              if (onReload != null)
                AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: onReload!),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (participations.isEmpty)
            const EmptyState(
              icon: Icons.event_note_outlined,
              title: 'ยังไม่มีกิจกรรมที่เข้าร่วม',
              message: 'เมื่อสมัครและเข้าร่วมกิจกรรม รายการจะแสดงที่นี่',
            )
          else
            AppDataTable(
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('กิจกรรม')),
                DataColumn(label: Text('สถานที่')),
                DataColumn(label: Text('วันที่จัด')),
                DataColumn(label: Text('สถานะ')),
              ],
              rows: [
                for (final (index, p) in participations.indexed)
                  _row(context, index, p, activityById[p.activityId]),
              ],
            ),
        ],
      ),
    );
  }

  List<DataCell> _row(BuildContext context, int index, Participation p, Activity? activity) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.sub);
    return [
      DataCell(Text('${index + 1}', style: muted)),
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            p.activityName ?? activity?.name ?? '-',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      DataCell(Text(activity?.location ?? '-', style: muted)),
      DataCell(Text(activity == null ? '-' : formatThaiDate(activity.startAt), style: muted)),
      DataCell(StatusChip.evidence(p.evidenceStatus, dense: true)),
    ];
  }
}

/// เรียงการเข้าร่วมให้ล่าสุดขึ้นก่อน
///
/// นิสิตสนใจของที่เพิ่งไปมามากกว่าของเมื่อปีที่แล้ว · กิจกรรมที่หาไม่เจอให้ไปอยู่
/// ท้ายสุดแทนที่จะทำให้ลำดับพัง
void sortParticipationsByRecent(
  List<Participation> participations,
  Map<int, Activity> activityById,
) {
  DateTime startAt(Participation p) =>
      activityById[p.activityId]?.startAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  participations.sort((a, b) => startAt(b).compareTo(startAt(a)));
}
