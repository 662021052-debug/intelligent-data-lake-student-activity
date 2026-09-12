import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_nav.dart';

/// เมนูหลักของระบบ — แถบซ้ายพื้นน้ำเงินเข้มตาม mockup
///
/// โครง: โลโก้ + ชื่อระบบ · หัวข้อกลุ่ม ("เมนูผู้ดูแลระบบ"/"เมนูนิสิต") ·
/// รายการเมนู (ไอคอน + ข้อความ ตัวที่เปิดอยู่พื้นขาวตัวน้ำเงิน) · ท้ายสุดเป็น
/// ผู้ใช้ที่ล็อกอินอยู่ + ปุ่มออกจากระบบ
///
/// เมนูที่มี [AppNavItem.children] จะพับ/กางได้ และกางเองเมื่อหน้าย่อยของมัน
/// กำลังเปิดอยู่ — ผู้ใช้จะได้ไม่ต้องไล่กางเองเพื่อหาว่าตัวเองอยู่ตรงไหน
class AppSidebar extends StatefulWidget {
  const AppSidebar({
    super.key,
    required this.items,
    this.activeId,
    this.onSelect,
    this.username,
    this.role,
    this.subtitle,
    this.groupTitle,
    this.onLogout,
    this.onBrandTap,
  });

  /// เมนูที่จะแสดง — ปกติมาจาก [navItemsForRole]
  final List<AppNavItem> items;

  /// [AppNavItem.id] ของหน้าที่กำลังเปิดอยู่
  final String? activeId;

  final ValueChanged<AppNavItem>? onSelect;

  final String? username;

  /// role ของผู้ใช้ ใช้แสดงป้ายใต้ชื่อ (นิสิต/เจ้าหน้าที่/ผู้ดูแลระบบ)
  final String? role;

  /// คำบรรยายใต้ชื่อระบบ — ปกติมาจาก [navSubtitleForRole]
  final String? subtitle;

  /// หัวข้อเหนือรายการเมนู — ปกติมาจาก [navGroupTitleForRole]
  final String? groupTitle;

  final VoidCallback? onLogout;

  /// กดโลโก้/ชื่อระบบเพื่อกลับหน้าแรก
  final VoidCallback? onBrandTap;

  /// ความกว้างของแถบเมนู (drawer ตอนจอแคบใช้ค่าเดียวกัน จะได้กว้างเท่ากัน)
  static const double width = 210;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  /// id ของเมนูแม่ที่ผู้ใช้กางค้างไว้เอง (นอกเหนือจากตัวที่กางเองเพราะลูกเปิดอยู่)
  final Set<String> _expanded = {};

  bool _holdsActive(AppNavItem item) =>
      item.children.any((child) => child.id == widget.activeId);

  bool _isOpen(AppNavItem item) => _expanded.contains(item.id) || _holdsActive(item);

  void _toggle(AppNavItem item) {
    setState(() {
      if (_isOpen(item)) {
        _expanded.remove(item.id);
      } else {
        _expanded.add(item.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.blueDark,
      child: SizedBox(
        width: AppSidebar.width,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SidebarBrand(subtitle: widget.subtitle, onTap: widget.onBrandTap),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.groupTitle != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.sm,
                          ),
                          child: Text(
                            widget.groupTitle!,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.onNavMuted,
                                  letterSpacing: 0.4,
                                ),
                          ),
                        ),
                      for (final item in widget.items) ..._entriesFor(item),
                    ],
                  ),
                ),
              ),
              _SidebarUser(
                username: widget.username,
                role: widget.role,
                onLogout: widget.onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// เมนูหนึ่งช่อง พร้อมหน้าย่อยถ้ากางอยู่
  List<Widget> _entriesFor(AppNavItem item) {
    final hasChildren = item.children.isNotEmpty;
    final open = hasChildren && _isOpen(item);

    return [
      _SidebarTile(
        item: item,
        active: item.id == widget.activeId,
        expandable: hasChildren,
        expanded: open,
        onTap: () {
          // เมนูแม่ที่มีหน้าย่อยให้กางไปพร้อมกับเปิดหน้าของตัวเอง ผู้ใช้จึงกดครั้งเดียว
          // ได้ทั้งหน้าหลักของกลุ่มและเห็นหน้าย่อยที่เหลือ
          if (hasChildren) _toggle(item);
          widget.onSelect?.call(item);
        },
      ),
      if (open)
        for (final child in item.children)
          _SidebarTile(
            item: child,
            active: child.id == widget.activeId,
            indented: true,
            onTap: () => widget.onSelect?.call(child),
          ),
    ];
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({this.subtitle, this.onTap});

  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          const TsuLogo(size: 32, onDark: true),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  kAppBrandTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(color: Colors.white, height: 1.15),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(
                      color: AppColors.onNavMuted,
                      fontWeight: FontWeight.w400,
                      height: 1.15,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: Tooltip(message: 'หน้าแรก', child: content));
  }
}

/// เมนูหนึ่งช่องบน sidebar — ตัวที่เปิดอยู่เป็นพื้นขาวตัวน้ำเงินตาม mockup
class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.active,
    this.onTap,
    this.expandable = false,
    this.expanded = false,
    this.indented = false,
  });

  final AppNavItem item;
  final bool active;
  final VoidCallback? onTap;
  final bool expandable;
  final bool expanded;

  /// หน้าย่อย — เยื้องเข้ามาและใช้ตัวอักษรเล็กลง
  final bool indented;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final foreground = active ? AppColors.blue : AppColors.onNav;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        indented ? AppSpacing.xl : AppSpacing.sm,
        2,
        AppSpacing.sm,
        2,
      ),
      child: Material(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.field),
          hoverColor: Colors.white24,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(item.icon, size: indented ? 16 : 18, color: foreground),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (indented ? text.bodySmall : text.labelLarge)?.copyWith(
                      color: foreground,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (expandable)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: foreground,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ท้าย sidebar: ผู้ใช้ที่ล็อกอินอยู่ + ปุ่มออกจากระบบ
class _SidebarUser extends StatelessWidget {
  const _SidebarUser({this.username, this.role, this.onLogout});

  final String? username;
  final String? role;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UserAvatar(username: username, size: 32),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      username ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(color: Colors.white, height: 1.2),
                    ),
                    Text(
                      roleLabel(role),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(
                        color: AppColors.onNavMuted,
                        fontWeight: FontWeight.w400,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onLogout != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('ออกจากระบบ'),
              onPressed: onLogout,
              // ธีมกลางตั้งพื้นปุ่มเป็นสีขาวไว้สำหรับปุ่มบนการ์ด — บน sidebar พื้นเข้ม
              // ต้องล้างเป็นโปร่งใสด้วย ไม่งั้นได้กล่องขาวที่ตัวอักษร/ไอคอนขาวหายไปในพื้น
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ).copyWith(
                // ไล่ระดับตอน hover/กด ให้รู้ว่ากดได้ เหมือนเมนูช่องอื่นบนแถบเดียวกัน
                overlayColor: WidgetStateProperty.all(Colors.white24),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// แถบบนบาง ๆ เหนือเนื้อหา — พื้นฟ้าตัวขาวตาม mockup
///
/// ปุ่มพับ sidebar · ชื่อหน้า/ชื่อระบบ · กระดิ่งแจ้งเตือน · ชื่อผู้ใช้ + ป้ายบทบาท ·
/// ปุ่มออกจากระบบ
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.title,
    this.onToggleSidebar,
    this.onBack,
    this.username,
    this.role,
    this.onLogout,
  });

  /// ชื่อหน้าที่กำลังเปิด — หน้าที่มีหัวข้อของตัวเองอยู่แล้วไม่ต้องส่ง จะขึ้น
  /// ชื่อระบบแทน ไม่งั้นชื่อเดียวกันจะซ้ำสองที่ติดกัน
  final String? title;

  /// พับ/กาง sidebar (จอแคบคือเปิด drawer)
  final VoidCallback? onToggleSidebar;

  /// ปุ่มย้อนกลับ (หน้าที่เปิดซ้อนขึ้นมา)
  final VoidCallback? onBack;

  final String? username;
  final String? role;

  /// ออกจากระบบ — อยู่บนแถบบนด้วย ไม่ใช่แค่ท้าย sidebar เพราะ sidebar พับเก็บได้
  /// และจอแคบมันซ่อนเป็น drawer ถ้ามีที่เดียวผู้ใช้จะออกจากระบบไม่ได้เลย
  final VoidCallback? onLogout;

  static const double _height = 52;

  /// แคบกว่านี้ซ่อนชื่อผู้ใช้ เหลือแค่ป้ายบทบาท ไม่งั้นแถวบนล้นบนมือถือเล็ก
  static const double _usernameBreakpoint = 480;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Material(
      color: AppColors.blue,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: _height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showUsername = constraints.maxWidth >= _usernameBreakpoint &&
                  (username?.isNotEmpty ?? false);

              return Row(
                children: [
                  if (onToggleSidebar != null)
                    IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      tooltip: 'เมนู',
                      onPressed: onToggleSidebar,
                    )
                  else
                    const SizedBox(width: AppSpacing.lg),
                  if (onBack != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'ย้อนกลับ',
                      onPressed: onBack,
                    ),
                  Expanded(
                    child: Text(
                      title ?? kAppBrandTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(color: Colors.white),
                    ),
                  ),
                  const _NotificationBell(),
                  if (showUsername) ...[
                    const SizedBox(width: AppSpacing.xs),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        username!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge?.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.sm),
                  _RolePill(role: role),
                  if (onLogout != null)
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      tooltip: 'ออกจากระบบ',
                      onPressed: onLogout,
                    )
                  else
                    const SizedBox(width: AppSpacing.lg),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ป้ายบทบาททรงแคปซูลพื้นขาวตัวฟ้า
class _RolePill extends StatelessWidget {
  const _RolePill({this.role});

  final String? role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        roleLabel(role),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: AppColors.blue, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// กระดิ่งแจ้งเตือน
///
/// ระบบยังไม่มีแหล่งการแจ้งเตือนจริง กดแล้วจึงบอกตรง ๆ ว่ายังไม่มี และไม่ใส่จุดแดง
/// หลอกว่ามีของใหม่
class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'การแจ้งเตือน',
      icon: const Icon(Icons.notifications_none, color: Colors.white),
      itemBuilder: (context) => const [
        PopupMenuItem<void>(enabled: false, child: Text('ยังไม่มีการแจ้งเตือน')),
      ],
    );
  }
}
