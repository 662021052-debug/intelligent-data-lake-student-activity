import 'package:flutter/material.dart';

import '../models/participation.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// ชิ้นส่วนที่หน้าเช็กอินทุกทางเข้าใช้ร่วมกัน
///
/// มีสองทางที่นิสิตเช็กอินได้ — สแกนในแอป (F1) และเปิดลิงก์จากกล้องปกติ (F4) —
/// ผลลัพธ์ที่เห็นต้องเหมือนกันเป๊ะ ไม่งั้นเหมือนคนละระบบ

/// ย้ำกฎ D2: เช็กอินคือบันทึกว่ามาร่วมงาน ไม่ใช่ได้ชั่วโมง
class CheckinHoursNotice extends StatelessWidget {
  const CheckinHoursNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: StatusPalette.info.background,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: StatusPalette.info.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'การเช็กอินเป็นการบันทึกว่าคุณมาร่วมงานเท่านั้น '
              'ชั่วโมงกิจกรรมจะนับให้เมื่อส่งหลักฐานและเจ้าหน้าที่อนุมัติแล้ว',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: StatusPalette.info.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดเขียว "เช็กอินสำเร็จ" พร้อมชื่อกิจกรรมและเวลาที่บันทึกไว้
class CheckinSuccessCard extends StatelessWidget {
  final Participation participation;

  const CheckinSuccessCard({super.key, required this.participation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checkedInAt = participation.checkInTime;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: StatusPalette.approved.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: StatusPalette.approved.foreground.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 40, color: StatusPalette.approved.foreground),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'เช็กอินสำเร็จ',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: StatusPalette.approved.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  participation.activityName ?? 'กิจกรรม #${participation.activityId}',
                  style: theme.textTheme.titleMedium,
                ),
                if (checkedInAt != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'เวลาเช็กอิน ${formatDateTime(serverTimeToLocal(checkedInAt))} น.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(
                  'อย่าลืมส่งหลักฐานการเข้าร่วมเพื่อให้ได้ชั่วโมง',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// แถบแดงบอกสาเหตุที่เช็กอินไม่ผ่าน (ข้อความไทยที่ backend ส่งมา)
class CheckinErrorBanner extends StatelessWidget {
  final String message;

  const CheckinErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: StatusPalette.rejected.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: StatusPalette.rejected.foreground),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: StatusPalette.rejected.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
