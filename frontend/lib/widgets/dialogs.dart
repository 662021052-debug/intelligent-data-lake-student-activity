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

void showErrorSnackbar(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.toString().replaceFirst('Exception: ', '')),
      backgroundColor: Colors.red,
    ),
  );
}

String? requiredValidator(String? value) =>
    (value == null || value.trim().isEmpty) ? 'กรอกข้อมูล' : null;
