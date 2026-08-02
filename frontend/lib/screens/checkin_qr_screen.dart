import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/checkin_qr.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../widgets/checkin_qr_view.dart';
import '../widgets/dialogs.dart';

/// F2 — จอ QR เช็กอินสำหรับเจ้าหน้าที่ฉายที่หน้างาน
///
/// หน้านี้ทำแค่โหลด token แล้วส่งต่อให้ [CheckinQrView] วาด (แยกไว้เพื่อให้เทสต์
/// หน้าตาได้โดยไม่ต้องยิง API) — เข้าถึงได้เฉพาะ staff เจ้าของกิจกรรมกับ admin
/// ซึ่ง backend เป็นคนบังคับ นิสิตเรียก endpoint นี้จะได้ 403
class CheckinQrScreen extends StatefulWidget {
  final int activityId;

  /// ชื่อกิจกรรมที่รู้อยู่แล้วจากหน้ารายการ — ใช้ขึ้น AppBar ระหว่างรอโหลด
  final String activityName;

  const CheckinQrScreen({
    super.key,
    required this.activityId,
    required this.activityName,
  });

  @override
  State<CheckinQrScreen> createState() => _CheckinQrScreenState();
}

class _CheckinQrScreenState extends State<CheckinQrScreen> {
  CheckinQr? _qr;
  String? _error;
  bool _loading = true;

  /// นาฬิกาสำหรับป้าย "เปิด/ปิดรับเช็กอิน" — จอนี้ถูกฉายค้างไว้เป็นชั่วโมง
  /// ป้ายจึงต้องเปลี่ยนเองเมื่อถึงเวลา ไม่ใช่ค้างค่าตอนเปิดหน้า
  Timer? _ticker;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = DateTime.now().toUtc()),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final qr = await ApiService.fetchCheckinQr(widget.activityId);
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _now = DateTime.now().toUtc();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyToken() async {
    final token = _qr?.token;
    if (token == null) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) showInfoSnackbar(context, 'คัดลอกรหัสกิจกรรมแล้ว');
  }

  @override
  Widget build(BuildContext context) {
    final qr = _qr;

    return Scaffold(
      appBar: AppBar(
        title: Text(qr?.activityName ?? widget.activityName),
        actions: [
          IconButton(
            tooltip: 'โหลดใหม่',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (_error != null) return _ErrorView(message: _error!, onRetry: _load);
          if (qr == null) return const SizedBox.shrink();
          return CheckinQrView(qr: qr, now: _now, onCopyToken: _copyToken);
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
