import '../utils/api_error.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/ocr_result.dart';
import '../models/participation.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/ocr_status.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/evidence_preview.dart';
import '../widgets/status_chip.dart';

/// Phase 15 — staff review screen showing the evidence image next to the OCR
/// text and scores, so a reviewer can decide quickly. Auto-approval is an assist;
/// staff can always override (approve / reject) or re-run OCR.
class OcrReviewScreen extends StatefulWidget {
  final int participationId;
  final String studentName;

  const OcrReviewScreen({
    super.key,
    required this.participationId,
    required this.studentName,
  });

  @override
  State<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends State<OcrReviewScreen> {
  bool _loading = false;
  String? _error;

  Uint8List? _bytes;
  String _contentType = '';
  OcrResult? _ocr;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.fetchEvidence(widget.participationId),
        ApiService.fetchOcrResult(widget.participationId),
      ]);
      final (bytes, contentType) = results[0] as (Uint8List, String);
      setState(() {
        _bytes = bytes;
        _contentType = contentType;
        _ocr = results[1] as OcrResult?;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await ApiService.update(
        '/participations/${widget.participationId}',
        {'evidence_status': status},
        Participation.fromJson,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status == 'approved' ? 'อนุมัติแล้ว' : 'ไม่อนุมัติแล้ว')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  Future<void> _reprocess() async {
    try {
      await ApiService.processEvidence(widget.participationId);
      await _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // ไม่ใส่ leading เอง — ใช้ปุ่มย้อนกลับมาตรฐานของ AppBar ปุ่มเดียว
        // (เดิมสร้าง IconButton ซ้ำกับปุ่มที่ Flutter ใส่ให้ กลายเป็นปุ่มย้อนกลับ 2 อัน)
        // หน้าที่เรียกจะรีเฟรชรายการเสมอเมื่อกลับมา จึงไม่ต้องส่งค่ากลับทางปุ่มนี้
        title: Text('ตรวจหลักฐาน: ${widget.studentName}'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'โหลดใหม่',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 800;
                    final image = _buildEvidencePane();
                    final panel = _buildOcrPane();
                    return isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: image),
                              const VerticalDivider(width: 1),
                              Expanded(child: panel),
                            ],
                          )
                        : ListView(children: [
                            SizedBox(height: 320, child: image),
                            const Divider(height: 1),
                            panel,
                          ]);
                  },
                ),
      bottomNavigationBar: _buildActionBar(),
    );
  }

  Widget _buildEvidencePane() {
    final bytes = _bytes;
    if (bytes == null) return const Center(child: Text('ไม่มีไฟล์'));
    return Padding(
      padding: const EdgeInsets.all(8),
      child: EvidencePreview(bytes: bytes, contentType: _contentType),
    );
  }

  Widget _buildOcrPane() {
    final ocr = _ocr;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ผลการอ่านด้วย OCR (Silver Layer)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (ocr == null)
            const Text('ยังไม่ได้ประมวลผล OCR — กด "ประมวลผล OCR" ด้านล่าง')
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip.ocr(ocr.decision),
                _scorePill('ความตรง', ocr.matchScore),
                _scorePill('ความมั่นใจ OCR', ocr.ocrConfidence),
                if (ocr.isDuplicate)
                  const StatusChip(
                    label: 'ไฟล์ซ้ำ',
                    palette: StatusPalette.rejected,
                    icon: Icons.copy_all_outlined,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('ข้อความที่อ่านได้', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  ocr.extractedText.isEmpty ? '(อ่านข้อความไม่ได้)' : ocr.extractedText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scorePill(String label, double value) {
    return Chip(
      avatar: const Icon(Icons.percent, size: 16),
      label: Text('$label ${asPercent(value)}'),
    );
  }

  Widget _buildActionBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _reprocess,
              icon: const Icon(Icons.document_scanner),
              label: const Text('ประมวลผล OCR'),
            ),
            FilledButton.icon(
              onPressed: () => _setStatus('approved'),
              icon: const Icon(Icons.check_circle),
              label: const Text('อนุมัติ'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _setStatus('rejected'),
              icon: const Icon(Icons.cancel),
              label: const Text('ไม่อนุมัติ'),
            ),
          ],
        ),
      ),
    );
  }
}
