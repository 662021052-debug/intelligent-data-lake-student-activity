import 'package:flutter/material.dart';

Future<bool?> confirmDelete(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('ยืนยันการลบ'),
      content: Text('ต้องการลบ "$name" ใช่หรือไม่?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('ลบ'),
        ),
      ],
    ),
  );
}

/// Generic confirmation dialog. Returns true when the user confirms.
Future<bool?> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'ยืนยัน',
  Color? confirmColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
        FilledButton(
          style: confirmColor == null
              ? null
              : FilledButton.styleFrom(backgroundColor: confirmColor),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

void showErrorSnackbar(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.toString().replaceFirst('Exception: ', '')),
      backgroundColor: Colors.red,
    ),
  );
}

void showInfoSnackbar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String? requiredValidator(String? value) =>
    (value == null || value.trim().isEmpty) ? 'กรอกข้อมูล' : null;
