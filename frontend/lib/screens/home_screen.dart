import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'activities_screen.dart';
import 'chatbot_screen.dart';
import 'dashboard_screen.dart';
import 'my_hours_screen.dart';
import 'participations_screen.dart';
import 'register_activities_screen.dart';
import 'students_screen.dart';
import 'users_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('หน้าหลัก'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text('${authService.username ?? ''} (${authService.role ?? ''})'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ออกจากระบบ',
            onPressed: authService.logout,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          final cards = [
            if (authService.isAdmin)
              _MenuCard(
                icon: Icons.dashboard,
                title: 'แดชบอร์ดผู้บริหาร',
                subtitle: 'ภาพรวม KPI กราฟ และกลุ่มเสี่ยง',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DashboardScreen()),
                ),
              ),
            if (authService.isAdmin)
              _MenuCard(
                icon: Icons.people,
                title: 'นิสิต',
                subtitle: 'จัดการข้อมูลนิสิต',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StudentsScreen()),
                ),
              ),
            _MenuCard(
              icon: Icons.event,
              title: 'กิจกรรม',
              subtitle: authService.role == 'student' ? 'ดูกิจกรรมทั้งหมด' : 'จัดการข้อมูลกิจกรรม',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActivitiesScreen()),
              ),
            ),
            _MenuCard(
              icon: Icons.fact_check,
              title: 'การเข้าร่วมกิจกรรม',
              subtitle: 'บันทึกและตรวจสอบการเข้าร่วม',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ParticipationsScreen()),
              ),
            ),
            if (authService.isAdmin)
              _MenuCard(
                icon: Icons.admin_panel_settings,
                title: 'จัดการผู้ใช้',
                subtitle: 'สร้างผู้ใช้และกำหนดสิทธิ์',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UsersScreen()),
                ),
              ),
            if (authService.role == 'student')
              _MenuCard(
                icon: Icons.how_to_reg,
                title: 'สมัครกิจกรรม',
                subtitle: 'ดูกิจกรรมที่เปิดรับสมัครและสมัครเข้าร่วม',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterActivitiesScreen()),
                ),
              ),
            if (authService.role == 'student')
              _MenuCard(
                icon: Icons.emoji_events,
                title: 'ชั่วโมงสะสมของฉัน',
                subtitle: 'ดูความคืบหน้าชั่วโมงกิจกรรมแต่ละหมวด',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyHoursScreen()),
                ),
              ),
            if (authService.role == 'student')
              _MenuCard(
                icon: Icons.smart_toy,
                title: 'ผู้ช่วยอัจฉริยะ',
                subtitle: 'ถามชั่วโมง หมวดที่ยังขาด และขอคำแนะนำกิจกรรม',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatbotScreen()),
                ),
              ),
          ];
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: cards
                    .map((c) => SizedBox(width: isWide ? 280 : double.infinity, child: c))
                    .toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
