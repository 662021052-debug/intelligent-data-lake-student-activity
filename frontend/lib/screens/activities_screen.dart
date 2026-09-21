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
import '../widgets/app_table_cells.dart';
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

/// ตัวเลือกประเภทในฟอร์ม = 5 ค่าเดิมที่ backend รับ + ค่าเดิมของกิจกรรมที่ไม่อยู่ในรายการ
///
/// กิจกรรมเก่า/ที่นำเข้าจากไฟล์อาจมีประเภทอื่น (backend รับ string อะไรก็ได้) — ต้องยังเห็น
/// และเลือกค้างไว้ ไม่งั้นแค่เปิดแก้ชื่อก็ทำประเภทเดิมหายแบบเงียบ ๆ
List<String> activityTypeChoices(String? existingType) => [
      ..._activityTypes,
      if (existingType != null && existingType.isNotEmpty && !_activityTypes.contains(existingType))
        existingType,
    ];

/// body ที่ฟอร์มกิจกรรมส่งไป POST/PUT `/activities` — แยกออกมาเพื่อให้เทสต์ยืนยันได้ว่า
/// การจัดหน้าฟอร์มใหม่ไม่ได้เปลี่ยนสิ่งที่ backend รับ
Map<String, dynamic> activityFormPayload({
  required String name,
  required String activityType,
  required int? subcategoryId,
  required Set<int> requirementIds,
  required double hours,
  required bool isRequired,
  required int maxParticipants,
  required DateTime startAt,
  DateTime? endAt,
  required String location,
}) =>
    {
      'name': name,
      'activity_type': activityType,
      'subcategory_id': subcategoryId,
      'requirement_ids': requirementIds.toList()..sort(),
      'hours': hours,
      'is_required': isRequired,
      'max_participants': maxParticipants,
      'start_at': startAt.toIso8601String(),
      // ส่งเสมอแม้ว่าง (null) — โหมดแก้ไขใช้ null นี้ล้างเวลาสิ้นสุดเดิมที่ผู้ใช้กดลบออก
      'end_at': endAt?.toIso8601String(),
      'location': location,
    };

/// ข้อความเตือนเมื่อเวลาสิ้นสุดไม่อยู่หลังเวลาเริ่ม — ถ้อยคำเดียวกับที่ backend ตอบ (422)
const kEndBeforeStartMessage = 'เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่มกิจกรรม';

/// เวลาสิ้นสุดที่กรอกไว้ผิดไหม (ว่าง = ไม่ผิด) — ตัดสินตรงกับ backend: ต้อง "หลัง" เท่านั้น
/// เท่ากันก็ไม่ผ่าน
bool isEndBeforeStart(DateTime startAt, DateTime? endAt) =>
    endAt != null && !endAt.isAfter(startAt);

/// ชื่อรายการเกณฑ์ + เส้นทาง "ชุดเกณฑ์ › กลุ่ม" ของทุกรายการ — ใช้ทำ pill ในฟอร์มกิจกรรม
Map<int, ({String name, String path})> requirementPaths(List<CriteriaSet> criteriaSets) => {
      for (final set in criteriaSets)
        for (final group in set.groups)
          for (final requirement in group.requirements)
            requirement.id: (
              name: requirement.name,
              path: '${set.name} › '
                  '${group.subtitle == null ? group.name : '${group.name} (${group.subtitle})'}',
            ),
    };

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
  final lines = activityCriteriaLines(categories, criteriaSets, activity);
  if (lines.isEmpty) return '-';
  return lines.length == 1 ? lines.first.name : '${lines.first.name} +${lines.length - 1}';
}

/// ทีละรายการที่กิจกรรมนับชั่วโมงให้ — ต้นทางเดียวของทั้งป้ายสั้นในตาราง/การ์ด
/// ([activityCriteriaLabel]) และรายการเต็มในไดอะล็อกยืนยันการสมัคร
///
/// ว่าง = ยังไม่ได้กำหนดหมวด (ไม่ผูกรายการเกณฑ์และไม่มีหมวดย่อยที่หาเจอ)
List<({String name, String? learningUnit})> activityCriteriaLines(
  List<HourCategory> categories,
  List<CriteriaSet> criteriaSets,
  Activity activity,
) {
  if (activity.requirementIds.isEmpty) {
    final path = subcategoryPath(categories, activity.subcategoryId);
    return path == '-' ? const [] : [(name: path, learningUnit: null)];
  }
  final byId = requirementsById(criteriaSets);
  final lines = [
    for (final id in activity.requirementIds)
      if (byId[id] != null) (name: byId[id]!.name, learningUnit: byId[id]!.learningUnitName),
  ];
  if (lines.isEmpty) {
    // ผูกไว้แต่ชุดเกณฑ์ที่โหลดมายังไม่มีรายการนั้น (เช่น ชุดถูกปิด) — บอกจำนวนเท่าที่รู้
    return [(name: '${activity.requirementIds.length} รายการเกณฑ์', learningUnit: null)];
  }
  return lines;
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

/// ตารางแคบกว่านี้ ยุบปุ่มรองเข้าเมนู ⋮ — ปุ่มครบ 4 ปุ่มกินที่ 140px ซึ่งตารางแคบ ๆ
/// ควรเอาไปให้คอลัมน์ข้อความ (ชื่อ/สถานที่/หมวด) แทน
const kActivityActionsCompactBelow = 960.0;

bool activityActionsCompact(double tableWidth) => tableWidth < kActivityActionsCompactBelow;

/// ช่องไฟระหว่างคอลัมน์ของตารางกิจกรรม — แคบกว่าค่าเริ่มต้นของธีม (24) เพื่อให้ 8 คอลัมน์
/// พอดีจอ desktop โดยไม่ต้องเลื่อนแนวนอน
const kActivityColumnSpacing = AppSpacing.lg;

/// ขอบซ้าย-ขวาของตาราง (ช่องว่างก่อนคอลัมน์แรก/หลังคอลัมน์สุดท้าย)
const kActivityTableMargin = AppSpacing.lg;

/// ความสูงแถว — ล็อกไว้ทุกแถวสูงเท่ากัน ปุ่ม 32px และชิปสถานะอยู่กึ่งกลางพอดี
const kActivityRowHeight = 56.0;

/// ความกว้างเนื้อหาของคอลัมน์ที่กว้างคงที่ (ไม่รวม padding รอบเซลล์)
/// ชั่วโมงที่ได้ — กว้างพอสำหรับ "12.5 ชม." และหัว "ชั่วโมงที่ได้" ด้วย Sarabun
const kActivityHoursCellWidth = 72.0;
const kActivityStatusCellWidth = 112.0;

/// ความกว้างคอลัมน์ใน Table = เนื้อหา + padding ที่ DataTable ใส่รอบเซลล์เอง
///
/// DataTable ให้ padding ครึ่งช่องไฟแต่ละข้าง ยกเว้นคอลัมน์แรก (ขอบตารางด้านหน้า) และ
/// คอลัมน์สุดท้าย (ขอบตารางด้านหลัง) — columnWidth ที่ส่งไปคือความกว้างรวม padding
/// ถ้าใส่แค่ความกว้างเนื้อหา เนื้อหาจะโดนบีบเหลือน้อยกว่าที่ตั้งไว้
TableColumnWidth _fixedColumn(double content, {bool last = false}) => FixedColumnWidth(
      content +
          kActivityColumnSpacing / 2 +
          (last ? kActivityTableMargin : kActivityColumnSpacing / 2),
    );

/// คอลัมน์ของตารางกิจกรรม ซ้าย→ขวา — พอดีกว้างตาราง ไม่มีการเลื่อนแนวนอน
///
/// * ข้อความ (ชื่อ · สถานที่ · ประเภท · หมวดชั่วโมง) แชร์พื้นที่ที่เหลือแบบ flex แล้วตัด … + tooltip
/// * วันเวลา · ชั่วโมง · สถานะ · จัดการ กว้างคงที่ (เนื้อหาไม่ยาวกว่านี้)
/// * "บังคับ" กับ "รับสูงสุด" ไม่มีคอลัมน์ของตัวเอง — เป็นป้ายบนชื่อ + อยู่ใน tooltip ของชื่อ
///   (สองคอลัมน์นี้คือส่วนที่ทำให้ตารางกว้างเกินจอจนต้องเลื่อน)
///
/// นิสิตเห็นเฉพาะกิจกรรมที่อนุมัติแล้ว (backend กรองให้) คอลัมน์สถานะจึงเป็นค่าเดียวกันทุกแถว
/// ไม่ให้ข้อมูลอะไร — ซ่อนเฉพาะมุมมองนิสิต · ลำดับต้องตรงกับ [activityTableCells]
List<DataColumn> activityTableColumns(bool isStudent, {bool compact = false}) => [
      DataColumn(label: ActivityColumnLabel('ชื่อกิจกรรม'), columnWidth: const FlexColumnWidth(3)),
      DataColumn(
        label: ActivityColumnLabel('วันเวลา'),
        columnWidth: _fixedColumn(kThaiDateCellWidth),
      ),
      DataColumn(label: ActivityColumnLabel('สถานที่'), columnWidth: const FlexColumnWidth(2)),
      DataColumn(label: ActivityColumnLabel('ประเภท'), columnWidth: const FlexColumnWidth(1.4)),
      // "นับเข้าหมวด" กับ "ชั่วโมงที่ได้" ตั้งใจให้ไม่มีคำซ้ำกัน — เดิม "หมวดชั่วโมง" คู่กับ
      // "ชั่วโมง" อ่านแล้วนึกว่าเป็นคอลัมน์เดียวกัน
      DataColumn(label: ActivityColumnLabel('นับเข้าหมวด'), columnWidth: const FlexColumnWidth(2)),
      DataColumn(
        label: ActivityColumnLabel('ชั่วโมงที่ได้'),
        numeric: true,
        columnWidth: _fixedColumn(kActivityHoursCellWidth),
      ),
      if (!isStudent)
        DataColumn(
          label: ActivityColumnLabel('สถานะอนุมัติ'),
          columnWidth: _fixedColumn(kActivityStatusCellWidth),
        ),
      DataColumn(
        label: ActivityColumnLabel('จัดการ'),
        columnWidth: _fixedColumn(ActivityActionButtons.widthFor(compact: compact), last: true),
      ),
    ];

/// หัวคอลัมน์ของตารางกิจกรรม — ยอมหดและตัด … แทนที่จะล้นทับคอลัมน์ข้าง ๆ
///
/// DataTable วางป้ายหัวคอลัมน์เป็นลูกตรงของ [Row] ที่ไม่มีการหด ป้ายที่กว้างกว่าคอลัมน์
/// (คอลัมน์แคบคงที่อย่าง "ชั่วโมง" หรือเมื่อผู้ใช้ขยายตัวอักษรของระบบ) จึงล้นออกนอกคอลัมน์
/// — เป็น [Flexible] เองจึงหดตามคอลัมน์ได้ ส่วนความกว้างของคอลัมน์ยังมาจาก columnWidth
class ActivityColumnLabel extends Flexible {
  ActivityColumnLabel(this.text, {super.key})
      : super(
          child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
        );

  /// ข้อความหัวคอลัมน์ (ใช้อ้างถึงคอลัมน์ในเทสและที่อื่น)
  final String text;
}

/// เซลล์ของแถวกิจกรรม เรียงตาม [activityTableColumns] — [actions] คือเนื้อหาคอลัมน์ "จัดการ"
List<DataCell> activityTableCells(
  Activity a, {
  required bool isStudent,
  required Widget actions,
  List<HourCategory> categories = const [],
  List<CriteriaSet> criteriaSets = const [],
  TextStyle? mutedStyle,
}) =>
    [
      DataCell(ActivityNameCell(activity: a)),
      // วันเวลาไทย พ.ศ. — ตารางโชว์แค่วันที่ เวลาเต็มอยู่ใน tooltip · กว้างคงที่ (ดู ThaiDateCell)
      DataCell(ThaiDateCell(
        formatThaiDate(a.startAt),
        tooltip: formatThaiDateTime(a.startAt),
        style: mutedStyle,
      )),
      // คอลัมน์ flex — ตารางกำหนดขอบให้แล้ว TruncatedCell จึงไม่ต้องจำกัดความกว้างเอง
      DataCell(TruncatedCell(a.location, maxWidth: double.infinity, style: mutedStyle)),
      DataCell(TruncatedCell(a.activityType, maxWidth: double.infinity, style: mutedStyle)),
      DataCell(TruncatedCell(
        activityCriteriaLabel(categories, criteriaSets, a),
        maxWidth: double.infinity,
        style: mutedStyle,
      )),
      // ชิดขวาให้ตรงหัวคอลัมน์ (คอลัมน์ตัวเลข) · ย่อลงเองถ้าตัวอักษรใหญ่เกินช่อง แทนการตัดทิ้ง
      DataCell(NarrowCell(
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(activityHoursLabel(a), maxLines: 1, softWrap: false),
        ),
        width: kActivityHoursCellWidth,
      )),
      if (!isStudent) DataCell(ActivityApprovalChips(activity: a)),
      DataCell(actions),
    ];

/// รายละเอียดใต้ชื่อในการ์ดจอแคบ — บรรทัดแรก "ทำอะไร เมื่อไหร่" บรรทัดสอง "ที่ไหน รับกี่คน"
String activityCardSubtitle(Activity a) =>
    '${a.activityType} • ได้ ${_trimHours(a.hours)} ชม. • ${formatThaiDateTime(a.startAt)}\n'
    'สถานที่: ${a.location} • รับ ${a.maxParticipants} คน${a.isRequired ? " • บังคับ" : ""}';

/// ชั่วโมงที่ได้จากกิจกรรม พร้อมหน่วย — "3 ชม." / "4.5 ชม." (ไม่ใช่เลขลอย ๆ)
String activityHoursLabel(Activity a) => '${_trimHours(a.hours)} ชม.';

/// tooltip ของชื่อกิจกรรมในตาราง — ชื่อเต็ม + ข้อมูลที่เคยเป็นคอลัมน์ "รับสูงสุด"/"บังคับ"
String activityNameTooltip(Activity a) =>
    '${a.name}\nรับสูงสุด ${a.maxParticipants} คน · ${a.isRequired ? 'กิจกรรมบังคับ' : 'ไม่บังคับ'}';

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
                                child: ActivitiesTable(
                                  activities: _activities,
                                  categories: _categories,
                                  criteriaSets: _criteriaSets,
                                  isStudent: isStudent,
                                  canWrite: canWrite,
                                  isAdmin: authService.isAdmin,
                                  onAction: _onAction,
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
            subtitle: Text(activityCardSubtitle(a)),
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

/// ตารางกิจกรรมบน desktop — ทุกคอลัมน์พอดีกว้างตาราง ไม่มีการเลื่อนแนวนอน
///
/// ความกว้างคอลัมน์มาจาก [activityTableColumns] (ข้อความ flex · ที่เหลือคงที่) และตัดสินโหมด
/// ปุ่มจัดการ (ครบ/ย่อ) จากความกว้างที่ได้จริง · ทุกแถวสูง [kActivityRowHeight] เท่ากัน
class ActivitiesTable extends StatefulWidget {
  const ActivitiesTable({
    super.key,
    required this.activities,
    required this.isStudent,
    required this.canWrite,
    required this.isAdmin,
    required this.onAction,
    this.categories = const [],
    this.criteriaSets = const [],
  });

  final List<Activity> activities;
  final bool isStudent;
  final bool canWrite;
  final bool isAdmin;
  final void Function(Activity activity, ActivityAction action) onAction;
  final List<HourCategory> categories;
  final List<CriteriaSet> criteriaSets;

  @override
  State<ActivitiesTable> createState() => _ActivitiesTableState();
}

class _ActivitiesTableState extends State<ActivitiesTable> {
  /// แถวที่เมาส์ชี้อยู่ — ไฮไลต์ทั้งแถวให้กวาดตาตามแถวยาว ๆ ได้ไม่หลง
  int? _hovered;

  void _setHovered(int? index) {
    if (_hovered == index) return;
    setState(() => _hovered = index);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.sub);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = activityActionsCompact(constraints.maxWidth);
        return SizedBox(
          width: constraints.maxWidth,
          child: DataTable(
            columnSpacing: kActivityColumnSpacing,
            horizontalMargin: kActivityTableMargin,
            dataRowMinHeight: kActivityRowHeight,
            dataRowMaxHeight: kActivityRowHeight,
            columns: activityTableColumns(widget.isStudent, compact: compact),
            rows: [
              for (var i = 0; i < widget.activities.length; i++)
                DataRow(
                  color: WidgetStatePropertyAll(
                    i == _hovered ? AppColors.blueBg.withValues(alpha: 0.6) : null,
                  ),
                  cells: [
                    for (final cell in activityTableCells(
                      widget.activities[i],
                      isStudent: widget.isStudent,
                      categories: widget.categories,
                      criteriaSets: widget.criteriaSets,
                      mutedStyle: muted,
                      actions: widget.canWrite
                          ? ActivityActionButtons(
                              activity: widget.activities[i],
                              isAdmin: widget.isAdmin,
                              compact: compact,
                              onAction: (action) =>
                                  widget.onAction(widget.activities[i], action),
                            )
                          : const SizedBox.shrink(),
                    ))
                      DataCell(MouseRegion(
                        onEnter: (_) => _setHovered(i),
                        onExit: (_) => _setHovered(null),
                        // กินความสูงเต็มแถว ชี้ตรงไหนของแถวก็ติด ไม่ใช่เฉพาะบนตัวอักษร
                        child: SizedBox(
                          height: kActivityRowHeight,
                          child: Align(alignment: Alignment.centerLeft, child: cell.child),
                        ),
                      )),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// ชื่อกิจกรรมในตาราง — ตัด … เมื่อยาว · ป้าย "บังคับ" ต่อท้ายชื่อ
///
/// tooltip บอกชื่อเต็ม + รับสูงสุด + บังคับ/ไม่บังคับ แทนสองคอลัมน์ที่เคยทำให้ตารางล้นจอ
class ActivityNameCell extends StatelessWidget {
  const ActivityNameCell({super.key, required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: activityNameTooltip(activity),
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              activity.name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (activity.isRequired) ...[
            const SizedBox(width: AppSpacing.xs),
            const StatusChip(label: 'บังคับ', palette: StatusPalette.pending, dense: true),
          ],
        ],
      ),
    );
  }
}

/// ชิปสถานะฝั่ง staff/admin: สถานะอนุมัติ + ไอคอน "ซ่อนอยู่" ถ้าถูกซ่อนไว้
///
/// บรรทัดเดียวเสมอ · ซ่อนอยู่เป็นไอคอน (มี tooltip) ไม่ใช่ชิปที่สอง เพื่อให้คอลัมน์สถานะ
/// กว้างคงที่ได้แคบพอ · ย่อลงเองถ้าตัวอักษรใหญ่เกินคอลัมน์ (FittedBox) แทนที่จะล้นทับคอลัมน์ข้าง ๆ
class ActivityApprovalChips extends StatelessWidget {
  const ActivityApprovalChips({super.key, required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusChip.activityApproval(activity.approvalStatus, dense: true),
            if (activity.isHidden) ...[
              const SizedBox(width: AppSpacing.xs),
              const Tooltip(
                message: 'ซ่อนอยู่ — นิสิตไม่เห็นกิจกรรมนี้',
                child: Icon(Icons.visibility_off_outlined, size: 16, color: AppColors.muted),
              ),
            ],
          ],
        ),
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
  /// ประเภทกิจกรรม — null = ยังไม่ได้เลือก (สร้างใหม่ไม่เลือกค่าแรกให้เงียบ ๆ ต้องกดเลือกเอง)
  String? _activityType;
  int? _subcategoryId;

  /// กล่องเลือกรายการเกณฑ์กางอยู่ไหม — สร้างใหม่ (ยังไม่มีรายการ) กางไว้เลย
  /// แก้ไขกิจกรรมที่ผูกรายการแล้วพับไว้ ให้เห็น pill ของสิ่งที่เลือกก่อน
  late bool _pickerOpen;
  Set<int> _requirementIds = {};
  bool _isRequired = false;
  late DateTime _startAt;

  /// เวลาสิ้นสุด — null = ไม่ระบุ (ไม่บังคับ)
  DateTime? _endAt;
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
    // โหมดแก้ไขคงค่าเดิมเสมอ แม้ไม่ใช่ 5 ค่าในรายการ (ข้อมูลเก่า/นำเข้า)
    _activityType = (e?.activityType.isNotEmpty ?? false) ? e!.activityType : null;
    _requirementIds = {...?e?.requirementIds};
    _pickerOpen = _requirementIds.isEmpty;
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
    _endAt = e?.endAt;
    // pill ของรายการเกณฑ์บอกชั่วโมงที่นิสิตจะได้ — ต้องเปลี่ยนตามช่องชั่วโมงทันที
    _hoursController.addListener(_onHoursChanged);
  }

  void _onHoursChanged() => setState(() {});

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

  /// เลือกเวลาสิ้นสุด — เริ่มที่วันเดียวกับเวลาเริ่ม (กิจกรรมส่วนใหญ่จบวันเดียวกัน)
  /// และเลือกย้อนไปก่อนวันเริ่มไม่ได้ · ชิ้นเวลาเริ่มต้นที่ +1 ชม. จากเวลาเริ่ม
  /// เป็นแค่ค่าตั้งต้นของช่องพิมพ์ ไม่ผูกกับช่อง "ชั่วโมงที่ได้รับ"
  Future<void> _pickEndDateTime() async {
    final firstDay = DateTime(_startAt.year, _startAt.month, _startAt.day);
    final initial = _endAt ?? _startAt.add(const Duration(hours: 1));
    final initialDay = DateTime(initial.year, initial.month, initial.day);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDay.isBefore(firstDay) ? firstDay : initialDay,
      firstDate: firstDay,
      lastDate: DateTime(firstDay.year + 3, firstDay.month, firstDay.day),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      initialEntryMode: TimePickerEntryMode.inputOnly,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _endAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  /// error ใต้ช่อง "เวลาสิ้นสุด" — คำนวณสดทุกครั้งที่วาด จึงเปลี่ยนตามทันทีแม้ผู้ใช้
  /// ไปแก้เวลาเริ่มทีหลัง
  String? get _endError => isEndBeforeStart(_startAt, _endAt) ? kEndBeforeStartMessage : null;

  Future<void> _submit() async {
    // ตรวจทุกข้อพร้อมกันแล้วบอกทุกข้อที่ขาดในรอบเดียว — ไม่ให้แก้ข้อหนึ่งแล้วค่อยเจอข้อถัดไป
    final fieldsValid = _formKey.currentState!.validate();
    // กติกาเดียวกับ backend: ต้องจัดหมวดอย่างน้อยหนึ่งทาง ไม่งั้นกิจกรรมนี้จะไม่นับ
    // ชั่วโมงให้ใครเลย
    final missingCriteria = _requirementIds.isEmpty && _subcategoryId == null;
    if (missingCriteria) {
      setState(() {
        _error = 'กรุณาเลือกรายการเกณฑ์อย่างน้อยหนึ่งรายการ '
            'หรือเลือกหมวดชั่วโมงโครงเดิม';
        _pickerOpen = true;
      });
    }
    // กติกาเดียวกับ backend (422) — ข้อความขึ้นใต้ช่องเวลาสิ้นสุดอยู่แล้ว ไม่ต้องยิง API
    if (!fieldsValid || missingCriteria || _endError != null) return;
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
    final body = activityFormPayload(
      name: _nameController.text.trim(),
      activityType: _activityType!,
      subcategoryId: _subcategoryId,
      requirementIds: _requirementIds,
      hours: hours,
      isRequired: _isRequired,
      maxParticipants: int.parse(_maxParticipantsController.text.trim()),
      startAt: _startAt,
      endAt: _endAt,
      location: _locationController.text.trim(),
    );
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
    // ลำดับตาม mockup: ชื่อ → บล็อกเกณฑ์ (พระเอก) → ชั่วโมง/จำนวนรับ → วันเวลา/สถานที่ → ประเภท (ป้ายรอง)
    return AppFormDialog(
      title: widget.existing == null ? 'สร้างกิจกรรม' : 'แก้ไขกิจกรรม',
      subtitle: 'กรอกข้อมูลกิจกรรม แล้วเลือกว่านับเข้าเกณฑ์ชั่วโมงข้อไหน',
      width: 540,
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSubmit: _submit,
      fields: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'ชื่อกิจกรรม',
            hintText: 'เช่น อบรมความปลอดภัยไซเบอร์ ครั้งที่ 3/2569',
          ),
          validator: requiredValidator,
        ),
        ActivityCriteriaBlock(
          criteriaSets: widget.criteriaSets,
          categories: widget.categories,
          selected: _requirementIds,
          subcategoryId: _subcategoryId,
          hoursText: _hoursController.text,
          pickerOpen: _pickerOpen,
          onTogglePicker: () => setState(() => _pickerOpen = !_pickerOpen),
          onRequirementsChanged: (ids) => setState(() {
            _requirementIds = ids;
            if (ids.isNotEmpty) _error = null;
          }),
          onSubcategoryChanged: (v) => setState(() => _subcategoryId = v),
        ),
        _FormRow(
          children: [
            TextFormField(
              controller: _hoursController,
              decoration: const InputDecoration(labelText: 'ชั่วโมงที่ได้รับ', hintText: 'เช่น 4'),
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
          ],
        ),
        _FormRow(
          children: [
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
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'เวลาสิ้นสุด (ไม่บังคับ)',
                errorText: _endError,
                errorMaxLines: 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickEndDateTime,
                      child: Text(
                        _endAt == null ? 'ไม่ระบุ' : formatThaiDateTime(_endAt!),
                        style: _endAt == null
                            ? Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: AppColors.muted)
                            : null,
                      ),
                    ),
                  ),
                  if (_endAt != null)
                    InkWell(
                      onTap: () => setState(() => _endAt = null),
                      child: const Tooltip(
                        message: 'ล้างเวลาสิ้นสุด',
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.close, size: 18),
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: _pickEndDateTime,
                    child: const Icon(Icons.event_available, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
        TextFormField(
          controller: _locationController,
          decoration: const InputDecoration(labelText: 'สถานที่', hintText: 'เช่น หอประชุม'),
          validator: requiredValidator,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('กิจกรรมบังคับ'),
          subtitle: const Text('นิสิตทุกคนต้องเข้าร่วม'),
          value: _isRequired,
          onChanged: (v) => setState(() => _isRequired = v),
        ),
        ActivityTypeChips(
          value: _activityType,
          existingType: widget.existing?.activityType,
          onChanged: (v) => setState(() => _activityType = v),
        ),
      ],
    );
  }
}

/// สองช่องเคียงกันในฟอร์ม — จอแคบซ้อนเป็นแถวเดียวต่อช่อง ไม่บีบจนอ่านไม่ออก
class _FormRow extends StatelessWidget {
  const _FormRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.md),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// บล็อก "นับเข้าเกณฑ์ชั่วโมง" — สิ่งเดียวในฟอร์มที่กำหนดว่านิสิตได้ชั่วโมงหมวดไหน
///
/// จัดกรอบให้เด่นกว่าช่องอื่น (ผู้ใช้เคยสับสนเพราะช่องประเภทวางปนกันจนดูสำคัญเท่ากัน)
/// รายการที่เลือกขึ้นเป็น pill พร้อมชั่วโมงที่นิสิตจะได้ · เลือก/ถอดด้วย [RequirementPicker] เดิม
/// ไม่แตะ logic การผูก · หมวดชั่วโมงโครงเดิมอยู่ในบล็อกนี้ด้วยเพราะเป็นอีกทางที่ให้ชั่วโมง
class ActivityCriteriaBlock extends StatelessWidget {
  const ActivityCriteriaBlock({
    super.key,
    required this.criteriaSets,
    required this.categories,
    required this.selected,
    required this.subcategoryId,
    required this.hoursText,
    required this.pickerOpen,
    required this.onTogglePicker,
    required this.onRequirementsChanged,
    required this.onSubcategoryChanged,
  });

  final List<CriteriaSet> criteriaSets;
  final List<HourCategory> categories;
  final Set<int> selected;
  final int? subcategoryId;

  /// ค่าในช่องชั่วโมงตอนนี้ — ใช้โชว์ใน pill ว่ารายการนั้นจะได้กี่ชั่วโมง
  final String hoursText;
  final bool pickerOpen;
  final VoidCallback onTogglePicker;
  final ValueChanged<Set<int>> onRequirementsChanged;
  final ValueChanged<int?> onSubcategoryChanged;

  @override
  Widget build(BuildContext context) {
    final paths = requirementPaths(criteriaSets);
    final hours = double.tryParse(hoursText.trim());
    final hoursLabel = hours == null || hours <= 0 ? '– ชม.' : '${formatHours(hours)} ชม.';
    final hasSets = criteriaSets.isNotEmpty;
    final picked = selected.toList()..sort();

    return Container(
      key: const ValueKey('activity-criteria-block'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md + 2, AppSpacing.md + 2, AppSpacing.md + 2, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.blueBg,
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.3), width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text.rich(
            TextSpan(
              text: 'นับเข้าเกณฑ์ชั่วโมง',
              children: [TextSpan(text: ' *', style: TextStyle(color: AppColors.blue))],
            ),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.blueDark),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'ตัวนี้คือสิ่งที่กำหนดว่านิสิตได้ชั่วโมงหมวดไหน · เลือกได้หลายข้อ ชั่วโมงจะเข้าให้ทุกข้อที่เลือก',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.sub),
          ),
          const SizedBox(height: AppSpacing.md - 1),
          for (final id in picked)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _RequirementPill(
                key: ValueKey('requirement-pill-$id'),
                name: paths[id]?.name ?? 'รายการเกณฑ์ #$id',
                path: paths[id]?.path,
                hoursLabel: hoursLabel,
                onRemove: () => onRequirementsChanged({...selected}..remove(id)),
              ),
            ),
          if (hasSets)
            OutlinedButton.icon(
              onPressed: onTogglePicker,
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.blueDark,
                side: BorderSide(color: AppColors.blue.withValues(alpha: 0.6)),
                minimumSize: const Size.fromHeight(38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              icon: Icon(pickerOpen ? Icons.expand_less : Icons.add, size: 18),
              label: Text(pickerOpen ? 'ซ่อนรายการเกณฑ์' : 'เพิ่มเกณฑ์ที่นับเข้า'),
            ),
          if (pickerOpen || !hasSets) ...[
            const SizedBox(height: AppSpacing.sm),
            // Material ของตัวเอง: แถวติ๊กใน picker เป็น ListTile ที่วาดพื้น/ripple บน Material
            // ใกล้สุด — ถ้าไม่มี พื้นฟ้าของบล็อกจะบังไว้ (และได้กล่องรายการสีขาวแยกจากพื้นบล็อกด้วย)
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.field),
              clipBehavior: Clip.antiAlias,
              child: RequirementPicker(
                criteriaSets: criteriaSets,
                selected: selected,
                onChanged: onRequirementsChanged,
                // หัวข้อ/คำอธิบายอยู่ที่หัวบล็อกแล้ว ไม่ต้องซ้ำ
                showHeader: false,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // E3: ทางเดิมสำหรับนิสิตที่ยังไม่ผูกชุดเกณฑ์ — ไม่บังคับเมื่อระบบมีชุดเกณฑ์แล้ว
          SubcategoryDropdown(
            categories: categories,
            value: subcategoryId,
            onChanged: onSubcategoryChanged,
            labelText: hasSets ? 'หมวดชั่วโมงโครงเดิม (ไม่บังคับ)' : 'หมวดชั่วโมง',
            required: !hasSets,
          ),
        ],
      ),
    );
  }
}

class _RequirementPill extends StatelessWidget {
  const _RequirementPill({
    super.key,
    required this.name,
    required this.path,
    required this.hoursLabel,
    required this.onRemove,
  });

  final String name;
  final String? path;
  final String hoursLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 2, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                if (path != null)
                  Text(path!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: StatusPalette.approved.background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              hoursLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: StatusPalette.approved.foreground,
              ),
            ),
          ),
          IconButton(
            tooltip: 'เอารายการนี้ออก',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// ช่อง "ประเภทกิจกรรม" — ป้ายรองไว้ค้นหา/กรอง ไม่เกี่ยวกับการนับชั่วโมง
///
/// เป็น chip เลือกหนึ่งค่า (ส่งค่า string เดิม 5 ค่าที่ backend รับ) และต้องกดเลือกเอง —
/// ไม่มีค่าเริ่มต้นที่ติดมาเงียบ ๆ อีกต่อไป (เดิม dropdown เลือกค่าแรกให้ทุกครั้ง)
class ActivityTypeChips extends StatelessWidget {
  const ActivityTypeChips({
    super.key,
    required this.value,
    required this.onChanged,
    this.existingType,
  });

  final String? value;

  /// ประเภทเดิมของกิจกรรมที่กำลังแก้ — ถ้าไม่อยู่ใน 5 ค่า ยังโชว์เป็นชิปเพิ่มให้เลือกคืนได้
  final String? existingType;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = activityTypeChoices(existingType);

    return FormField<String>(
      initialValue: value,
      validator: (v) => (v == null || v.isEmpty) ? 'เลือกประเภทกิจกรรม' : null,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text.rich(
            TextSpan(
              text: 'ประเภทกิจกรรม',
              children: [
                TextSpan(text: ' *', style: TextStyle(color: AppColors.blue)),
                TextSpan(
                  text: '  — ป้ายไว้ค้นหา/กรอง ไม่เกี่ยวกับการนับชั่วโมง',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.muted),
                ),
              ],
            ),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final type in choices)
                ChoiceChip(
                  label: Text(type),
                  selected: field.value == type,
                  showCheckmark: false,
                  selectedColor: AppColors.blueBg,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                    color: field.value == type
                        ? AppColors.blue.withValues(alpha: 0.35)
                        : AppColors.line,
                  ),
                  shape: const StadiumBorder(),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: field.value == type ? FontWeight.w600 : FontWeight.w500,
                    color: field.value == type ? AppColors.blueDark : AppColors.sub,
                  ),
                  onSelected: (_) {
                    field.didChange(type);
                    onChanged(type);
                  },
                ),
            ],
          ),
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                field.errorText!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
