import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/evidence_io.dart';

/// Renders evidence bytes: images inline (zoomable) with a graceful fallback to
/// "open in a new tab" when the browser can't decode them (B1), and non-images
/// (PDF) as an open-in-tab button. Shared by the evidence dialog and the OCR
/// review screen so the fallback logic lives in one place.
class EvidencePreview extends StatelessWidget {
  final Uint8List bytes;
  final String contentType;

  const EvidencePreview({super.key, required this.bytes, required this.contentType});

  @override
  Widget build(BuildContext context) {
    if (!contentType.startsWith('image/')) {
      return Center(
        child: TextButton.icon(
          onPressed: () => openBytesInNewTab(bytes, contentType),
          icon: const Icon(Icons.open_in_new),
          label: const Text('เปิดไฟล์ในแท็บใหม่'),
        ),
      );
    }
    return InteractiveViewer(
      child: Image.memory(
        bytes,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              const Text('แสดงตัวอย่างรูปไม่ได้'),
              TextButton.icon(
                onPressed: () => openBytesInNewTab(bytes, contentType),
                icon: const Icon(Icons.open_in_new),
                label: const Text('เปิดไฟล์ในแท็บใหม่'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
