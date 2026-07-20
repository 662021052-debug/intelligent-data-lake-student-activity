import 'package:flutter/material.dart';

String evidenceLabel(String status) {
  switch (status) {
    case 'approved':
      return 'อนุมัติ';
    case 'rejected':
      return 'ไม่อนุมัติ';
    default:
      return 'รอตรวจสอบ';
  }
}

Color evidenceColor(String status) {
  switch (status) {
    case 'approved':
      return Colors.green.shade100;
    case 'rejected':
      return Colors.red.shade100;
    default:
      return Colors.amber.shade100;
  }
}
