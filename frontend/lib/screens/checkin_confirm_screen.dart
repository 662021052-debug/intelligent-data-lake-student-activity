import 'package:flutter/material.dart';

import '../models/participation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../widgets/checkin_result.dart';

/// F4a — หน้ายืนยันเช็กอินที่นิสิตมาถึงจากการสแกน QR ด้วยกล้องมือถือปกติ
///
/// **มีขั้นยืนยันเสมอ ไม่เช็กอินให้อัตโนมัติ** — ลิงก์อาจถูกเปิดโดยไม่ตั้งใจ
/// (กดพลาดจากประวัติเบราว์เซอร์ / โหลดหน้าซ้ำ) และนิสิตควรได้เห็นก่อนว่ากำลัง
/// จะเช็กอิน ไม่ใช่รู้ตัวตอนที่ระบบบันทึกไปแล้ว
///
/// ตัวชื่อกิจกรรมยังไม่รู้ตอนเข้าหน้า เพราะ endpoint ที่แปลง token เป็นกิจกรรมได้
/// มีแต่ `/activities/{id}/checkin-qr` ซึ่งเป็นของเจ้าหน้าที่ (นิสิตเรียกได้ 403)
/// จึงยืนยันด้วยข้อความกลาง ๆ แล้วโชว์ชื่อกิจกรรมจากผลลัพธ์หลังเช็กอินสำเร็จ
class CheckinConfirmScreen extends StatefulWidget {
  final String token;

  /// เรียกเมื่อผู้ใช้ออกจากหน้านี้ (เช็กอินเสร็จ/ยกเลิก) เพื่อให้แอปเคลียร์
  /// token ที่ค้างอยู่แล้วกลับไปหน้าปกติ
  final VoidCallback onDone;

  const CheckinConfirmScreen({super.key, required this.token, required this.onDone});

  @override
  State<CheckinConfirmScreen> createState() => _CheckinConfirmScreenState();
}

class _CheckinConfirmScreenState extends State<CheckinConfirmScreen> {
  bool _submitting = false;
  String? _error;
  Participation? _result;

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final participation = await ApiService.checkin(widget.token);
      if (!mounted) return;
      setState(() => _result = participation);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เช็กอินหน้างาน'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_result != null) ...[
                  CheckinSuccessCard(participation: _result!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (_error != null) ...[
                  CheckinErrorBanner(message: _error!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _buildBody(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_result != null) return _DonePanel(onDone: widget.onDone);
    if (!_canCheckin) return _WrongAccountPanel(onDone: widget.onDone);
    return _ConfirmPanel(submitting: _submitting, onConfirm: _confirm, onCancel: widget.onDone);
  }

  /// กันไว้ที่ UI ด้วย ทั้งที่ backend ตอบ 403 อยู่แล้ว — เจ้าหน้าที่ที่เผลอสแกน
  /// QR ของตัวเองควรได้คำอธิบายที่เข้าใจได้ ไม่ใช่ error ดิบ
  bool get _canCheckin => authService.role == 'student';
}

class _ConfirmPanel extends StatelessWidget {
  final bool submitting;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _ConfirmPanel({
    required this.submitting,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.how_to_reg, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'ยืนยันเช็กอินกิจกรรมนี้?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'คุณกำลังเช็กอินในนามของ ${authService.username ?? ''} '
              'ระบบจะบันทึกเวลาที่คุณมาถึงทันทีที่กดยืนยัน',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            const CheckinHoursNotice(),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              icon: submitting
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('ยืนยันเช็กอิน'),
              onPressed: submitting ? null : onConfirm,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: submitting ? null : onCancel,
              child: const Text('ยังไม่เช็กอิน กลับหน้าหลัก'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonePanel extends StatelessWidget {
  final VoidCallback onDone;

  const _DonePanel({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: FilledButton.icon(
          icon: const Icon(Icons.home),
          label: const Text('ไปหน้าหลัก'),
          onPressed: onDone,
        ),
      ),
    );
  }
}

/// เปิดลิงก์ด้วยบัญชีที่เช็กอินไม่ได้ (เจ้าหน้าที่/ผู้ดูแล หรือบัญชีที่ยังไม่ผูก
/// ข้อมูลนิสิต) — บอกให้ชัดพร้อมทางออกคือสลับบัญชี
class _WrongAccountPanel extends StatelessWidget {
  final VoidCallback onDone;

  const _WrongAccountPanel({required this.onDone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.no_accounts, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'บัญชีนี้เช็กอินไม่ได้ (เฉพาะนิสิต)',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'คุณกำลังใช้บัญชี ${authService.username ?? ''} '
              'ถ้าต้องการเช็กอิน ให้ออกจากระบบแล้วเข้าด้วยบัญชีนิสิตของตัวเอง',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('ออกจากระบบเพื่อสลับบัญชี'),
              // ไม่เคลียร์ token ที่ค้างอยู่ เพื่อให้พอเข้าด้วยบัญชีนิสิตแล้ว
              // กลับมาหน้ายืนยันนี้ต่อได้เลย ไม่ต้องสแกนใหม่
              onPressed: authService.logout,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onDone, child: const Text('ไปหน้าหลัก')),
          ],
        ),
      ),
    );
  }
}
