import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/checkin_qr.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// หน้าตาของจอ QR เช็กอินที่เจ้าหน้าที่ฉายหน้างาน (F2)
///
/// แยกออกจาก `CheckinQrScreen` ที่ทำหน้าที่โหลดข้อมูล เพื่อให้เทสต์ภาพหน้าจอได้
/// โดยไม่ต้องยิง API — เหมือนที่ [HourSummaryView] ทำ
class CheckinQrView extends StatelessWidget {
  final CheckinQr qr;

  /// เวลาปัจจุบันเป็น UTC (backend ส่งเวลามาเป็น UTC แบบไม่มีโซน)
  final DateTime now;

  final VoidCallback? onCopyToken;

  const CheckinQrView({
    super.key,
    required this.qr,
    required this.now,
    this.onCopyToken,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // QR ใหญ่ที่สุดเท่าที่ยังเหลือที่ให้ข้อความด้านล่าง — ฉายไกล ๆ ต้องยังสแกนติด
        final shortest = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final qrSize = (shortest * 0.62).clamp(220.0, 520.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CheckinWindowBadge(qr: qr, now: now),
                  const SizedBox(height: AppSpacing.lg),
                  // พื้นขาวเสมอ ไม่อิงธีม เพื่อให้คอนทราสต์พอสำหรับกล้องมือถือ
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: QrImageView(
                      // payload เป็นตัวระบุตัวตนของภาพนี้: เปลี่ยน token เมื่อไร
                      // ต้องวาด QR ใหม่ ไม่ใช่ใช้ state เดิม
                      key: ValueKey(qr.qrPayload),
                      data: qr.qrPayload,
                      size: qrSize,
                      backgroundColor: Colors.white,
                      // ระดับ M ทนแสงสะท้อน/ภาพเบลอบนจอโปรเจกเตอร์ได้ดีกว่า L
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      semanticsLabel: 'QR เช็กอิน ${qr.activityName}',
                      errorStateBuilder: (context, error) => SizedBox(
                        width: qrSize,
                        height: qrSize,
                        child: Center(
                          child: Text(
                            'สร้าง QR ไม่สำเร็จ — ให้นิสิตกรอกรหัสด้านล่างแทน',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'ให้นิสิตเปิดแอป → "เช็กอินหน้างาน" → สแกน QR นี้',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _TokenPanel(token: qr.token, onCopy: onCopyToken),
                  const SizedBox(height: AppSpacing.lg),
                  _WindowDetail(qr: qr),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ป้ายสถานะ: ตอนนี้สแกนได้จริงไหม (backend ปฏิเสธการสแกนนอกช่วงเวลา)
///
/// เจ้าหน้าที่จะได้รู้ก่อนที่นิสิตจะมายืนงงหน้าจอ
class _CheckinWindowBadge extends StatelessWidget {
  final CheckinQr qr;
  final DateTime now;

  const _CheckinWindowBadge({required this.qr, required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (palette, icon, label) = qr.isOpenAt(now)
        ? (StatusPalette.approved, Icons.check_circle, 'เปิดให้เช็กอินแล้ว')
        : qr.isBeforeOpenAt(now)
            ? (StatusPalette.pending, Icons.schedule, 'ยังไม่ถึงเวลาเช็กอิน')
            : (StatusPalette.rejected, Icons.block, 'เลยเวลาเช็กอินแล้ว');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: palette.foreground),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: palette.foreground, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// รหัสสำรองตัวใหญ่ — คู่กับทางเลือก "กรอกรหัสกิจกรรม" ในหน้าสแกนของนิสิต
/// (เว็บเปิดกล้องไม่ได้ถ้าไม่ใช่ HTTPS/localhost หรือผู้ใช้ไม่อนุญาตกล้อง)
class _TokenPanel extends StatelessWidget {
  final String token;
  final VoidCallback? onCopy;

  const _TokenPanel({required this.token, this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          Text(
            'กล้องใช้ไม่ได้? ให้นิสิตกรอกรหัสนี้แทน',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            token,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          if (onCopy != null) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('คัดลอกรหัส'),
              onPressed: onCopy,
            ),
          ],
        ],
      ),
    );
  }
}

class _WindowDetail extends StatelessWidget {
  final CheckinQr qr;

  const _WindowDetail({required this.qr});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      children: [
        Text('กิจกรรมเริ่ม ${formatDateTime(serverTimeToLocal(qr.startAt))} น.', style: style),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'สแกนเช็กอินได้ ${formatDateTime(serverTimeToLocal(qr.checkinOpensAt))} – '
          '${formatDateTime(serverTimeToLocal(qr.checkinClosesAt))} น.',
          textAlign: TextAlign.center,
          style: style,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'การเช็กอินบันทึกเฉพาะ "ใครมาร่วมงาน" — ชั่วโมงยังต้องให้นิสิตส่งหลักฐาน '
          'แล้วเจ้าหน้าที่อนุมัติเหมือนเดิม',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
