import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/criteria_set.dart';
import '../models/hour_category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../utils/format.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/app_sticky_table.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/requirement_picker.dart';
import '../widgets/search_field.dart';
import '../widgets/status_chip.dart';
import '../widgets/subcategory_dropdown.dart';
import 'activity_import_dialog.dart';
import 'app_shell.dart';
import 'activity_participants_screen.dart';
import 'checkin_qr_screen.dart';

const _activityTypes = ['จิตอาสา', 'กีฬา', 'วิชาการ', 'ศิลปวัฒนธรรม', 'อบรม/สัมมนา'];

String _trimHours(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toString();

/// ข้อความเดียวกับที่ backend ตอบ (400) เมื่อกันกิจกรรมย้อนหลัง — ฝั่ง UI กันเอง
/// ก่อนยิง API ด้วย จะได้ไม่ต้องรอ round-trip กว่าจะรู้ว่าเลือกวันไม่ได้
const kBackdatedActivityMessage = 'ไม่สามารถตั้งวันเวลากิจกรรมเป็นอดีตได้';

/// วันแรกที่เลือกเป็นวันจัดกิจกรรมได้ = วันนี้ (ตัดเวลาออก ให้เลือกวันนี้ได้ทั้งวัน)
///
/// รับ [now] เข้ามาได้เพื่อให้เทสต์ตรึงเวลาได้ ไม่ต้องพึ่งนาฬิกาเครื่องที่รันเทสต์
DateTime activityFirstSelectableDate([DateTime? now]) {
  final today = now ?? DateTime.now();
  return DateTime(today.year, today.month, today.day);
}

/// [startAt] ตกวันก่อนวันนี้หรือไม่ — เทียบระดับวันให้ตรงกับกฎฝั่ง backend
bool isBackdatedActivity(DateTime startAt, [DateTime? now]) =>
    startAt.isBefore(activityFirstSelectableDate(now));

/// error ที่ควรไปโผล่ใต้ช่อง "วันเวลาเริ่มกิจกรรม" แทนกล่อง error รวมท้ายฟอร์ม
/// — ผู้ใช้จะได้เห็นว่าปัญหาอยู่ที่ช่องไหน ไม่ต้องไล่หาเอง
bool isActivityDateError(String message) => message.contains('วันเวลากิจกรรมเป็นอดีต');

/// กด "ลบ" กิจกรรมนี้แล้วจะกลายเป็นการ "ซ่อน" แทนการลบจริงหรือไม่
///
/// กติกาเดียวกับ backend: มีผู้เข้าร่วมผูกอยู่ = ลบทิ้งไม่ได้ เพราะจะลากชั่วโมงที่
/// นิสิตได้ไปแล้วหายตามไปด้วย — UI ต้องตัดสินให้ตรงกัน ไม่งั้นคำเตือนจะโกหกผู้ใช้
bool activityWillBeHiddenOnDelete(Activity a) => a.participantCount > 0;

/// สิ่งที่กิจกรรมนับชั่วโมงให้ ในรูปสั้น ๆ พอใส่ช่องตารางได้
///
/// กิจกรรมที่ผูกรายการเกณฑ์ไว้แสดงชื่อรายการ (เกินหนึ่งรายการต่อท้ายว่า +n) ส่วนกิจกรรม
/// โครงเดิมที่มีแต่หมวดย่อยยังแสดงเป็น "หมวดแม่ › หมวดย่อย" เหมือนเดิม — ไม่งั้นกิจกรรม
/// ที่สร้างด้วยชุดเกณฑ์ใหม่จะขึ้นว่า "-" ทั้งที่ผูกเกณฑ์ไว้ครบ
String activityCriteriaLabel(
  List<HourCategory> categories,
  List<CriteriaSet> criteriaSets,
  Activity activity,
) {
  if (activity.requirementIds.isEmpty) {
    return subcategoryPath(categories, activity.subcategoryId);
  }
  final byId = requirementsById(criteriaSets);
  final names = [
    for (final id in activity.requirementIds)
      if (byId[id] != null) byId[id]!.name,
  ];
  if (names.isEmpty) return '${activity.requirementIds.length} รายการเกณฑ์';
  return names.length == 1 ? names.first : '${names.first} +${names.length - 1}';
}

/// กิจกรรมนี้มีปุ่ม "อนุมัติ" ให้คนที่กำลังดูอยู่ไหม
///
/// อนุมัติได้เฉพาะ admin (backend ตอบ 403 ให้ staff อยู่แล้ว — ฝั่ง UI ไม่โชว์ปุ่มที่
/// กดแล้วเด้ง error แน่ ๆ) และเฉพาะกิจกรรมที่ยังไม่อนุมัติ · staff ยังเห็น *ชิปสถานะ*
/// ได้ตามปกติ แค่กดเองไม่ได้
bool canApproveActivity(String approvalStatus, {required bool isAdmin}) =>
    isAdmin && approvalStatus != 'approved';

/// ปุ่มจัดการที่แถวกิจกรรมหนึ่งแถวมีได้
enum ActivityAction { unhide, approve, checkinQr, participants, edit, delete }

/// ปุ่มจัดการของกิจกรรมนี้ ตามลำดับที่แสดง (ตัวแรก = ปุ่มหลักที่ยังโชว์ในโหมดย่อ)
///
/// คู่ที่ไม่มีวันขึ้นพร้อมกัน: อนุมัติ ↔ QR (QR ต้องอนุมัติแล้ว) และ เลิกซ่อน ↔ ลบ
/// (ที่ซ่อนอยู่ไม่มีปุ่มลบ) — แถวหนึ่งจึงมีไม่เกิน [kActivityActionSlots] ปุ่มเสมอ
List<ActivityAction> activityActionsFor(Activity a, {required bool isAdmin}) => [
      if (a.isHidden) ActivityAction.unhide,
      if (canApproveActivity(a.approvalStatus, isAdmin: isAdmin)) ActivityAction.approve,
      // แสดงเฉพาะกิจกรรมที่อนุมัติแล้วและยังไม่ถูกซ่อน — สองกรณีนี้สแกนไม่ผ่านอยู่ดี
      // (backend ตอบ "กิจกรรมนี้ยังไม่เปิดให้เช็กอิน") การโชว์ QR จึงมีแต่ทำให้เข้าใจผิด
      if (a.approvalStatus == 'approved' && !a.isHidden) ActivityAction.checkinQr,
      ActivityAction.participants,
      ActivityAction.edit,
      // ที่ซ่อนอยู่แล้วไม่ต้องมีปุ่มลบ — กดไปก็ได้ผลเดิม แต่ชวนให้เข้าใจผิดว่าลบได้
      if (!a.isHidden) ActivityAction.delete,
    ];

/// จำนวนปุ่มสูงสุดที่แถวเดียวมีได้ — ใช้กำหนดความกว้างคอลัมน์ "จัดการ" ให้คงที่
const kActivityActionSlots = 4;

/// ตารางแคบกว่านี้ ยุบปุ่มรองเข้าเมนู ⋮ — ต่ำกว่านี้ฝั่งตรึงจะกินจอเกินครึ่ง
/// จนคอลัมน์ข้อมูลที่เลื่อนได้เหลือแทบมองไม่เห็น
const kActivityActionsCompactBelow = 960.0;

bool activityActionsCompact(double tableWidth) => tableWidth < kActivityActionsCompactBelow;

/// คอลัมน์ฝั่งซ้ายของตารางกิจกรรม — ส่วนที่เลื่อนแนวนอนได้เมื่อจอไม่พอ
///
/// "วันเวลา" อยู่ถัดจากชื่อเสมอ: ฝั่งเลื่อนได้กว้างราว 1,270px แต่จอ 1440 ให้ที่แค่ ~800px
/// คอลัมน์ท้าย ๆ จึงจมใต้ฝั่งตรึงจนกว่าจะเลื่อน เดิมวันเวลาอยู่เกือบท้ายเลยเห็นแค่
/// "1 ก.พ. 25" — ชื่อ+วันคือสิ่งที่ใช้ระบุกิจกรรม ต้องเห็นโดยไม่ต้องเลื่อน
List<DataColumn> activityScrollColumns() => const [
      DataColumn(label: Text('ชื่อกิจกรรม')),
      DataColumn(label: Text('วันเวลา')),
      DataColumn(label: Text('ประเภท')),
      DataColumn(label: Text('หมวดชั่วโมง')),
      DataColumn(label: Text('ชั่วโมง'), numeric: true),
      DataColumn(label: Text('บังคับ')),
      DataColumn(label: Text('รับสูงสุด'), numeric: true),
      DataColumn(label: Text('สถานที่')),
    ];

/// คอลัมน์ฝั่งขวาที่ถูกตรึงไว้ให้เห็นเสมอ
///
/// "สถานะอนุมัติ" กับปุ่มจัดการคือสองสิ่งที่ผู้ดูแลต้องใช้ทุกแถว ถ้าปล่อยให้เลื่อนหลุด
/// ออกนอกจอไปกับคอลัมน์อื่น ต้องลากตารางไปขวาทุกครั้งที่อยากกดอะไรสักปุ่ม
///
/// นิสิตเห็นเฉพาะกิจกรรมที่อนุมัติแล้ว (backend กรองให้) คอลัมน์สถานะจึงเป็นค่าเดียวกัน
/// ทุกแถว ไม่ให้ข้อมูลอะไร — ซ่อนเฉพาะมุมมองนิสิต
List<DataColumn> activityPinnedColumns(bool isStudent) => [
      if (!isStudent) const DataColumn(label: Text('สถานะอนุมัติ')),
      const DataColumn(label: Text('จัดการ')),
    ];

/// คอลัมน์ทั้งตารางตามลำดับซ้าย→ขวา (ฝั่งเลื่อน + ฝั่งตรึง)
List<DataColumn> activityTableColumns(bool isStudent) => [
      ...activityScrollColumns(),
      ...activityPinnedColumns(isStudent),
    ];

class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key});

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  static const int _limit = 10;

  List<Activity> _activities = [];
  List<HourCategory> _categories = [];
  List<CriteriaSet> _criteriaSets = [];
  int _total = 0;
  int _skip = 0;
  bool _loading = false;
  String? _error;
  String _search = '';
  String? _typeFilter;
  int _requestId = 0;

  /// มุมมองนิสิตเริ่มต้นที่ "เฉพาะกิจกรรมที่ยังไม่ถึงวันจัด" — เปิดอันนี้เพื่อดูย้อนหลัง
  /// (ฝั่ง staff/admin ยังเห็นทุกกิจกรรมเรียงล่าสุดก่อนเหมือนเดิม)
  bool _includePast = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCategories();
    _loadCriteriaSets();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService.fetchList('/hour-categories', HourCategory.fromJson);
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
      // non-fatal: table falls back to "-" and the form dialog shows an empty picker
    }
  }

  /// ชุดเกณฑ์สำหรับช่องเลือกรายการเกณฑ์ในฟอร์ม — ล้มก็ยังสร้างกิจกรรมด้วยหมวดเดิมได้
  Future<void> _loadCriteriaSets() async {
    try {
      final sets = await ApiService.fetchList('/criteria-sets', CriteriaSet.fromJson);
      if (mounted) setState(() => _criteriaSets = sets);
    } catch (_) {
      // non-fatal: ฟอร์มจะขึ้นหมายเหตุว่ายังไม่มีชุดเกณฑ์ และบังคับเลือกหมวดชั่วโมงเดิมแทน
    }
  }

  void _onSearch(String value) {
    _search = value;
    _skip = 0;
    _load();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, String>{'skip': '$_skip', 'limit': '$_limit'};
      if (_search.isNotEmpty) query['search'] = _search;
      if (_typeFilter != null) query['activity_type'] = _typeFilter!;
      // นิสิตเปิดหน้ามาต้องเจอกิจกรรมที่ยังสมัคร/เข้าร่วมทันได้ก่อน ไม่ใช่ของอีกปีหน้า
      // ที่บังเอิญวันจัดไกลสุด (ลำดับปกติเรียงวันจัดจากใหม่ไปเก่า)
      if (authService.role == 'student' && !_includePast) query['upcoming'] = 'true';
      final page = await ApiService.fetchPage('/activities', Activity.fromJson, query: query);
      // ผลลัพธ์เก่าที่มาช้ากว่าคำค้นหาล่าสุด ต้องไม่ทับของใหม่
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _activities = page.items;
        _total = page.total;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Activity? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ActivityFormDialog(
        existing: existing,
        categories: _categories,
        criteriaSets: _criteriaSets,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Activity a) async {
    // มีคนเข้าร่วมแล้ว backend จะ "ซ่อน" ให้แทนการลบจริง — คำเตือนต้องตรงกับสิ่งที่
    // จะเกิดขึ้นจริง ไม่งั้นผู้ใช้จะกลัวว่าชั่วโมงของนิสิตหายทั้งที่ไม่หาย
    final confirmed = activityWillBeHiddenOnDelete(a)
        ? await confirmAction(
            context,
            title: 'ยืนยันการซ่อนกิจกรรม',
            message: 'ซ่อน "${a.name}" ใช่หรือไม่?',
            detail: 'กิจกรรมนี้มีผู้เข้าร่วมแล้ว ${a.participantCount} คน จึงลบทิ้งไม่ได้ '
                'ระบบจะซ่อนให้แทน — นิสิตจะไม่เห็นและสมัครใหม่ไม่ได้ '
                'แต่ประวัติการเข้าร่วมและชั่วโมงเดิมยังอยู่ครบ กด "เลิกซ่อน" เพื่อกู้คืนได้',
            confirmLabel: 'ซ่อน',
            icon: Icons.visibility_off_outlined,
            destructive: true,
          )
        : await confirmDelete(context, a.name);
    if (confirmed != true) return;
    try {
      await ApiService.delete('/activities/${a.id}');
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  Future<void> _unhide(Activity a) async {
    try {
      await ApiService.patch('/activities/${a.id}/unhide', Activity.fromJson);
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  Future<void> _approve(Activity a) async {
    try {
      await ApiService.patch('/activities/${a.id}/approve', Activity.fromJson);
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  /// เปิด dialog นำเข้าแผนกิจกรรม แล้วโหลดรายการใหม่ถ้ามีกิจกรรมถูกสร้างจริง
  Future<void> _openImportDialog() async {
    final imported = await showDialog<bool>(
      context: context,
      builder: (_) => const ActivityImportDialog(),
    );
    if (imported == true) {
      _skip = 0;
      _load();
    }
  }

  void _openParticipants(Activity a) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ActivityParticipantsScreen(activity: a)),
    );
  }

  void _onAction(Activity a, ActivityAction action) {
    switch (action) {
      case ActivityAction.unhide:
        _unhide(a);
      case ActivityAction.approve:
        _approve(a);
      case ActivityAction.checkinQr:
        _openCheckinQr(a);
      case ActivityAction.participants:
        _openParticipants(a);
      case ActivityAction.edit:
        _openForm(existing: a);
      case ActivityAction.delete:
        _delete(a);
    }
  }

  void _openCheckinQr(Activity a) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckinQrScreen(activityId: a.id!, activityName: a.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = authService.canWrite;
    final isStudent = authService.role == 'student';
    return AdminPage(
      activeId: 'activities',
      title: isStudent ? 'กิจกรรม' : 'จัดการกิจกรรม',
      subtitle: '$_total กิจกรรม',
      actions: [
        if (canWrite)
          // นำเข้าทั้งภาคเรียนทีเดียว (ข้อ 6.7) — อยู่คู่กับปุ่มสร้างทีละอัน
          OutlinedButton.icon(
            onPressed: _openImportDialog,
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('นำเข้าแผนกิจกรรม'),
          ),
        if (canWrite)
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('สร้างกิจกรรม'),
          ),
      ],
      filters: [
        DebouncedSearchField(label: 'ค้นหาชื่อกิจกรรม', onSearch: _onSearch),
        DropdownButton<String?>(
          value: _typeFilter,
          hint: const Text('ประเภททั้งหมด'),
          items: [
            const DropdownMenuItem(value: null, child: Text('ประเภททั้งหมด')),
            ..._activityTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))),
          ],
          onChanged: (v) {
            setState(() => _typeFilter = v);
            _skip = 0;
            _load();
          },
        ),
        if (isStudent)
          FilterChip(
            label: const Text('รวมกิจกรรมที่จัดไปแล้ว'),
            selected: _includePast,
            onSelected: (value) {
              setState(() => _includePast = value);
              _skip = 0;
              _load();
            },
          ),
        AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: _load),
      ],
      // แถบบางบอกว่ากำลังโหลดผลค้นหา โดยไม่ต้องล้างตารางเดิมทิ้ง
      busy: _loading && _activities.isNotEmpty,
      footer: _error == null && _activities.isNotEmpty ? _buildPagination() : null,
      child: _loading && _activities.isEmpty
          ? const LoadingState(message: 'กำลังโหลดกิจกรรม...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _activities.isEmpty
                  ? _emptyState(canWrite)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return constraints.maxWidth > 800
                            ? TableCard(
                                child: _buildTable(
                                  canWrite,
                                  isStudent,
                                  compact: activityActionsCompact(constraints.maxWidth),
                                ),
                              )
                            : _buildList(canWrite, isStudent);
                      },
                    ),
    );
  }

  /// ไม่มีข้อมูล: แยกกรณี "ค้นหาไม่เจอ" / "ยังไม่มีอันที่กำลังจะถึง" / "ไม่มีเลย"
  Widget _emptyState(bool canWrite) {
    if (_search.isNotEmpty || _typeFilter != null) return EmptyState.noResults();
    // นิสิตที่ยังไม่ได้เปิดดูย้อนหลัง อาจมีกิจกรรมในระบบอยู่ แค่จัดไปหมดแล้ว
    if (!canWrite && !_includePast) {
      return const EmptyState(
        icon: Icons.event_busy,
        title: 'ยังไม่มีกิจกรรมที่กำลังจะถึง',
        message: 'เปิด "รวมกิจกรรมที่จัดไปแล้ว" เพื่อดูย้อนหลัง '
            'หรือรอเจ้าหน้าที่เพิ่มกิจกรรมใหม่',
      );
    }
    return EmptyState(
      icon: Icons.event_busy,
      title: 'ยังไม่มีกิจกรรม',
      message: canWrite
          ? 'กดปุ่ม "สร้างกิจกรรม" ด้านบนเพื่อเพิ่มกิจกรรมแรก'
          : 'เมื่อเจ้าหน้าที่เพิ่มกิจกรรม รายการจะแสดงที่นี่',
    );
  }

  /// ช่องที่เป็นข้อมูลประกอบ ใช้สีจางกว่าชื่อกิจกรรม เพื่อให้กวาดตาหาชื่อได้เร็ว
  TextStyle? _mutedCell(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.sub);

  Widget _buildTable(bool canWrite, bool isStudent, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    return AppStickyTable(
      scrollableColumns: activityScrollColumns(),
      pinnedColumns: activityPinnedColumns(isStudent),
      rows: [
        for (final a in _activities)
          StickyRow(
            scrollable: [
              // ชื่อกิจกรรมยาวได้เป็นประโยค — ตัดแล้วบอกเต็มตอนชี้ ไม่ให้ดันคอลัมน์อื่นหลุดจอ
              DataCell(TruncatedCell(a.name, maxWidth: 220)),
              // วันเวลาไทย พ.ศ. — ตารางโชว์แค่วันที่ เวลาเต็มอยู่ใน tooltip · อยู่ถัดจากชื่อ
              // (ดู activityScrollColumns) และกว้างคงที่ (ดู ThaiDateCell)
              DataCell(ThaiDateCell(
                formatThaiDate(a.startAt),
                tooltip: formatThaiDateTime(a.startAt),
                style: _mutedCell(context),
              )),
              DataCell(TruncatedCell(a.activityType,
                  maxWidth: 110, style: _mutedCell(context))),
              DataCell(TruncatedCell(
                activityCriteriaLabel(_categories, _criteriaSets, a),
                maxWidth: 170,
                style: _mutedCell(context),
              )),
              DataCell(NarrowCell(Text(_trimHours(a.hours)), width: 36)),
              DataCell(NarrowCell(
                Tooltip(
                  message: a.isRequired ? 'กิจกรรมบังคับ' : 'ไม่บังคับ',
                  child: Icon(
                    a.isRequired ? Icons.check_circle : Icons.remove,
                    size: 18,
                    color: a.isRequired ? StatusPalette.approved.foreground : scheme.outline,
                  ),
                ),
                width: 32,
              )),
              DataCell(NarrowCell(Text('${a.maxParticipants}'), width: 40)),
              DataCell(TruncatedCell(a.location,
                  maxWidth: 140, style: _mutedCell(context))),
            ],
            pinned: [
              if (!isStudent) DataCell(ActivityApprovalChips(activity: a)),
              DataCell(canWrite
                  ? ActivityActionButtons(
                      activity: a,
                      isAdmin: authService.isAdmin,
                      compact: compact,
                      onAction: (action) => _onAction(a, action),
                    )
                  : const SizedBox.shrink()),
            ],
          ),
      ],
    );
  }

  Widget _buildList(bool canWrite, bool isStudent) {
    return ListView.builder(
      itemCount: _activities.length,
      itemBuilder: (context, index) {
        final a = _activities[index];
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: ListTile(
            onTap: canWrite ? () => _openParticipants(a) : null,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(a.name)),
                if (!isStudent) ...[
                  const SizedBox(width: 8),
                  ActivityApprovalChips(activity: a),
                ],
              ],
            ),
            subtitle: Text(
              '${a.activityType} • ได้ ${_trimHours(a.hours)} ชม. • ${formatThaiDateTime(a.startAt)}\n'
              '${a.location} • รับ ${a.maxParticipants} คน${a.isRequired ? " • บังคับ" : ""}',
            ),
            isThreeLine: true,
            // การ์ดบนจอแคบมีที่ให้ trailing น้อย — ใช้โหมดย่อ (ปุ่มหลัก + ⋮) เสมอ
            trailing: canWrite
                ? ActivityActionButtons(
                    activity: a,
                    isAdmin: authService.isAdmin,
                    compact: true,
                    onAction: (action) => _onAction(a, action),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildPagination() => PaginationBar(
        skip: _skip,
        limit: _limit,
        total: _total,
        onChanged: (skip) {
          setState(() => _skip = skip);
          _load();
        },
      );
}

/// ชิปสถานะฝั่ง staff/admin: สถานะอนุมัติ + "ซ่อนอยู่" ถ้าถูกซ่อนไว้
///
/// เป็น [Row] บรรทัดเดียว ไม่ใช่ [Wrap] ด้วยเหตุผลเดียวกับ [ActivityActionButtons]
class ActivityApprovalChips extends StatelessWidget {
  const ActivityApprovalChips({super.key, required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip.activityApproval(activity.approvalStatus, dense: true),
          if (activity.isHidden) ...[
            const SizedBox(width: AppSpacing.xs),
            const StatusChip(
              label: 'ซ่อนอยู่',
              palette: StatusPalette.neutral,
              icon: Icons.visibility_off_outlined,
              dense: true,
            ),
          ],
        ],
      );
}

/// ปุ่มจัดการของแถวกิจกรรม — บรรทัดเดียวเสมอ กว้างคงที่ทุกแถว
///
/// เดิมใช้ [Wrap] ซึ่ง intrinsic width ของมัน**ไม่นับ spacing** ตารางที่คำนวณความกว้าง
/// คอลัมน์จาก intrinsic width จึงให้ที่ขาดไปนิดเดียว ปุ่มสุดท้าย (ลบ) เลยตกบรรทัด
/// และเพราะแถวถูกล็อกความสูงไว้ บรรทัดที่ตกลงมาจึงวาดทับแถวถัดไป
///
/// * โหมดปกติ: วางได้ [kActivityActionSlots] ปุ่มในบรรทัดเดียว (แถวที่มีปุ่มน้อยกว่า
///   เว้นที่ว่างท้ายไว้ ความกว้างคอลัมน์จึงไม่กระโดดตามแถว)
/// * โหมดย่อ ([compact]): ปุ่มหลัก 1 ปุ่ม + เมนู ⋮ สำหรับที่เหลือ
class ActivityActionButtons extends StatelessWidget {
  const ActivityActionButtons({
    super.key,
    required this.activity,
    required this.isAdmin,
    required this.onAction,
    this.compact = false,
  });

  final Activity activity;
  final bool isAdmin;
  final bool compact;
  final ValueChanged<ActivityAction> onAction;

  static const double buttonSize = 32;
  static const double gap = AppSpacing.xs;

  /// ความกว้างคงที่ของกลุ่มปุ่ม — โหมดย่อ = ปุ่มหลัก + ⋮
  static double widthFor({required bool compact}) {
    final slots = compact ? 2 : kActivityActionSlots;
    return slots * buttonSize + (slots - 1) * gap;
  }

  static IconData iconOf(ActivityAction action) => switch (action) {
        ActivityAction.unhide => Icons.visibility,
        ActivityAction.approve => Icons.check_circle,
        ActivityAction.checkinQr => Icons.qr_code_2,
        ActivityAction.participants => Icons.groups,
        ActivityAction.edit => Icons.edit,
        ActivityAction.delete => Icons.delete,
      };

  String labelOf(ActivityAction action) => switch (action) {
        ActivityAction.unhide => 'เลิกซ่อน',
        ActivityAction.approve => 'อนุมัติกิจกรรม',
        ActivityAction.checkinQr => 'แสดง QR เช็กอิน',
        ActivityAction.participants => 'ดูผู้เข้าร่วม',
        ActivityAction.edit => 'แก้ไข',
        ActivityAction.delete =>
          activityWillBeHiddenOnDelete(activity) ? 'ซ่อน (มีผู้เข้าร่วมแล้ว ลบไม่ได้)' : 'ลบ',
      };

  Widget _button(ActivityAction action) => AppIconButton(
        icon: iconOf(action),
        size: buttonSize,
        danger: action == ActivityAction.delete,
        tooltip: labelOf(action),
        onPressed: () => onAction(action),
      );

  Widget _overflowMenu(List<ActivityAction> actions) => PopupMenuButton<ActivityAction>(
        tooltip: 'การจัดการเพิ่มเติม',
        padding: EdgeInsets.zero,
        onSelected: onAction,
        itemBuilder: (_) => [
          for (final action in actions)
            PopupMenuItem(
              value: action,
              child: Row(
                children: [
                  Icon(
                    iconOf(action),
                    size: 18,
                    color: action == ActivityAction.delete ? AppColors.danger : AppColors.sub,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    labelOf(action),
                    style: action == ActivityAction.delete
                        ? const TextStyle(color: AppColors.danger)
                        : null,
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          width: buttonSize,
          height: buttonSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: const Icon(Icons.more_vert, size: buttonSize * 0.5, color: AppColors.sub),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final actions = activityActionsFor(activity, isAdmin: isAdmin);
    final children = compact
        ? [
            _button(actions.first),
            if (actions.length > 1) _overflowMenu(actions.skip(1).toList()),
          ]
        : [for (final action in actions) _button(action)];

    return SizedBox(
      width: widthFor(compact: compact),
      height: buttonSize,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// ฟอร์มเพิ่ม/แก้ไขกิจกรรม — public เพื่อให้เทสต์ pump ตรง ๆ ได้ (หน้าเต็มต้องยิง
/// API จริง จึงเปิด dialog ผ่านหน้าจอในเทสต์ไม่ได้)
class ActivityFormDialog extends StatefulWidget {
  final Activity? existing;
  final List<HourCategory> categories;

  /// ชุดเกณฑ์ที่เลือกรายการได้ — ว่างได้ (ระบบที่ยังไม่ได้ seed เกณฑ์) แล้วฟอร์มจะ
  /// กลับไปบังคับเลือกหมวดชั่วโมงโครงเดิมแทน
  final List<CriteriaSet> criteriaSets;

  const ActivityFormDialog({
    super.key,
    this.existing,
    required this.categories,
    this.criteriaSets = const [],
  });

  @override
  State<ActivityFormDialog> createState() => _ActivityFormDialogState();
}

class _ActivityFormDialogState extends State<ActivityFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _maxParticipantsController;
  late final TextEditingController _locationController;
  late final TextEditingController _hoursController;
  String _activityType = _activityTypes.first;
  int? _subcategoryId;
  Set<int> _requirementIds = {};
  bool _isRequired = false;
  late DateTime _startAt;
  bool _saving = false;
  String? _error;

  /// error ของช่องวันเวลาโดยเฉพาะ (แสดงใต้ช่องนั้น ไม่ใช่กล่องรวมท้ายฟอร์ม)
  String? _dateError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _maxParticipantsController =
        TextEditingController(text: e != null ? '${e.maxParticipants}' : '50');
    _locationController = TextEditingController(text: e?.location ?? '');
    _hoursController = TextEditingController(
      text: e != null && e.hours > 0 ? _trimHours(e.hours) : '3',
    );
    _activityType = e?.activityType ?? _activityTypes.first;
    _requirementIds = {...?e?.requirementIds};
    // มีชุดเกณฑ์ให้เลือกแล้ว = ทางหลักคือรายการเกณฑ์ ไม่เดาหมวดชั่วโมงเดิมให้
    // (เดาไว้จะได้กิจกรรมที่ผูกหมวดของรุ่นเก่าติดมาโดยที่ผู้ใช้ไม่ได้ตั้งใจ)
    _subcategoryId = e?.subcategoryId ??
        (widget.criteriaSets.isEmpty &&
                widget.categories.isNotEmpty &&
                widget.categories.first.subcategories.isNotEmpty
            ? widget.categories.first.subcategories.first.id
            : null);
    _isRequired = e?.isRequired ?? false;
    _startAt = e?.startAt ?? DateTime.now().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _maxParticipantsController.dispose();
    _locationController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final today = activityFirstSelectableDate();
    final date = await showDatePicker(
      context: context,
      // กิจกรรมเดิมที่จัดไปแล้วมี _startAt เป็นอดีต ซึ่งใช้เป็น initialDate ไม่ได้
      // (ต้องไม่ก่อน firstDate) จึงเริ่มที่วันนี้แทน — แก้ field อื่นได้ตามปกติ
      // แต่ถ้าจะแตะวัน ต้องเลือกวันนี้ขึ้นไปเท่านั้น
      initialDate: _startAt.isBefore(today) ? today : _startAt,
      firstDate: today,
      lastDate: DateTime(today.year + 3, today.month, today.day),
    );
    if (date == null || !mounted) return;
    // พิมพ์เวลาอย่างเดียวแบบ 24 ชม. — `inputOnly` ตัดทั้งหน้าปัดนาฬิกาที่ลากเข็มยาก
    // และปุ่มสลับไปหน้าปัด ส่วน AM/PM ตัดด้วย alwaysUse24HourFormat
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startAt),
      initialEntryMode: TimePickerEntryMode.inputOnly,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _startAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _dateError = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // กติกาเดียวกับ backend: ต้องจัดหมวดอย่างน้อยหนึ่งทาง ไม่งั้นกิจกรรมนี้จะไม่นับ
    // ชั่วโมงให้ใครเลย
    if (_requirementIds.isEmpty && _subcategoryId == null) {
      setState(() => _error = 'กรุณาเลือกรายการเกณฑ์อย่างน้อยหนึ่งรายการ '
          'หรือเลือกหมวดชั่วโมงโครงเดิม');
      return;
    }
    final hours = double.tryParse(_hoursController.text.trim());
    if (hours == null || hours <= 0) {
      setState(() => _error = 'กรุณากรอกจำนวนชั่วโมงมากกว่า 0');
      return;
    }
    // กิจกรรมเก่าที่จัดไปแล้วยังแก้ field อื่นได้ — ห้ามเฉพาะการ "ย้ายวัน" ไปอดีต
    // (เงื่อนไขเดียวกับที่ backend บังคับ ไม่งั้นสองฝั่งจะตัดสินไม่ตรงกัน)
    final startChanged = widget.existing == null || widget.existing!.startAt != _startAt;
    if (startChanged && isBackdatedActivity(_startAt)) {
      setState(() => _dateError = kBackdatedActivityMessage);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _dateError = null;
    });
    final body = {
      'name': _nameController.text.trim(),
      'activity_type': _activityType,
      'subcategory_id': _subcategoryId,
      'requirement_ids': _requirementIds.toList()..sort(),
      'hours': hours,
      'is_required': _isRequired,
      'max_participants': int.parse(_maxParticipantsController.text.trim()),
      'start_at': _startAt.toIso8601String(),
      'location': _locationController.text.trim(),
    };
    try {
      if (widget.existing == null) {
        await ApiService.create('/activities', body, Activity.fromJson);
      } else {
        await ApiService.update('/activities/${widget.existing!.id}', body, Activity.fromJson);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final message = friendlyError(e);
      setState(() {
        if (isActivityDateError(message)) {
          _dateError = message;
          _error = null;
        } else {
          _error = message;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFormDialog(
      title: widget.existing == null ? 'เพิ่มกิจกรรม' : 'แก้ไขกิจกรรม',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'ชื่อกิจกรรม'),
          validator: requiredValidator,
        ),
        DropdownButtonFormField<String>(
          initialValue: _activityType,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'ประเภท'),
          items: _activityTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _activityType = v ?? _activityTypes.first),
        ),
        RequirementPicker(
          criteriaSets: widget.criteriaSets,
          selected: _requirementIds,
          onChanged: (ids) => setState(() {
            _requirementIds = ids;
            if (ids.isNotEmpty) _error = null;
          }),
        ),
        // E3: dropdown หมวดชั่วโมง — ชื่อสั้นในช่อง ชื่อเต็มในรายการ ไม่ล้นกรอบ
        // ไม่บังคับเมื่อเลือกรายการเกณฑ์แล้ว: มีไว้สำหรับนิสิตที่ยังไม่ผูกชุดเกณฑ์
        SubcategoryDropdown(
          categories: widget.categories,
          value: _subcategoryId,
          onChanged: (v) => setState(() => _subcategoryId = v),
          labelText: widget.criteriaSets.isEmpty
              ? 'หมวดชั่วโมง'
              : 'หมวดชั่วโมงโครงเดิม (ไม่บังคับ)',
          required: widget.criteriaSets.isEmpty,
        ),
        TextFormField(
          controller: _hoursController,
          decoration: const InputDecoration(
            labelText: 'ชั่วโมงที่ได้รับเมื่อเข้าร่วม',
            hintText: 'เช่น 4',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            final n = double.tryParse((v ?? '').trim());
            return (n == null || n <= 0) ? 'กรอกจำนวนชั่วโมงมากกว่า 0' : null;
          },
        ),
        TextFormField(
          controller: _maxParticipantsController,
          decoration: const InputDecoration(labelText: 'จำนวนที่รับ'),
          keyboardType: TextInputType.number,
          validator: (v) => int.tryParse(v ?? '') == null ? 'กรอกตัวเลข' : null,
        ),
        TextFormField(
          controller: _locationController,
          decoration: const InputDecoration(labelText: 'สถานที่'),
          validator: requiredValidator,
        ),
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'วันเวลาเริ่มกิจกรรม',
            // แสดงใต้ช่องนี้เลย ทั้งของที่ UI กันเองและ 400 ที่ backend ตอบกลับมา
            errorText: _dateError,
          ),
          child: InkWell(
            onTap: _pickDateTime,
            child: Row(
              children: [
                Expanded(child: Text(formatThaiDateTime(_startAt))),
                const Icon(Icons.calendar_today, size: 18),
              ],
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('กิจกรรมบังคับ'),
          subtitle: const Text('นิสิตทุกคนต้องเข้าร่วม'),
          value: _isRequired,
          onChanged: (v) => setState(() => _isRequired = v),
        ),
      ],
    );
  }
}
