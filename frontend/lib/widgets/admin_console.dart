import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ชิ้นส่วนของ "แดชบอร์ดคอนโซล" ที่เป็นหน้าแรกของแอดมิน
///
/// แยกออกมาจาก `dashboard_screen.dart` เพราะชิ้นส่วนพวกนี้รับข้อมูลทางพารามิเตอร์
/// ล้วน ๆ ไม่ยิง API เอง จึงเทสต์ทีละชิ้นได้โดยไม่ต้องจำลองทั้งหน้า

/// ปุ่มลัดหนึ่งปุ่มบนแถวบนสุดของคอนโซล
class ConsoleShortcut {
  const ConsoleShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// กำลังทำงานอยู่ (เช่นรีเฟรช Gold) — ปุ่มถูกปิดและขึ้นวงหมุนแทนไอคอน
  final bool busy;
}

/// แถวปุ่มลัดไปหน้าที่แอดมินใช้บ่อย
///
/// คอนโซลแทนที่แผงการ์ดเมนูเดิมของหน้าแรก ปุ่มพวกนี้จึงต้องครอบคลุม *ทุกหน้า*
/// ที่เคยเข้าได้จากแผงนั้น ไม่งั้นหน้าที่ไม่มีอยู่บนเมนู sidebar (นิสิต ปฏิทิน
/// การเข้าร่วม) จะกลายเป็นหน้ากำพร้าที่ไม่มีทางเข้าถึงเลย
class ConsoleShortcutBar extends StatelessWidget {
  const ConsoleShortcutBar({super.key, required this.shortcuts});

  final List<ConsoleShortcut> shortcuts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final s in shortcuts)
          OutlinedButton.icon(
            onPressed: s.busy ? null : s.onTap,
            icon: s.busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(s.icon, size: 18),
            label: Text(s.label),
          ),
      ],
    );
  }
}

/// แถบคู่มือพื้นน้ำเงินเข้มเหนือตัวเลขทั้งหมด
///
/// ปุ่มพาไปที่คู่มือจริง ๆ ([showAdminGuide]) ไม่ใช่ปุ่มหลอกที่กดแล้วไม่เกิดอะไร
class GuideBanner extends StatelessWidget {
  const GuideBanner({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final label = Row(
      children: [
        // ไอคอนในกล่องขาวโปร่งตาม mockup — ไอคอนขาวเปล่าบนพื้นน้ำเงินเข้มดูจมไปกับพื้น
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: const Icon(Icons.menu_book_outlined, color: Colors.white, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'คู่มือการใช้งานสำหรับ Admin',
                style: text.titleSmall?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'ตั้งแต่ตั้งค่ากิจกรรมจนออกใบประมวลผล',
                style: text.bodySmall?.copyWith(color: AppColors.onNav),
              ),
            ],
          ),
        ),
      ],
    );

    final button = FilledButton(
      onPressed: onOpen,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.blueDark,
      ),
      child: const Text('เปิดคู่มือ →'),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.blueDark,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // จอแคบวางปุ่มไว้ใต้ข้อความ — วางข้างกันจะบีบข้อความจนอ่านไม่ออกหรือล้นออกนอกจอ
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [label, const SizedBox(height: AppSpacing.md), button],
            );
          }
          return Row(
            children: [
              Expanded(child: label),
              const SizedBox(width: AppSpacing.lg),
              button,
            ],
          );
        },
      ),
    );
  }
}

/// หนึ่งหัวข้อในคู่มือ — แยกเป็นข้อมูลเพื่อให้เทสต์ยืนยันได้ว่าคู่มือมีเนื้อหาจริง
class GuideSection {
  const GuideSection(this.title, this.body);

  final String title;
  final String body;
}

/// เนื้อหาคู่มือ — อธิบายสิ่งที่ระบบทำจริงตามที่เขียนไว้ในโค้ด ไม่ใช่ข้อความหลอก
const List<GuideSection> adminGuideSections = [
  GuideSection(
    'งานประจำของผู้ดูแล',
    'เจ้าหน้าที่สร้างกิจกรรมแล้วรอผู้ดูแลอนุมัติ · นิสิตสมัคร เช็กอิน แล้วอัปโหลด'
        'หลักฐาน · ผู้ดูแลตรวจหลักฐานให้ผ่านหรือไม่ผ่าน ชั่วโมงจะถูกนับเมื่อหลักฐาน'
        'ผ่านแล้วเท่านั้น',
  ),
  GuideSection(
    'ตัวเลขบนแดชบอร์ดมาจากไหน',
    'ทุกตัวเลขอ่านจาก Gold Layer (วิว gold_*) ไม่ได้อ่านจากตารางหลักโดยตรง '
        '"ผ่านเกณฑ์" หมายถึงครบทุกรายการของชุดเกณฑ์ที่นิสิตคนนั้นสังกัด ไม่ใช่แค่'
        'ชั่วโมงรวมถึงเป้า — ชั่วโมงที่เกินในรายการหนึ่งไม่ไปชดเชยรายการที่ยังขาด',
  ),
  GuideSection(
    'ต้องรีเฟรช Gold เมื่อไร',
    'วิว gold_* ถูกสร้างใหม่ตอนระบบบูตอยู่แล้ว กด "รีเฟรช Gold" เมื่อเพิ่งแก้'
        'โครงเกณฑ์/หมวดชั่วโมง แล้วอยากให้ตัวเลขบนแดชบอร์ดตรงทันทีโดยไม่ต้องรีสตาร์ต',
  ),
  GuideSection(
    'กลุ่มเสี่ยงและการแจ้งเตือน',
    'กลุ่มเสี่ยงคือนิสิตที่ความคืบหน้ายังไม่ถึงเกณฑ์ที่ตั้งไว้ (ค่าเริ่มต้น 50%) '
        'ส่งอีเมลเตือนได้จากหน้าการเข้าร่วมกิจกรรม',
  ),
  GuideSection(
    'ออกใบประมวลผล',
    'ปุ่ม Excel/PDF มุมขวาบนของหน้านี้ออกรายงานชั่วโมง "สะสม" ตามคณะ/ชั้นปีที่กรองอยู่ '
        '(รายงานไม่มีตัวกรองภาคเรียน ต่างจากตัวเลขบนหน้าจอ)',
  ),
];

/// เปิดคู่มือผู้ดูแลเป็นกล่องข้อความ
///
/// ใช้กล่องแทนการทำเป็นหน้าแยก เพราะคู่มือไม่มีเมนูของตัวเองบน sidebar — ทำเป็น
/// หน้าจะกลายเป็นหน้าที่เข้าได้ทางเดียวและไฮไลต์เมนูผิดตัว
Future<void> showAdminGuide(BuildContext context) {
  final text = Theme.of(context).textTheme;

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('คู่มือการใช้งานสำหรับ Admin'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final section in adminGuideSections) ...[
                Text(section.title, style: text.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  section.body,
                  style: text.bodyMedium?.copyWith(color: AppColors.sub, height: 1.5),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ปิด')),
      ],
    ),
  );
}

/// จำนวนงานค้างที่การ์ดสรุปสองใบใช้ร่วมกัน
class ConsoleCounts {
  const ConsoleCounts({
    this.pendingActivities = 0,
    this.pendingEvidence = 0,
    this.approvedToday = 0,
  });

  /// กิจกรรมที่เจ้าหน้าที่สร้างไว้และยังรอผู้ดูแลอนุมัติ
  final int pendingActivities;

  /// หลักฐานการเข้าร่วมที่ยังรอตรวจ
  final int pendingEvidence;

  /// กิจกรรมที่อนุมัติไปแล้ววันนี้ — ตัวชี้ว่าคิวเดินอยู่ ไม่ใช่ค้างนิ่ง
  final int approvedToday;

  int get outstanding => pendingActivities + pendingEvidence;
}

/// การ์ด "ภาพรวมสถานะ" — ตัวเลขสามตัวที่บอกว่าคิวงานตอนนี้เป็นยังไง
class StatusOverviewCard extends StatelessWidget {
  const StatusOverviewCard({super.key, required this.counts});

  final ConsoleCounts counts;

  @override
  Widget build(BuildContext context) {
    return _ConsoleCard(
      title: 'ภาพรวมสถานะ',
      child: Column(
        children: [
          _StatRow(
            label: 'รออนุมัติกิจกรรม',
            value: counts.pendingActivities,
            // ศูนย์แปลว่าไม่มีอะไรค้าง ไม่ใช่เรื่องต้องเตือน — สีเตือนเก็บไว้ให้เลขที่ยังค้างจริง
            color: counts.pendingActivities > 0 ? AppColors.warning : AppColors.muted,
          ),
          _StatRow(
            label: 'หลักฐานรอตรวจ',
            value: counts.pendingEvidence,
            color: counts.pendingEvidence > 0 ? AppColors.warning : AppColors.muted,
          ),
          _StatRow(
            label: 'อนุมัติแล้ววันนี้',
            value: counts.approvedToday,
            color: counts.approvedToday > 0 ? AppColors.success : AppColors.muted,
          ),
        ],
      ),
    );
  }
}

/// งานหนึ่งอย่างที่รอผู้ดูแลทำ พร้อมทางไปหน้าที่ทำได้จริง
class TodoItem {
  const TodoItem({required this.label, required this.count, required this.onTap});

  /// ข้อความของงาน — ใส่จำนวนไว้ในประโยคเลยตาม mockup ("อนุมัติ 3 กิจกรรมใหม่")
  final String label;

  /// จำนวนงานที่ค้าง — 0 คือไม่ต้องขึ้นรายการนี้
  final int count;
  final VoidCallback onTap;
}

/// การ์ด "งานที่ต้องดำเนินการ" — เฉพาะงานที่ยังค้างจริง พร้อมลิงก์ไปหน้าที่เกี่ยว
class TodoCard extends StatelessWidget {
  const TodoCard({super.key, required this.items});

  final List<TodoItem> items;

  @override
  Widget build(BuildContext context) {
    // ไม่แสดงงานที่จำนวนเป็นศูนย์ — รายการที่กดไปแล้วไม่มีอะไรให้ทำคือการหลอกให้กด
    final pending = items.where((i) => i.count > 0).toList();
    final text = Theme.of(context).textTheme;

    return _ConsoleCard(
      title: 'งานที่ต้องดำเนินการ',
      child: pending.isEmpty
          ? Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'เคลียร์หมดแล้ว ไม่มีกิจกรรมหรือหลักฐานค้างรอผู้ดูแล',
                    style: text.bodyMedium?.copyWith(color: AppColors.sub),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in pending)
                  InkWell(
                    onTap: item.onTap,
                    borderRadius: BorderRadius.circular(AppRadius.field),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.label,
                              style: text.bodyMedium?.copyWith(color: AppColors.sub),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            'ดู →',
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// การ์ดของคอนโซล — หัวการ์ดเป็นแถบพื้นน้ำเงินเข้มตัวขาวตาม mockup
class _ConsoleCard extends StatelessWidget {
  const _ConsoleCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.blueDark,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text(
              title,
              style: text.titleSmall?.copyWith(color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// หนึ่งแถวของ "ภาพรวมสถานะ": ป้ายชื่อซ้าย จำนวนตัวหนาสีตามสถานะชิดขวา
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.sub)),
          ),
          Text(
            '$value',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
