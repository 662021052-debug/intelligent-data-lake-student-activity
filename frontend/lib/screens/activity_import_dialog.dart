import 'package:flutter/material.dart';

import '../models/activity_import.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../utils/download_io.dart';
import '../utils/evidence_io.dart';
import '../widgets/activity_import_summary.dart';
import '../widgets/app_card.dart';
import '../widgets/dialogs.dart';

/// ชื่อไฟล์ต้นแบบที่ฝั่งเว็บตั้งเอง — ต้องตรงกับที่ backend ตั้งใน
/// `Content-Disposition` เพราะเราสร้างไฟล์จาก blob เอง (แบบเดียวกับรายงานชั่วโมง)
const importTemplateFileName = 'เทมเพลตนำเข้าแผนกิจกรรม.xlsx';

const _xlsxMediaType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Dialog "นำเข้าแผนกิจกรรม" (ข้อ 6.7) — สำหรับเจ้าหน้าที่/ผู้ดูแล
///
/// ปิดแล้วคืนค่า true ถ้ามีกิจกรรมถูกสร้างจริงอย่างน้อยหนึ่งรายการ เพื่อให้หน้า
/// จัดการกิจกรรมโหลดรายการใหม่ — ไฟล์ที่ผิดทั้งไฟล์ไม่ต้องโหลดใหม่ให้เสียเที่ยว
class ActivityImportDialog extends StatefulWidget {
  const ActivityImportDialog({super.key});

  @override
  State<ActivityImportDialog> createState() => _ActivityImportDialogState();
}

class _ActivityImportDialogState extends State<ActivityImportDialog> {
  bool _busy = false;
  String? _error;
  String? _filename;
  ActivityImportResult? _result;

  Future<void> _downloadTemplate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await ApiService.downloadBytes('/activities/import/template.xlsx');
      saveBytesAsFile(bytes, importTemplateFileName, _xlsxMediaType);
      if (mounted) showInfoSnackbar(context, 'ดาวน์โหลดไฟล์ต้นแบบแล้ว');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final picked = await pickSpreadsheetFile();
    // ผู้ใช้กดยกเลิกกล่องเลือกไฟล์ — ไม่ใช่ error ไม่ต้องขึ้นอะไร
    if (picked == null) return;

    final (bytes, filename, _) = picked;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _filename = filename;
    });
    try {
      final result = await ApiService.importActivities(bytes, filename);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      // 400 = ไฟล์ใช้ไม่ได้ทั้งไฟล์ (หัวตารางไม่ครบ/นามสกุลผิด) ข้อความไทยจาก
      // backend อธิบายไว้แล้วว่าต้องแก้อะไร จึงแสดงตรง ๆ
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;

    return AlertDialog(
      title: const Text('นำเข้าแผนกิจกรรม'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'อัปโหลดไฟล์ .xlsx หรือ .csv ที่มีคอลัมน์ '
                'ชื่อ / ประเภท / หมวดย่อย / วันเวลา / ชั่วโมง / สถานที่ / จำนวนรับ / บังคับ '
                'แถวที่กรอกผิดจะถูกข้ามและรายงานเลขแถวกลับมา ไม่ล้มทั้งไฟล์',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: _busy ? null : _downloadTemplate,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('ดาวน์โหลดไฟล์ต้นแบบ'),
              ),
              const SizedBox(height: AppSpacing.md),
              // พื้นที่วางไฟล์แบบ mockup — กดทั้งกล่องได้ ไม่ต้องเล็งปุ่มเล็ก ๆ
              InkWell(
                onTap: _busy ? null : _pickAndUpload,
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: DottedUploadArea(
                  label: result == null ? 'เลือกไฟล์เพื่อนำเข้า' : 'เลือกไฟล์อื่น',
                  filename: _filename,
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: AppSpacing.lg),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: StatusPalette.rejected.background,
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 18, color: StatusPalette.rejected.foreground),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: StatusPalette.rejected.foreground),
                      ),
                    ),
                    ],
                  ),
                ),
              ],
              if (result != null) ...[
                const SizedBox(height: AppSpacing.lg),
                ActivityImportSummary(
                  result: result,
                  // กิจกรรมของ admin ถูกอนุมัติตั้งแต่นำเข้า จึงไม่ต้องเตือนให้ไปอนุมัติ
                  needsApproval: !authService.isAdmin,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _busy
              ? null
              : () => Navigator.pop(context, (_result?.createdCount ?? 0) > 0),
          child: const Text('ปิด'),
        ),
      ],
    );
  }
}
