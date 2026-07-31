import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/participation.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/api_error.dart';
import '../utils/format.dart';
import '../utils/ocr_status.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/evidence_actions.dart';
import '../widgets/status_chip.dart';
import 'ocr_review_screen.dart';

class ActivityParticipantsScreen extends StatefulWidget {
  final Activity activity;
  const ActivityParticipantsScreen({super.key, required this.activity});

  @override
  State<ActivityParticipantsScreen> createState() => _ActivityParticipantsScreenState();
}

class _ActivityParticipantsScreenState extends State<ActivityParticipantsScreen> {
  List<Participation> _participations = [];
  Map<int, Student> _studentsById = {};
  bool _loading = false;
  bool _processingBatch = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final students = await ApiService.fetchAll('/students', Student.fromJson);
      // The OCR summary (decision/scores) is folded into each participation, so
      // no per-row OCR request is needed.
      final participations = await ApiService.fetchList(
        '/activities/${widget.activity.id}/participations',
        Participation.fromJson,
      );

      setState(() {
        _studentsById = {for (final s in students) s.id!: s};
        _participations = participations;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _processOcr(Participation p) async {
    try {
      await ApiService.processEvidence(p.id!);
      await _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  Future<void> _openReview(Participation p) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OcrReviewScreen(
          participationId: p.id!,
          studentName: _studentLabel(p.studentId),
        ),
      ),
    );
    // Always refresh on return so the list reflects any approve/reject/reprocess,
    // regardless of how the user navigated back (arrow, gesture, browser back).
    if (mounted) _load();
  }

  /// Admin batch: run OCR on every row that has evidence but no result yet.
  Future<void> _processAllPending() async {
    final pending = _participations
        .where((p) => p.hasEvidence && !p.hasOcr)
        .toList();
    if (pending.isEmpty) {
      showInfoSnackbar(context, 'ไม่มีหลักฐานที่ยังไม่ได้ประมวลผล');
      return;
    }
    setState(() => _processingBatch = true);
    try {
      for (final p in pending) {
        try {
          await ApiService.processEvidence(p.id!);
        } catch (_) {
          // keep going even if one fails
        }
      }
      await _load();
    } finally {
      if (mounted) setState(() => _processingBatch = false);
    }
  }

  Future<void> _setEvidence(Participation p, String status) async {
    try {
      await ApiService.update(
        '/participations/${p.id}',
        {'evidence_status': status},
        Participation.fromJson,
      );
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  String _studentLabel(int studentId) => _studentsById[studentId]?.fullName ?? '#$studentId';

  String _trimHours(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toString();

  Widget _activityHeader() {
    final a = widget.activity;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        '${a.activityType} • ได้ ${_trimHours(a.hours)} ชม. เมื่อหลักฐานผ่านการอนุมัติ',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ผู้เข้าร่วม: ${widget.activity.name}'),
        actions: [
          if (authService.isAdmin)
            _processingBatch
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Icons.document_scanner),
                    tooltip: 'ประมวลผล OCR ทั้งหมดที่ค้าง',
                    onPressed: _processAllPending,
                  ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _participations.isEmpty
                  ? Column(children: [
                      _activityHeader(),
                      const Expanded(
                        child: EmptyState(
                          icon: Icons.group_off_outlined,
                          title: 'ยังไม่มีผู้เข้าร่วม',
                          message: 'เมื่อมีนิสิตสมัครกิจกรรมนี้ รายชื่อจะแสดงที่นี่',
                        ),
                      ),
                    ])
                  : Column(children: [
                      _activityHeader(),
                      Expanded(
                        child: ListView.builder(
                      itemCount: _participations.length,
                      itemBuilder: (context, index) {
                        final p = _participations[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ListTile(
                            title: Text(_studentLabel(p.studentId)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'เช็คอิน: ${p.checkInTime?.toString() ?? "-"}'
                                  ' • ชั่วโมง: ${p.evidenceStatus == "approved" ? formatHours(p.hoursEarned) : "–"}'
                                  '${p.hasEvidence ? "" : " • ยังไม่มีหลักฐาน"}',
                                ),
                                if (p.hasOcr && p.ocrDecision != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        StatusChip.ocr(p.ocrDecision!, dense: true),
                                        Text(
                                          'ตรง ${asPercent(p.ocrMatchScore ?? 0)} • มั่นใจ ${asPercent(p.ocrConfidence ?? 0)}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  )
                                else if (p.hasEvidence)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('ยังไม่ได้ประมวลผล OCR',
                                        style: Theme.of(context).textTheme.bodySmall),
                                  ),
                              ],
                            ),
                            isThreeLine: false,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StatusChip.evidence(p.evidenceStatus, dense: true),
                                // Review OCR + evidence side-by-side (also where staff override lives)
                                if (p.hasEvidence)
                                  IconButton(
                                    icon: const Icon(Icons.fact_check, color: Colors.indigo),
                                    tooltip: 'ตรวจหลักฐาน + OCR',
                                    onPressed: () => _openReview(p),
                                  ),
                                if (p.hasEvidence && !p.hasOcr)
                                  IconButton(
                                    icon: const Icon(Icons.document_scanner, color: Colors.teal),
                                    tooltip: 'ประมวลผล OCR',
                                    onPressed: () => _processOcr(p),
                                  ),
                                // B3: only show the view button when a file actually exists
                                if (p.hasEvidence)
                                  IconButton(
                                    icon: const Icon(Icons.image_search, color: Colors.blueGrey),
                                    tooltip: 'ดูหลักฐาน',
                                    onPressed: () => viewEvidenceFlow(context, p.id!),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.check_circle, color: Colors.green),
                                  // A3: cannot approve without evidence
                                  tooltip: p.hasEvidence ? 'อนุมัติ' : 'ต้องมีหลักฐานก่อนอนุมัติ',
                                  onPressed: p.hasEvidence
                                      ? () => _setEvidence(p, 'approved')
                                      : null,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.red),
                                  tooltip: 'ไม่อนุมัติ',
                                  onPressed: () => _setEvidence(p, 'rejected'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                        ),
                      ),
                    ]),
    );
  }
}
