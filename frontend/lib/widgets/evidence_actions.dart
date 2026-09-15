import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/api_error.dart';
import '../utils/evidence_io.dart';
import '../utils/evidence_kind.dart';
import 'evidence_kind_dialog.dart';
import 'evidence_preview.dart';

const _allowedContentTypes = {'image/jpeg', 'image/png', 'application/pdf'};
const _maxEvidenceBytes = 10 * 1024 * 1024; // 10 MB

/// ถามประเภทหลักฐาน (บังคับเลือก) → เลือกไฟล์ภาพ/PDF → อัปโหลดเป็นหลักฐานของ [participationId]
/// Returns true when a file was successfully uploaded.
Future<bool> uploadEvidenceFlow(BuildContext context, int participationId) async {
  // ถามก่อนเลือกไฟล์ — ปิด dialog = ยกเลิกทั้งหมด ไม่มีค่าเริ่ม (ไม่ให้ภาพถ่ายหลุดเป็นเกียรติบัตรเงียบ ๆ)
  final kind = await showEvidenceKindDialog(context);
  if (kind == null || !context.mounted) return false;

  final picked = await pickEvidenceFile();
  if (picked == null) return false;
  final (bytes, filename, contentType) = picked;

  if (!_allowedContentTypes.contains(contentType)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('รองรับเฉพาะไฟล์รูปภาพ (JPEG/PNG) หรือ PDF')),
      );
    }
    return false;
  }
  if (bytes.length > _maxEvidenceBytes) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไฟล์ใหญ่เกิน 10 MB')),
      );
    }
    return false;
  }

  try {
    await ApiService.uploadEvidence(
      participationId,
      bytes,
      filename,
      contentType,
      evidenceKind: kind,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(evidenceKindNeedsHumanReview(kind)
              ? 'อัปโหลดหลักฐานสำเร็จ — รอเจ้าหน้าที่ตรวจ'
              : 'อัปโหลดหลักฐานสำเร็จ'),
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
    return false;
  }
}

/// Fetches the latest evidence for [participationId] and previews it: images are
/// shown inline in a dialog, PDFs are opened in a new browser tab.
Future<void> viewEvidenceFlow(BuildContext context, int participationId) async {
  try {
    final (bytes, contentType) = await ApiService.fetchEvidence(participationId);
    if (!context.mounted) return;
    if (contentType.startsWith('image/')) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: EvidencePreview(bytes: bytes, contentType: contentType),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ปิด'),
              ),
            ],
          ),
        ),
      );
    } else {
      // PDF (or anything else): open in a new tab.
      openBytesInNewTab(bytes, contentType);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }
}
