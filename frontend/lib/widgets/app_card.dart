import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// การ์ดพื้นฐานของทุกหน้า — พื้นขาว ขอบเทาบาง มุมโค้ง 12 เงาบาง ๆ
///
/// ใช้แทนการเขียน `Container(decoration: BoxDecoration(...))` เองในแต่ละหน้า
/// เพื่อให้ขอบ/มุม/เงาเท่ากันหมด (ค่าทั้งหมดมาจาก `cardTheme` ของธีมกลาง)
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// การ์ดที่กดได้ (เช่น การ์ดกิจกรรมที่กดแล้วเปิดรายละเอียด)
  final VoidCallback? onTap;

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);

    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// หัวข้อของส่วนงาน: ชื่อเรื่อง + คำอธิบายย่อย + ปุ่มด้านขวา
///
/// จอแคบปุ่มจะตกลงมาอยู่บรรทัดใหม่แทนที่จะเบียดจนข้อความล้น
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;

  /// บรรทัดเล็กใต้ชื่อ เช่น "ปีการศึกษา 2569 · 33 กิจกรรม"
  final String? subtitle;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: text.titleMedium?.copyWith(fontSize: 16)),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          // บรรทัดนี้อยู่บนพื้นหน้าสีเทา ไม่ใช่บนการ์ดขาว จึงใช้สีตัวอักษรรอง
          // แทนสีจาง เพื่อให้ contrast ผ่านเกณฑ์บนพื้นที่เข้มกว่า
          Text(subtitle!, style: text.bodySmall?.copyWith(color: AppColors.sub)),
        ],
      ],
    );

    if (actions.isEmpty) return heading;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.md,
      children: [
        heading,
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
      ],
    );
  }
}

/// ข้อมูลประกอบสั้น ๆ คู่กับไอคอน เช่น "3 ชม." "เหลือ 3 ที่"
class MetaItem extends StatelessWidget {
  const MetaItem({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: text.bodySmall?.copyWith(color: AppColors.sub)),
      ],
    );
  }
}

/// แถบความคืบหน้าบาง ๆ พร้อมป้ายชื่อและตัวเลข (ชั่วโมงสะสมแยกหมวด)
///
/// สีของแถบสื่อสถานะเอง: ครบแล้ว = เขียว, เกินครึ่ง = ฟ้า, ยังน้อย = ส้ม
class ProgressRow extends StatelessWidget {
  const ProgressRow({
    super.key,
    required this.label,
    required this.value,
    required this.progress,
  });

  final String label;

  /// ข้อความตัวเลขด้านขวา เช่น "16/12"
  final String value;

  /// 0..1
  final double progress;

  /// สีแถบตามความคืบหน้า — ใช้ร่วมกันทุกหน้าที่โชว์ชั่วโมงสะสม
  static Color barColor(double progress) {
    if (progress >= 1) return StatusPalette.approved.accent;
    if (progress >= 0.5) return AppColors.blue;
    return StatusPalette.pending.accent;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final clamped = progress.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: text.bodySmall)),
            Text(value, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 6,
            backgroundColor: AppColors.page,
            valueColor: AlwaysStoppedAnimation<Color>(barColor(clamped)),
          ),
        ),
      ],
    );
  }
}

/// การ์ดที่ห่อตารางยาว ๆ — เลื่อนแนวตั้งได้ ส่วนตารางเลื่อนแนวนอนเองอยู่แล้ว
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AppCard(padding: EdgeInsets.zero, child: child),
    );
  }
}


/// พื้นที่ "ลากไฟล์มาวาง หรือเลือกไฟล์" แบบเส้นประตาม mockup
class DottedUploadArea extends StatelessWidget {
  const DottedUploadArea({super.key, required this.label, this.filename});

  final String label;

  /// ชื่อไฟล์ที่เลือกไว้แล้ว (ถ้ามี)
  final String? filename;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // เป็นกล่องกดได้ทั้งกล่อง จึงต้องประกาศว่าเป็นปุ่มด้วย ไม่งั้นโปรแกรมอ่าน
    // หน้าจอจะเห็นเป็นแค่ข้อความ กดไม่ได้
    return Semantics(
      button: true,
      label: label,
      child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        border: Border.all(color: const Color(0xFFC7D0DA), width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 28, color: AppColors.blue),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: AppColors.sub),
          ),
          if (filename != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              filename!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ],
        ],
      ),
      ),
    );
  }
}
