import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ชื่อระบบที่ขึ้นบนแถบบนสุดทุกหน้า
const String kAppBrandTitle = 'กิจกรรมพัฒนานิสิต';

/// เมนูหนึ่งช่องบนแถบนำทาง
///
/// [id] เป็นตัวระบุที่คงที่ (ไม่ใช่ข้อความ) เพื่อให้หน้าไหนกำลังเปิดอยู่ตรวจสอบได้
/// โดยไม่ต้องเทียบสตริงภาษาไทย
class AppNavItem {
  const AppNavItem({required this.id, required this.label, required this.icon});

  final String id;
  final String label;
  final IconData icon;

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
      'admin' => const [
          AppNavItem.activities,
          AppNavItem.users,
          AppNavItem.hourCategories,
          AppNavItem.dashboard,
        ],
      'staff' => const [
          AppNavItem.activities,
          AppNavItem.participations,
          AppNavItem.calendar,
        ],
      _ => const [AppNavItem.home],
    };

/// คำบรรยายใต้ชื่อระบบ — แยกฝั่งนิสิตกับฝั่งผู้ดูแลตาม mockup
String navSubtitleForRole(String? role) =>
    role == 'student' ? 'นอกชั้นเรียน' : 'ระบบผู้ดูแล';

/// แถบนำทางบนสุดของทุกหน้า (ตาม mockup)
///
/// โลโก้ TSU + ชื่อระบบ · เมนูแนวนอนตรงกลาง (เมนูที่เปิดอยู่เป็นฟ้าและขีดเส้นใต้)
/// · avatar + ปุ่มออกจากระบบ
///
/// จอแคบกว่า [_wideBreakpoint] จะยุบเมนูกลางเป็นปุ่มเมนูแบบ popup เพื่อไม่ให้ล้น
class AppNavBar extends StatelessWidget implements PreferredSizeWidget {
  const AppNavBar({
    super.key,
    required this.items,
    this.activeId,
    this.onSelect,
    this.username,
    this.subtitle,
    this.onLogout,
    this.onBack,
    this.onHome,
    this.title,
  });

  /// เมนูที่จะแสดง — ปกติมาจาก [navItemsForRole]
  final List<AppNavItem> items;

  /// [AppNavItem.id] ของหน้าที่กำลังเปิดอยู่
  final String? activeId;

  final ValueChanged<AppNavItem>? onSelect;

  /// ชื่อผู้ใช้ ใช้ทำตัวอักษรย่อใน avatar
  final String? username;

  /// คำบรรยายใต้ชื่อระบบ — ปกติมาจาก [navSubtitleForRole]
  final String? subtitle;

  final VoidCallback? onLogout;

  /// ปุ่มย้อนกลับด้านซ้ายสุด (หน้าที่เปิดซ้อนขึ้นมา)
  final VoidCallback? onBack;

  /// กดโลโก้/ชื่อระบบเพื่อกลับหน้าแรก — เมนูฝั่งผู้ดูแลไม่มีช่อง "หน้าแรก"
  /// ตาม mockup โลโก้จึงเป็นทางกลับที่ใช้ได้ทุก role
  final VoidCallback? onHome;

  /// ชื่อหน้าที่กำลังเปิด แสดงเฉพาะตอนจอแคบ
  ///
  /// จอกว้างมีเมนูที่ไฮไลต์บอกอยู่แล้ว แต่พอเมนูยุบเป็น popup จะไม่เหลืออะไร
  /// บอกว่ากำลังอยู่หน้าไหน
  final String? title;

  static const double _height = 58;
  static const double _wideBreakpoint = 900;

  /// แคบกว่านี้ต้องซ่อนชื่อระบบข้างโลโก้ ไม่งั้นแถวบนล้นจอบนมือถือเล็ก
  /// (โลโก้ TSU ยังอยู่ และแถบยังบอกชื่อหน้าที่เปิดอยู่)
  static const double _brandTextBreakpoint = 480;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: Container(
        height: _height,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _wideBreakpoint;
            final showBrandText = constraints.maxWidth >= _brandTextBreakpoint;
            return Row(
              children: [
                if (onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'ย้อนกลับ',
                    onPressed: onBack,
                  ),
                _HomeLink(
                  onTap: onHome,
                  subtitle: subtitle,
                  showText: showBrandText,
                ),
                if (wide)
                  Expanded(child: _NavLinks(items: items, activeId: activeId, onSelect: onSelect))
                else if (title != null)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Text(
                        title!,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: AppColors.blue),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (!wide && items.length > 1) ...[
                  _NavMenuButton(items: items, activeId: activeId, onSelect: onSelect),
                  const SizedBox(width: AppSpacing.sm),
                ],
                UserAvatar(username: username),
                if (onLogout != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  // จอแคบเหลือแค่ไอคอน (ยังมี tooltip บอกว่าปุ่มอะไร)
                  if (wide)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('ออกจากระบบ'),
                      onPressed: onLogout,
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.logout, size: 20),
                      tooltip: 'ออกจากระบบ',
                      onPressed: onLogout,
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// โลโก้กล่องฟ้าตัวอักษรขาว "TSU"
class TsuLogo extends StatelessWidget {
  const TsuLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.blue,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Text(
        'TSU',
        style: TextStyle(
          color: Colors.white,
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

/// โลโก้ + ชื่อระบบ กดแล้วกลับหน้าแรก
class _HomeLink extends StatelessWidget {
  const _HomeLink({
    required this.onTap,
    required this.subtitle,
    required this.showText,
  });

  final VoidCallback? onTap;
  final String? subtitle;

  /// จอแคบมากเหลือแค่โลโก้
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TsuLogo(),
        if (showText) ...[
          const SizedBox(width: AppSpacing.md),
          // จำกัดความกว้างไว้ ชื่อระบบที่ยาวขึ้นในอนาคตจะได้ไม่ดันแถวจนล้น
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: _Brand(subtitle: subtitle),
          ),
        ],
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Tooltip(
        message: 'หน้าแรก',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
          child: content,
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.subtitle});

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          kAppBrandTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleSmall?.copyWith(height: 1.15),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(
              color: AppColors.muted,
              fontWeight: FontWeight.w400,
              height: 1.15,
            ),
          ),
      ],
    );
  }
}

/// เมนูแนวนอนตรงกลาง — ตัวที่เปิดอยู่เป็นฟ้าตัวหนาและมีเส้นใต้
class _NavLinks extends StatelessWidget {
  const _NavLinks({required this.items, this.activeId, this.onSelect});

  final List<AppNavItem> items;
  final String? activeId;
  final ValueChanged<AppNavItem>? onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final item in items)
            _NavLink(
              item: item,
              active: item.id == activeId,
              onTap: onSelect == null ? null : () => onSelect!(item),
            ),
        ],
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.item, required this.active, this.onTap});

  final AppNavItem item;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          item.label,
          style: text.labelLarge?.copyWith(
            color: active ? AppColors.blue : AppColors.sub,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// เมนูแบบยุบสำหรับจอแคบ
class _NavMenuButton extends StatelessWidget {
  const _NavMenuButton({required this.items, this.activeId, this.onSelect});

  final List<AppNavItem> items;
  final String? activeId;
  final ValueChanged<AppNavItem>? onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppNavItem>(
      tooltip: 'เมนู',
      icon: const Icon(Icons.menu),
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<AppNavItem>(
            value: item,
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: item.id == activeId ? AppColors.blue : AppColors.sub,
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  item.label,
                  style: TextStyle(
                    color: item.id == activeId ? AppColors.blue : AppColors.ink,
                    fontWeight: item.id == activeId ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
