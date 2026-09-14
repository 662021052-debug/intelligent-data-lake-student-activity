import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ชื่อระบบที่ขึ้นบนแถบบนสุดทุกหน้า
const String kAppBrandTitle = 'กิจกรรมพัฒนานิสิต';

/// เมนูหนึ่งช่องบนแถบนำทาง
///
/// [id] เป็นตัวระบุที่คงที่ (ไม่ใช่ข้อความ) เพื่อให้หน้าไหนกำลังเปิดอยู่ตรวจสอบได้
/// โดยไม่ต้องเทียบสตริงภาษาไทย
///
/// [children] คือหน้าย่อยของเมนูนั้น (เช่น แดชบอร์ด → ภาพรวม, สถิติ) เมนูที่มี
/// หน้าย่อยจะพับ/กางได้บน sidebar และกางเองเมื่อหน้าย่อยตัวใดตัวหนึ่งเปิดอยู่
class AppNavItem {
  const AppNavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.children = const [],
  });

  final String id;
  final String label;
  final IconData icon;
  final List<AppNavItem> children;

  static const home = AppNavItem(id: 'home', label: 'หน้าแรก', icon: Icons.home_outlined);
  static const register =
      AppNavItem(id: 'register', label: 'สมัครกิจกรรม', icon: Icons.how_to_reg_outlined);
  static const myHours =
      AppNavItem(id: 'my_hours', label: 'รายละเอียดชั่วโมง', icon: Icons.timelapse_outlined);
  static const chatbot =
      AppNavItem(id: 'chatbot', label: 'ผู้ช่วยอัจฉริยะ', icon: Icons.smart_toy_outlined);
  static const activities =
      AppNavItem(id: 'activities', label: 'จัดการกิจกรรม', icon: Icons.event_outlined);
  static const participations = AppNavItem(
    id: 'participations',
    label: 'การเข้าร่วมกิจกรรม',
    icon: Icons.fact_check_outlined,
  );
  static const evidenceReview = AppNavItem(
    id: 'evidence_review',
    label: 'ตรวจหลักฐาน',
    icon: Icons.document_scanner_outlined,
  );
  static const calendar = AppNavItem(
    id: 'calendar',
    label: 'ปฏิทินกิจกรรม',
    icon: Icons.calendar_month_outlined,
  );
  static const users =
      AppNavItem(id: 'users', label: 'จัดการผู้ใช้', icon: Icons.manage_accounts_outlined);
  static const hourCategories =
      AppNavItem(id: 'hour_categories', label: 'หมวดชั่วโมง', icon: Icons.category_outlined);
  static const dashboard =
      AppNavItem(id: 'dashboard', label: 'แดชบอร์ด', icon: Icons.dashboard_outlined);
  static const students =
      AppNavItem(id: 'students', label: 'จัดการนิสิต', icon: Icons.school_outlined);
}

/// เมนูของแต่ละ role — ตรงกับสิทธิ์ที่หน้าจอนั้น ๆ ยอมให้เข้าจริง
///
/// เจ้าหน้าที่ไม่ได้เห็นเมนูจัดการผู้ใช้/หมวดชั่วโมง/แดชบอร์ด เพราะสามหน้านั้น
/// เป็นของแอดมินเท่านั้น (หน้าจะปฏิเสธการเข้าถึงอยู่แล้ว เมนูจึงต้องไม่ล่อให้กด)
List<AppNavItem> navItemsForRole(String? role) => switch (role) {
      'student' => const [
          AppNavItem.home,
          AppNavItem.register,
          AppNavItem.myHours,
          AppNavItem.chatbot,
        ],
      // เรียงตาม mockup: แดชบอร์ด (หน้าแรกของแอดมิน) มาก่อน แล้วหน้าจัดการ
      'admin' => const [
          AppNavItem.dashboard,
          AppNavItem.activities,
          // วางต่อจาก "จัดการกิจกรรม" เพราะเป็นมุมมองอีกแบบของข้อมูลชุดเดียวกัน
          AppNavItem.calendar,
          // คิวตรวจหลักฐาน + OCR ของทั้งระบบ (เดิมต้องเข้าผ่านรายชื่อผู้เข้าร่วมทีละกิจกรรม)
          AppNavItem.evidenceReview,
          AppNavItem.users,
          AppNavItem.students,
          AppNavItem.hourCategories,
        ],
      'staff' => const [
          AppNavItem.activities,
          AppNavItem.participations,
          AppNavItem.evidenceReview,
          AppNavItem.calendar,
        ],
      _ => const [AppNavItem.home],
    };

/// คำบรรยายใต้ชื่อระบบ — แยกฝั่งนิสิตกับฝั่งผู้ดูแลตาม mockup
String navSubtitleForRole(String? role) =>
    role == 'student' ? 'นอกชั้นเรียน' : 'ระบบผู้ดูแล';

/// หัวข้อกลุ่มเหนือรายการเมนูบน sidebar
String navGroupTitleForRole(String? role) =>
    role == 'student' ? 'เมนูนิสิต' : 'เมนูผู้ดูแลระบบ';

/// ป้ายชื่อ role ภาษาไทย (นิสิต / เจ้าหน้าที่ / ผู้ดูแลระบบ)
String roleLabel(String? role) => switch (role) {
      'student' => 'นิสิต',
      'staff' => 'เจ้าหน้าที่',
      'admin' => 'ผู้ดูแลระบบ',
      _ => '-',
    };

/// โลโก้กล่องตัวอักษร "TSU"
///
/// บนพื้นสว่างเป็นกล่องฟ้าตัวอักษรขาว ส่วนบนพื้นน้ำเงินเข้มของ sidebar ต้องสลับ
/// เป็นกล่องขาวตัวอักษรฟ้า ไม่งั้นฟ้าบนน้ำเงินเข้มแทบมองไม่เห็น
class TsuLogo extends StatelessWidget {
  const TsuLogo({super.key, this.size = 36, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onDark ? Colors.white : AppColors.blue,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Text(
        'TSU',
        style: TextStyle(
          color: onDark ? AppColors.blue : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// วงกลมตัวอักษรย่อของผู้ใช้ (พื้นฟ้าอ่อน ตัวอักษรฟ้าเข้ม)
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.username, this.size = 30});

  final String? username;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = username?.trim() ?? '';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.blueBg, shape: BoxShape.circle),
      child: name.isEmpty
          ? Icon(Icons.person, size: size * 0.6, color: AppColors.blue)
          : Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w600,
                fontSize: size * 0.42,
              ),
            ),
    );
  }
}
