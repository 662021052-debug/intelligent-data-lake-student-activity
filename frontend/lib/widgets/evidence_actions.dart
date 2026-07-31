import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/api_error.dart';
import '../utils/evidence_io.dart';
import 'evidence_preview.dart';

const _allowedContentTypes = {'image/jpeg', 'image/png', 'application/pdf'};
const _maxEvidenceBytes = 10 * 1024 * 1024; // 10 MB

/// Lets the user pick an image/PDF and uploads it as evidence for [participationId].
/// Returns true when a file was successfully uploaded.
Future<bool> uploadEvidenceFlow(BuildContext context, int participationId) async {
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
    await ApiService.uploadEvidence(participationId, bytes, filename, contentType);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อัปโหลดหลักฐานสำเร็จ')),
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
