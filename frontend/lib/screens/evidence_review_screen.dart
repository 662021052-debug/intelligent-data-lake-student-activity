import 'package:flutter/material.dart';

import '../models/participation.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../utils/evidence_kind.dart';
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
          studentName: evidenceStudentLabel(p),
        ),
      ),
    );
    // อนุมัติ/ไม่อนุมัติ/อ่านใหม่ในหน้านั้นเปลี่ยนสถานะของแถว → โหลดคิวใหม่เสมอ
    if (mounted) _load();
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
                          ? TableCard(
                              child: EvidenceReviewTable(items: _items, onReview: _openReview),
                            )
                          : EvidenceReviewCards(items: _items, onReview: _openReview),
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
}

// ------------------------------------------------------------------ ตาราง/การ์ดของคิว

/// "ชื่อ (รหัสนิสิต)" — ไม่มีชื่อจาก API ก็ยังบอกได้ว่าเป็นนิสิต id ไหน
String evidenceStudentLabel(Participation p) {
  final name = p.studentName ?? '#${p.studentId}';
  return p.studentCode == null ? name : '$name (${p.studentCode})';
}

String evidenceActivityLabel(Participation p) => p.activityName ?? '#${p.activityId}';

/// ช่องไฟระหว่างคอลัมน์ / ขอบซ้าย-ขวาของตาราง — ค่าเดียวกับตารางกิจกรรม
const kEvidenceColumnSpacing = AppSpacing.lg;
const kEvidenceTableMargin = AppSpacing.lg;

/// ความสูงแถว — พอสำหรับป้าย OCR สองป้ายซ้อนกัน (ผล OCR + ภาพถ่าย/อื่น ๆ) และวันที่สองบรรทัด
const kEvidenceRowHeight = 64.0;

/// ความกว้างเนื้อหาของคอลัมน์สถานะหลักฐาน — ชิป "ไม่อนุมัติ"/"รอตรวจสอบ" พร้อมไอคอน
const kEvidenceStatusCellWidth = 104.0;

/// ความกว้างคอลัมน์ใน Table = เนื้อหา + padding ที่ DataTable ใส่รอบเซลล์เอง (ครึ่งช่องไฟ
/// แต่ละข้าง คอลัมน์สุดท้ายด้านหลังเป็นขอบตาราง) — ใส่แค่ความกว้างเนื้อหา เนื้อหาจะโดนบีบ
TableColumnWidth _evidenceFixedColumn(double content, {bool last = false}) => FixedColumnWidth(
      content + kEvidenceColumnSpacing / 2 + (last ? kEvidenceTableMargin : kEvidenceColumnSpacing / 2),
    );

/// คอลัมน์ของคิวตรวจหลักฐาน ซ้าย→ขวา — พอดีความกว้างการ์ด ไม่เลื่อนแนวนอน
///
/// * นิสิต · กิจกรรม · ผล OCR แชร์พื้นที่ที่เหลือแบบ flex — ข้อความ/ป้ายยาวตัด … (ชี้ดูเต็มได้)
/// * ส่งเมื่อ · สถานะ · ปุ่ม "ตรวจ" กว้างคงที่ — ปุ่มอยู่ขวาสุดและไม่ถูกดันออกนอกการ์ด
///   (เดิมทุกคอลัมน์กว้างตามเนื้อหาในตารางเลื่อนแนวนอน ปุ่ม "ตรวจ" จึงถูกตัดที่จอ 1440)
///
/// ลำดับต้องตรงกับ [evidenceReviewCells]
List<DataColumn> evidenceReviewColumns() => [
      DataColumn(label: TableColumnLabel('นิสิต'), columnWidth: const FlexColumnWidth(2.2)),
      DataColumn(label: TableColumnLabel('กิจกรรม'), columnWidth: const FlexColumnWidth(2.6)),
      DataColumn(
        label: TableColumnLabel('ส่งเมื่อ'),
        columnWidth: _evidenceFixedColumn(kThaiDateCellWidth),
      ),
      DataColumn(label: TableColumnLabel('ผล OCR'), columnWidth: const FlexColumnWidth(2.4)),
      DataColumn(
        label: TableColumnLabel('สถานะ'),
        columnWidth: _evidenceFixedColumn(kEvidenceStatusCellWidth),
      ),
      DataColumn(
        label: TableColumnLabel('จัดการ'),
        columnWidth: _evidenceFixedColumn(EvidenceReviewButton.width, last: true),
      ),
    ];

/// เซลล์ของแถวคิวตรวจหลักฐาน เรียงตาม [evidenceReviewColumns]
List<DataCell> evidenceReviewCells(
  Participation p, {
  required VoidCallback onReview,
  TextStyle? mutedStyle,
}) =>
    [
      // คอลัมน์ flex — ตารางกำหนดขอบให้แล้ว TruncatedCell จึงไม่จำกัดความกว้างเอง
      DataCell(TruncatedCell(evidenceStudentLabel(p), maxWidth: double.infinity)),
      DataCell(TruncatedCell(evidenceActivityLabel(p), maxWidth: double.infinity, style: mutedStyle)),
      DataCell(EvidenceUploadedCell(p, style: mutedStyle)),
      DataCell(EvidenceOcrCell(p)),
      DataCell(SizedBox(
        width: kEvidenceStatusCellWidth,
        child: Align(
          alignment: Alignment.centerLeft,
          child: StatusChip.evidence(p.evidenceStatus, dense: true, shrink: true),
        ),
      )),
      DataCell(EvidenceReviewButton(onPressed: onReview)),
    ];

/// ตารางคิวตรวจหลักฐาน (จอกว้าง) — กว้างเท่าที่ได้รับพอดี ไม่มีการเลื่อนแนวนอน
class EvidenceReviewTable extends StatelessWidget {
  const EvidenceReviewTable({super.key, required this.items, required this.onReview});

  final List<Participation> items;
  final ValueChanged<Participation> onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: AppColors.sub);
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        child: DataTable(
          columnSpacing: kEvidenceColumnSpacing,
          horizontalMargin: kEvidenceTableMargin,
          dataRowMinHeight: kEvidenceRowHeight,
          dataRowMaxHeight: kEvidenceRowHeight,
          columns: evidenceReviewColumns(),
          rows: [
            for (final p in items)
              DataRow(
                color: appRowColor(theme.colorScheme),
                cells: evidenceReviewCells(p, onReview: () => onReview(p), mutedStyle: muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// คิวตรวจหลักฐานแบบการ์ด (จอแคบ) — กดทั้งการ์ดเพื่อเปิดหน้าตรวจ
class EvidenceReviewCards extends StatelessWidget {
  const EvidenceReviewCards({super.key, required this.items, required this.onReview});

  final List<Participation> items;
  final ValueChanged<Participation> onReview;

  @override
  Widget build(BuildContext context) => ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final p = items[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              onTap: () => onReview(p),
              title: Text(evidenceStudentLabel(p)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(evidenceActivityLabel(p)),
                    EvidenceOcrCell(p, stacked: false),
                    StatusChip.evidence(p.evidenceStatus, dense: true, shrink: true),
                  ],
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      );
}

/// วันที่ส่ง (บรรทัดบน) + เวลา (บรรทัดล่าง จาง) กว้างคงที่ — เต็ม ๆ อยู่ใน tooltip
///
/// รูปแบบบรรทัดเดียว "15 ก.ย. 2569 20:32" กินที่จนดันปุ่ม "ตรวจ" ล้นการ์ด
class EvidenceUploadedCell extends StatelessWidget {
  const EvidenceUploadedCell(this.participation, {super.key, this.style});

  final Participation participation;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final uploaded = participation.evidenceUploadedAt;
    if (uploaded == null) {
      return SizedBox(width: kThaiDateCellWidth, child: Text('-', style: style));
    }
    // backend เก็บ utcnow แบบไม่มีโซนเวลา — .toLocal() เฉย ๆ ไม่แปลงให้ จะเพี้ยน 7 ชม.
    final local = serverTimeToLocal(uploaded);
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')} น.';
    return Tooltip(
      message: '${formatThaiDate(local)} $time',
      child: SizedBox(
        width: kThaiDateCellWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatThaiDate(local), maxLines: 1, softWrap: false, style: style),
            Text(
              time,
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// ผล OCR + ป้ายประเภทหลักฐาน (เฉพาะภาพถ่าย/อื่น ๆ ที่ต้องตรวจด้วยตา) + ป้ายไฟล์ซ้ำในตัวผล OCR
///
/// ทุกป้ายหดตามพื้นที่แล้วตัด … — ป้ายซ้ำ ("⚠️ ภาพคล้ายกันมาก · นิสิตคนอื่น") ยาวพอจะดัน
/// ตารางให้ล้นได้ ตัวเต็มพร้อมคะแนนอยู่ใน tooltip
class EvidenceOcrCell extends StatelessWidget {
  const EvidenceOcrCell(this.participation, {super.key, this.stacked = true});

  final Participation participation;

  /// ตาราง: ป้ายซ้อนแนวตั้งในคอลัมน์ · การ์ดจอแคบ: เรียงต่อกันแบบ Wrap
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final p = participation;
    final status = _status();
    // เกียรติบัตรไม่ต้องมีป้าย — ภาพถ่าย/หลักฐานอื่นไม่ถูกอนุมัติอัตโนมัติ บอกเหตุผลไว้ข้างผล OCR
    if (!evidenceKindNeedsHumanReview(p.evidenceKind)) return status;
    final kind = StatusChip.evidenceKind(p.evidenceKind, dense: true, compact: true, shrink: true);
    if (!stacked) {
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [status, kind],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [status, const SizedBox(height: 4), kind],
    );
  }

  Widget _status() {
    final p = participation;
    if (!p.hasOcr || p.ocrDecision == null) {
      return const Text(
        'ยังไม่ประมวลผล',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.muted),
      );
    }
    final label = ocrDecisionLabel(
      p.ocrDecision!,
      duplicateReason: p.ocrDuplicateReason,
      matchKind: p.ocrMatchKind,
    );
    return Tooltip(
      message: '$label\n'
          'ความตรง ${asPercent(p.ocrMatchScore ?? 0)} · '
          'ความมั่นใจ OCR ${asPercent(p.ocrConfidence ?? 0)}'
          '${p.ocrDecision == 'flagged' ? ' · กด "ตรวจ" เพื่อดูว่าซ้ำกับใบไหน' : ''}',
      child: StatusChip.ocr(
        p.ocrDecision!,
        duplicateReason: p.ocrDuplicateReason,
        matchKind: p.ocrMatchKind,
        dense: true,
        shrink: true,
      ),
    );
  }
}

/// ปุ่ม "ตรวจ" กว้าง/สูงคงที่ — คอลัมน์สุดท้ายของตารางใช้ความกว้างนี้ ปุ่มจึงไม่หลุดขอบ
class EvidenceReviewButton extends StatelessWidget {
  const EvidenceReviewButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const double width = 88;
  static const double height = 32;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: FilledButton.tonalIcon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            minimumSize: const Size(width, height),
            maximumSize: const Size(width, height),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.fact_check_outlined, size: 16),
          label: const Text('ตรวจ', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
        ),
      );
}
