import 'package:flutter/material.dart';

import '../models/participation.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../utils/evidence_status.dart';
import '../utils/format.dart';
import '../utils/ocr_status.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/app_data_table.dart';
import '../widgets/app_table_cells.dart';
import '../widgets/empty_state.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/search_field.dart';
import '../widgets/status_chip.dart';
import 'app_shell.dart';
import 'ocr_review_screen.dart';

const _evidenceStatuses = ['pending', 'approved', 'rejected'];
/// ป้ายสั้นของตัวกรองผล OCR — ป้ายเต็มใน [ocrDecisionLabel] มีอีโมจิและยาวจน
/// dropdown ล้นจอแคบ 360
const _ocrFilterLabels = {
  'auto_approved': 'อนุมัติอัตโนมัติ',
  'needs_review': 'รอเจ้าหน้าที่ตรวจ',
  'flagged': 'ไฟล์ซ้ำ',
};

/// query ของคิวตรวจหลักฐาน — ขอเฉพาะรายการที่ "ส่งไฟล์หลักฐานแล้ว" เสมอ
///
/// การเข้าร่วมที่ยังไม่มีไฟล์ไม่มีอะไรให้ตรวจ ถ้าไม่กรองที่ backend คิวจะจมอยู่ใต้
/// การเข้าร่วมหลายหมื่นรายการที่ไม่มีหลักฐาน
Map<String, String> evidenceReviewQuery({
  required int skip,
  required int limit,
  String? evidenceStatus,
  String? ocrDecision,
  String search = '',
}) =>
    {
      'skip': '$skip',
      'limit': '$limit',
      'has_evidence': 'true',
      'evidence_status': ?evidenceStatus,
      'ocr_decision': ?ocrDecision,
      if (search.isNotEmpty) 'search': search,
    };

/// คิว "ตรวจหลักฐาน" ของ admin/staff — รายการที่มีไฟล์หลักฐาน พร้อมผล OCR (Silver)
///
/// กดแถวเพื่อเปิด [OcrReviewScreen] (รูป + ข้อความที่ OCR อ่านได้ + อนุมัติ/ไม่อนุมัติ/อ่านใหม่)
/// เดิมหน้านั้นเข้าได้ทางเดียวคือ จัดการกิจกรรม → รายชื่อผู้เข้าร่วม ทีละกิจกรรม
/// staff เห็นเฉพาะกิจกรรมของตัวเอง (backend กรองให้)
class EvidenceReviewScreen extends StatefulWidget {
  const EvidenceReviewScreen({super.key});

  @override
  State<EvidenceReviewScreen> createState() => _EvidenceReviewScreenState();
}

class _EvidenceReviewScreenState extends State<EvidenceReviewScreen> {
  static const int _limit = 20;

  List<Participation> _items = [];
  int _total = 0;
  int _skip = 0;
  bool _loading = false;
  String? _error;
  // เปิดมาเจอ "งานที่ต้องทำ" ก่อน — รายการที่ยังรอตรวจ
  String? _statusFilter = 'pending';
  String? _ocrFilter;
  String _search = '';
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ApiService.fetchPage(
        '/participations',
        Participation.fromJson,
        query: evidenceReviewQuery(
          skip: _skip,
          limit: _limit,
          evidenceStatus: _statusFilter,
          ocrDecision: _ocrFilter,
          search: _search,
        ),
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _items = page.items;
        _total = page.total;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  void _refilter(VoidCallback change) {
    setState(change);
    _skip = 0;
    _load();
  }

  Future<void> _openReview(Participation p) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OcrReviewScreen(
          participationId: p.id!,
          studentName: _studentLabel(p),
        ),
      ),
    );
    // อนุมัติ/ไม่อนุมัติ/อ่านใหม่ในหน้านั้นเปลี่ยนสถานะของแถว → โหลดคิวใหม่เสมอ
    if (mounted) _load();
  }

  String _studentLabel(Participation p) {
    final name = p.studentName ?? '#${p.studentId}';
    return p.studentCode == null ? name : '$name (${p.studentCode})';
  }

  String _activityLabel(Participation p) => p.activityName ?? '#${p.activityId}';

  /// วันที่ + เวลาแบบสั้น — ตารางนี้มีหลายคอลัมน์ รูปแบบเต็ม "… เวลา 18:00 น." กินที่จน
  /// ปุ่ม "ตรวจ" ถูกดันล้นขอบการ์ดที่จอ 1440
  String _uploadedLabel(Participation p) {
    final uploaded = p.evidenceUploadedAt;
    if (uploaded == null) return '-';
    // backend เก็บ utcnow แบบไม่มีโซนเวลา — .toLocal() เฉย ๆ ไม่แปลงให้ จะเพี้ยน 7 ชม.
    final local = serverTimeToLocal(uploaded);
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return '${formatThaiDate(local)} $time';
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      activeId: 'evidence_review',
      title: 'ตรวจหลักฐาน',
      subtitle: _statusFilter == 'pending' ? 'รอตรวจ $_total รายการ' : 'พบ $_total รายการ',
      filters: [
        DebouncedSearchField(
          label: 'ค้นหาชื่อ/รหัสนิสิต หรือกิจกรรม',
          width: 280,
          onSearch: (value) => _refilter(() => _search = value),
        ),
        DropdownButton<String?>(
          value: _statusFilter,
          items: [
            const DropdownMenuItem(value: null, child: Text('ทุกสถานะ')),
            for (final s in _evidenceStatuses)
              DropdownMenuItem(value: s, child: Text(evidenceLabel(s))),
          ],
          onChanged: (v) => _refilter(() => _statusFilter = v),
        ),
        DropdownButton<String?>(
          value: _ocrFilter,
          items: [
            const DropdownMenuItem(value: null, child: Text('ทุกผล OCR')),
            for (final entry in _ocrFilterLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) => _refilter(() => _ocrFilter = v),
        ),
        AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: _load),
      ],
      busy: _loading && _items.isNotEmpty,
      footer: _error == null && _items.isNotEmpty
          ? PaginationBar(
              skip: _skip,
              limit: _limit,
              total: _total,
              onChanged: (skip) {
                setState(() => _skip = skip);
                _load();
              },
            )
          : null,
      child: _loading && _items.isEmpty
          ? const LoadingState(message: 'กำลังโหลดหลักฐาน...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? _emptyState()
                  : LayoutBuilder(
                      builder: (context, constraints) => constraints.maxWidth > 800
                          ? TableCard(child: _buildTable())
                          : _buildList(),
                    ),
    );
  }

  Widget _emptyState() {
    final defaultView = _statusFilter == 'pending' && _ocrFilter == null && _search.isEmpty;
    if (!defaultView) return EmptyState.noResults();
    return const EmptyState(
      icon: Icons.task_alt,
      title: 'ไม่มีหลักฐานรอตรวจ',
      message: 'หลักฐานที่นิสิตส่งเข้ามาจะแสดงที่นี่',
    );
  }

  Widget _ocrCell(Participation p) {
    if (!p.hasOcr || p.ocrDecision == null) {
      return Text('ยังไม่ประมวลผล', style: TextStyle(color: AppColors.muted));
    }
    return Tooltip(
      message: 'ความตรง ${asPercent(p.ocrMatchScore ?? 0)} · '
          'ความมั่นใจ OCR ${asPercent(p.ocrConfidence ?? 0)}'
          '${p.ocrDecision == 'flagged' ? ' · กด "ตรวจ" เพื่อดูว่าซ้ำกับใบไหน' : ''}',
      child: StatusChip.ocr(p.ocrDecision!, duplicateReason: p.ocrDuplicateReason, dense: true),
    );
  }

  Widget _buildTable() => AppDataTable(
        columns: const [
          DataColumn(label: Text('นิสิต')),
          DataColumn(label: Text('กิจกรรม')),
          DataColumn(label: Text('ส่งหลักฐานเมื่อ')),
          DataColumn(label: Text('ผล OCR')),
          DataColumn(label: Text('สถานะหลักฐาน')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final p in _items)
            [
              // ชื่อยาวตัด … (ชี้ดูเต็มได้) ไม่งั้นตารางกว้างเกินการ์ดและปุ่ม "ตรวจ" ถูกตัด
              DataCell(TruncatedCell(_studentLabel(p), maxWidth: 200)),
              DataCell(TruncatedCell(_activityLabel(p), maxWidth: 220)),
              DataCell(Text(_uploadedLabel(p))),
              DataCell(_ocrCell(p)),
              DataCell(StatusChip.evidence(p.evidenceStatus, dense: true)),
              DataCell(FilledButton.tonalIcon(
                onPressed: () => _openReview(p),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('ตรวจ'),
              )),
            ],
        ],
      );

  Widget _buildList() => ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final p = _items[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              onTap: () => _openReview(p),
              title: Text(_studentLabel(p)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_activityLabel(p)),
                    _ocrCell(p),
                    StatusChip.evidence(p.evidenceStatus, dense: true),
                  ],
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      );
}
