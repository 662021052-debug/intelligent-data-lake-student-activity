import 'package:flutter/material.dart';

import '../utils/evidence_kind.dart';

/// ถามประเภทหลักฐานก่อนเลือกไฟล์ — คืนค่าที่เลือก (`certificate` / `photo` / `other`)
/// หรือ null ถ้ายกเลิก
Future<String?> showEvidenceKindDialog(BuildContext context) => showDialog<String>(
      context: context,
      builder: (_) => const EvidenceKindDialog(),
    );

/// ตัวเลือก "ประเภทหลักฐาน" (บังคับ)
///
/// ไม่มีค่าเริ่ม และปุ่ม "เลือกไฟล์" กดไม่ได้จนกว่าจะเลือก — ถ้าเลือกให้ ภาพถ่ายที่นิสิตไม่ได้ตั้งใจ
/// ระบุประเภทจะถูกนับเป็นเกียรติบัตรและหลุดเข้าเส้นทางอนุมัติอัตโนมัติได้
class EvidenceKindDialog extends StatefulWidget {
  const EvidenceKindDialog({super.key});

  @override
  State<EvidenceKindDialog> createState() => _EvidenceKindDialogState();
}

class _EvidenceKindDialogState extends State<EvidenceKindDialog> {
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return AlertDialog(
      title: const Text('ประเภทหลักฐาน'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('เลือกให้ตรงกับไฟล์ที่จะอัปโหลด *', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _kind,
              onChanged: (value) => setState(() => _kind = value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final kind in kEvidenceKinds)
                    RadioListTile<String>(
                      value: kind,
                      title: Text(evidenceKindOptionLabel(kind)),
                      subtitle: Text(evidenceKindOptionDetail(kind)),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    kEvidenceKindUploadHint,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: _kind == null ? null : () => Navigator.pop(context, _kind),
          child: const Text('เลือกไฟล์'),
        ),
      ],
    );
  }
}
