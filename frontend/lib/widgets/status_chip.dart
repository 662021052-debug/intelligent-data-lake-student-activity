import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/evidence_status.dart';
import '../utils/ocr_status.dart';

/// ชิปแสดง "สถานะ" ตัวเดียวที่ใช้ซ้ำทั้งแอป
///
/// เดิมแต่ละหน้า hardcode `Chip(backgroundColor: Colors.green.shade100)` เองทำให้
/// สีเพี้ยนกันไปมา — ตอนนี้สีมาจาก [StatusPalette] ที่เดียว: อนุมัติ=เขียว,
/// รอตรวจ=เหลือง/ส้ม, ไม่อนุมัติ=แดง, กิจกรรมรออนุมัติ=เทา
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.palette,
    this.icon,
    this.dense = false,
  });

  final String label;
  final StatusPalette palette;
  final IconData? icon;

  /// ใช้ในตาราง/แถวแคบ — ตัดระยะขอบลงให้แถวไม่สูงเกิน
  final bool dense;

  /// สถานะหลักฐานการเข้าร่วม (approved / pending / rejected)
  factory StatusChip.evidence(String status, {bool dense = false}) {
    return StatusChip(
      label: evidenceLabel(status),
      palette: switch (status) {
        'approved' => StatusPalette.approved,
        'rejected' => StatusPalette.rejected,
        _ => StatusPalette.pending,
      },
      icon: switch (status) {
        'approved' => Icons.check_circle_outline,
        'rejected' => Icons.cancel_outlined,
        _ => Icons.schedule,
      },
      dense: dense,
    );
  }

  /// สถานะการอนุมัติ "กิจกรรม" (approved / pending) — pending เป็นสีเทากลาง ๆ
  /// เพราะเป็นแค่ขั้นตอนรอ ไม่ใช่ความผิดปกติ
  factory StatusChip.activityApproval(String status, {bool dense = false}) {
    final approved = status == 'approved';
    return StatusChip(
      label: approved ? 'อนุมัติแล้ว' : 'รออนุมัติ',
      palette: approved ? StatusPalette.approved : StatusPalette.neutral,
      icon: approved ? Icons.verified_outlined : Icons.hourglass_empty,
      dense: dense,
    );
  }

  /// ผลตรวจ OCR ชั้น Silver (auto_approved / needs_review / flagged)
  factory StatusChip.ocr(String decision, {bool dense = false}) {
    return StatusChip(
      label: ocrDecisionLabel(decision),
      palette: switch (decision) {
        'auto_approved' => StatusPalette.approved,
        'flagged' => StatusPalette.rejected,
        _ => StatusPalette.info,
      },
      dense: dense,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context)
        .textTheme
        .labelLarge
        ?.copyWith(color: palette.foreground, fontWeight: FontWeight.w600);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: palette.foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}
