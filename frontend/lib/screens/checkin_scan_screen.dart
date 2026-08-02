import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/participation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../utils/format.dart';

/// F1 — นิสิตสแกน QR ของกิจกรรมที่หน้างานเพื่อเช็กอินตัวเอง
///
/// ตัวตนผู้เช็กอินมาจาก JWT ที่ backend ล้วน ๆ หน้าจอนี้ส่งไปแค่ token ที่สแกนได้
/// จึงสแกนแทนกันไม่ได้แม้จะถ่ายรูป QR ไปให้เพื่อน
///
/// กล้องบนเว็บต้องเป็น HTTPS หรือ localhost และผู้ใช้ต้องกดอนุญาต (F3) — จึงไม่
/// เปิดกล้องเองทันทีที่เข้าหน้า แต่ให้กดปุ่มก่อน เพื่อให้เบราว์เซอร์ถามสิทธิ์ตอนที่
/// ผู้ใช้ตั้งใจจะสแกนจริง ๆ และมีทางเลือก "กรอกรหัสกิจกรรม" ไว้เสมอเมื่อกล้องใช้ไม่ได้
class CheckinScanScreen extends StatefulWidget {
  const CheckinScanScreen({super.key});

  @override
  State<CheckinScanScreen> createState() => _CheckinScanScreenState();
}

enum _Mode { intro, scanning, manual }

class _CheckinScanScreenState extends State<CheckinScanScreen> {
  _Mode _mode = _Mode.intro;
  MobileScannerController? _controller;
  final TextEditingController _manualInput = TextEditingController();

  bool _submitting = false;
  String? _error;
  Participation? _result;

  @override
  void dispose() {
    _controller?.dispose();
    _manualInput.dispose();
    super.dispose();
  }

  void _startCamera() {
    setState(() {
      _error = null;
      _result = null;
      _mode = _Mode.scanning;
      // สร้างใหม่ทุกครั้งที่เริ่มสแกน: controller ตัวเดิมที่ถูกถอดออกจากต้นไม้แล้ว
      // นำกลับมาใช้ซ้ำไม่ได้
      _controller?.dispose();
      _controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        // กัน QR ใบเดียวยิง onDetect รัว ๆ หลายสิบครั้งต่อวินาที
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    });
  }

  void _stopCamera({_Mode to = _Mode.intro}) {
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    if (mounted) setState(() => _mode = to);
  }

  void _openManualEntry() {
    _manualInput.clear();
    _stopCamera(to: _Mode.manual);
    setState(() {
      _error = null;
      _result = null;
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_submitting || _result != null) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _submit(value);
        return;
      }
    }
  }

  Future<void> _submit(String token) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final participation = await ApiService.checkin(token);
      // เช็กอินสำเร็จแล้วปิดกล้อง ไม่ให้สแกนซ้ำจน error "เช็กอินแล้ว" เด้งใส่
      _controller?.dispose();
      _controller = null;
      if (!mounted) return;
      setState(() {
        _result = participation;
        _mode = _Mode.intro;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (authService.role != 'student') {
      return Scaffold(
        appBar: AppBar(title: const Text('เช็กอินหน้างาน')),
        body: const Center(child: Text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('เช็กอินหน้างาน'),
        actions: [
          if (_mode == _Mode.scanning)
            IconButton(
              tooltip: 'สลับกล้องหน้า/หลัง',
              icon: const Icon(Icons.cameraswitch),
              onPressed: () => _controller?.switchCamera(),
            ),
        ],
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
                  _CheckinSuccessCard(participation: _result!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                switch (_mode) {
                  _Mode.intro => _buildIntro(context),
                  _Mode.scanning => _buildScanner(context),
                  _Mode.manual => _buildManualEntry(context),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final theme = Theme.of(context);
    final scanAgain = _result != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.qr_code_scanner, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'สแกน QR ของกิจกรรมที่หน้างาน',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'เจ้าหน้าที่จะแสดง QR ประจำกิจกรรมไว้ที่จุดลงทะเบียน '
              'สแกนแล้วระบบจะบันทึกเวลาที่คุณมาถึงทันที',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _HoursNotice(),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              icon: const Icon(Icons.photo_camera),
              label: Text(scanAgain ? 'สแกนกิจกรรมอื่น' : 'เปิดกล้องสแกน QR'),
              onPressed: _submitting ? null : _startCamera,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              icon: const Icon(Icons.keyboard),
              label: const Text('กล้องใช้ไม่ได้ — กรอกรหัสกิจกรรมแทน'),
              onPressed: _submitting ? null : _openManualEntry,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => _CameraError(
                    message: _cameraErrorMessage(error),
                    onManualEntry: _openManualEntry,
                  ),
                ),
                // กรอบเล็งให้รู้ว่าต้องวาง QR ตรงไหน
                IgnorePointer(
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.68,
                      heightFactor: 0.68,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 3),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_submitting)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'วาง QR ของกิจกรรมให้อยู่ในกรอบ',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton.icon(
          icon: const Icon(Icons.keyboard),
          label: const Text('กรอกรหัสกิจกรรมแทน'),
          onPressed: _submitting ? null : _openManualEntry,
        ),
        TextButton.icon(
          icon: const Icon(Icons.close),
          label: const Text('ปิดกล้อง'),
          onPressed: _submitting ? null : () => _stopCamera(),
        ),
      ],
    );
  }

  Widget _buildManualEntry(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('กรอกรหัสกิจกรรม', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'ขอรหัสใต้ QR จากเจ้าหน้าที่ที่จุดลงทะเบียน แล้วพิมพ์ลงช่องนี้',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _manualInput,
              autofocus: true,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'รหัสกิจกรรม',
                prefixIcon: Icon(Icons.vpn_key),
              ),
              onSubmitted: (value) => _submitManualInput(value),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _HoursNotice(),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              icon: _submitting
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.how_to_reg),
              label: const Text('เช็กอิน'),
              onPressed:
                  _submitting ? null : () => _submitManualInput(_manualInput.text),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              icon: const Icon(Icons.photo_camera),
              label: const Text('กลับไปใช้กล้องสแกน'),
              onPressed: _submitting ? null : _startCamera,
            ),
          ],
        ),
      ),
    );
  }

  void _submitManualInput(String value) {
    final token = value.trim();
    if (token.isEmpty) {
      setState(() => _error = 'กรอกรหัสกิจกรรมก่อนกดเช็กอิน');
      return;
    }
    _submit(token);
  }

  String _cameraErrorMessage(MobileScannerException error) =>
      switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          'ยังไม่ได้อนุญาตให้ใช้กล้อง — กดอนุญาตในเบราว์เซอร์แล้วลองใหม่ '
              'หรือใช้วิธีกรอกรหัสกิจกรรมแทน',
        MobileScannerErrorCode.unsupported =>
          'อุปกรณ์หรือเบราว์เซอร์นี้เปิดกล้องไม่ได้ (บนเว็บต้องเปิดผ่าน HTTPS หรือ '
              'localhost) — ใช้วิธีกรอกรหัสกิจกรรมแทนได้',
        _ => 'เปิดกล้องไม่สำเร็จ — ใช้วิธีกรอกรหัสกิจกรรมแทนได้',
      };
}

/// ย้ำกฎ D2 ให้นิสิตไม่เข้าใจผิดว่าสแกนแล้วได้ชั่วโมงเลย
class _HoursNotice extends StatelessWidget {
  const _HoursNotice();

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

class _CheckinSuccessCard extends StatelessWidget {
  final Participation participation;

  const _CheckinSuccessCard({required this.participation});

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

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

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

/// แสดงแทนภาพกล้องเมื่อเปิดกล้องไม่ได้ (ไม่อนุญาต / ไม่ใช่ HTTPS / เบราว์เซอร์ไม่รองรับ)
class _CameraError extends StatelessWidget {
  final String message;
  final VoidCallback onManualEntry;

  const _CameraError({required this.message, required this.onManualEntry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off, size: 44, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              icon: const Icon(Icons.keyboard),
              label: const Text('กรอกรหัสกิจกรรมแทน'),
              onPressed: onManualEntry,
            ),
          ],
        ),
      ),
    );
  }
}
