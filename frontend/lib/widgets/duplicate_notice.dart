import 'package:flutter/material.dart';

import '../models/ocr_result.dart';
import '../theme/app_theme.dart';
import '../utils/evidence_status.dart';
import '../utils/ocr_status.dart';
import 'dialogs.dart';

/// ใบนี้ต้องให้เจ้าหน้าที่รับรู้ก่อนอนุมัติไหม — ผล OCR ล่าสุดเป็น flagged หรือไฟล์ซ้ำ
bool needsDuplicateConfirmation(OcrResult? ocr) =>
    ocr != null && (ocr.decision == 'flagged' || ocr.isDuplicate);

/// แถบบอกว่าไฟล์หลักฐานนี้ซ้ำกับใบไหน (แทนป้าย "ไฟล์ซ้ำ" ลอย ๆ)
///
/// [onOpenOriginal] แสดงเป็นลิงก์ "ดูใบต้นทาง" เฉพาะเมื่อ backend บอกว่าผู้ใช้เปิดได้
/// (staff ที่ไม่ได้เป็นเจ้าของกิจกรรมของใบต้นทางเห็นชื่อ แต่เปิดหน้าตรวจไม่ได้)
class DuplicateNotice extends StatelessWidget {
  const DuplicateNotice({super.key, required this.ocr, this.onOpenOriginal});

  final OcrResult ocr;
  final VoidCallback? onOpenOriginal;

  @override
  Widget build(BuildContext context) {
    final palette =
        isSevereDuplicate(ocr.duplicateReason) ? StatusPalette.rejected : StatusPalette.pending;
    final originalStatus = ocr.duplicateOfEvidenceStatus;
    final canOpen = onOpenOriginal != null &&
        ocr.duplicateOfViewable &&
        ocr.duplicateOfParticipationId != null;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.copy_all_outlined, color: palette.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  duplicateContextMessage(ocr),
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // exact = ไฟล์เดียวกันเป๊ะ · near = ภาพคล้าย (ควรเปิดเทียบก่อนตัดสิน)
                if (duplicateMatchKindHint(ocr.matchKind) case final hint?)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      hint,
                      style: textTheme.bodySmall?.copyWith(color: palette.foreground),
                    ),
                  ),
                if (originalStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'สถานะหลักฐานของใบต้นทาง: ${evidenceLabel(originalStatus)}',
                      style: textTheme.bodySmall?.copyWith(color: palette.foreground),
                    ),
                  ),
                if (canOpen)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onOpenOriginal,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('ดูใบต้นทาง'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ถามยืนยันก่อนอนุมัติใบที่ไฟล์ซ้ำ — คืน true เมื่อไปต่อได้
///
/// ไม่บล็อกถาวร (เผื่อมีเหตุผลจริง) และ backend ยังอนุมัติได้เหมือนเดิม การกันอยู่ที่ UX:
/// ใบที่ไม่ซ้ำไปต่อได้ทันทีโดยไม่มี dialog
Future<bool> confirmApproveIfDuplicate(BuildContext context, OcrResult? ocr) async {
  if (!needsDuplicateConfirmation(ocr)) return true;
  final confirmed = await confirmAction(
    context,
    title: 'อนุมัติใบที่ไฟล์ซ้ำ?',
    message: duplicateContextMessage(ocr!),
    detail: 'ระบบไม่บล็อกการอนุมัติ แต่อนุมัติแล้วนิสิตได้ชั่วโมงทันที — '
        'อนุมัติเฉพาะเมื่อตรวจแล้วว่ามีเหตุผลจริง',
    confirmLabel: 'อนุมัติทั้งที่ซ้ำ',
    icon: Icons.copy_all_outlined,
    destructive: true,
  );
  return confirmed == true;
}
