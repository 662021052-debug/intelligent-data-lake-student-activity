import 'package:flutter/material.dart';

import '../models/activity_import.dart';
import '../theme/app_theme.dart';

/// สรุปผลการนำเข้าแผนกิจกรรม: สำเร็จกี่แถว ผิดกี่แถว พร้อมเหตุผลรายแถว
///
/// แยกออกมาเป็น widget ล้วน ๆ (รับผลลัพธ์เข้ามา ไม่ยิง API เอง) เพื่อให้เทสต์
/// ยืนยันหน้าตาของทุกกรณีได้ — สำเร็จหมด / สำเร็จบางส่วน / ไม่ผ่านเลย
class ActivityImportSummary extends StatelessWidget {
  const ActivityImportSummary({super.key, required this.result, this.needsApproval = true});

  final ActivityImportResult result;

  /// กิจกรรมที่เพิ่งนำเข้ายังต้องรออนุมัติหรือไม่
  ///
  /// เป็นจริงเมื่อผู้นำเข้าเป็น staff — กิจกรรมของ admin ถูกอนุมัติให้ทันทีตั้งแต่
  /// ตอนสร้าง (กฎเดียวกับการสร้างทีละอัน) จึงไม่ต้องเตือน รับเป็นพารามิเตอร์แทน
  /// การอ่าน authService เองเพื่อให้ widget นี้ยังเป็น widget ล้วนที่เทสต์ตรงได้
  final bool needsApproval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = result.isCompleteFailure
        ? StatusPalette.rejected
        : result.isPartial
            ? StatusPalette.pending
            : StatusPalette.approved;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Icon(
                result.isCompleteFailure
                    ? Icons.error_outline
                    : result.isPartial
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                color: palette.foreground,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'อ่านได้ ${result.totalRows} แถว • '
                  'เพิ่มสำเร็จ ${result.createdCount} แถว • '
                  'ผิด ${result.errorCount} แถว',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (result.createdCount > 0 && needsApproval) ...[
          const SizedBox(height: AppSpacing.md),
          // ถ้าไม่บอกตรงนี้ เจ้าหน้าที่จะงงว่าทำไมนิสิตยังไม่เห็นกิจกรรมที่เพิ่งนำเข้า
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'กิจกรรมที่นำเข้าอยู่ในสถานะ "รออนุมัติ" ต้องกดอนุมัติก่อนนิสิตจึงจะเห็น',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
        if (result.errors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('แถวที่ต้องกลับไปแก้', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          // จำกัดความสูงไว้ ไฟล์ที่ผิดทั้งไฟล์จะได้ไม่ดัน dialog ยาวจนกดปุ่มไม่ถึง
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: result.errors.length,
              itemBuilder: (context, index) {
                final error = result.errors[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          'แถว ${error.row}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(error.message, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
