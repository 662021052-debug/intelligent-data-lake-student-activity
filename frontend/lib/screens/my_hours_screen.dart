import 'package:flutter/material.dart';

import '../models/hour_summary.dart';
import '../services/api_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/hour_summary_view.dart';

class MyHoursScreen extends StatefulWidget {
  const MyHoursScreen({super.key});

  @override
  State<MyHoursScreen> createState() => _MyHoursScreenState();
}

class _MyHoursScreenState extends State<MyHoursScreen> {
  List<HourCategorySummary> _categories = [];
  bool _loading = false;
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
      final categories = await ApiService.fetchList(
        '/students/me/hours-summary',
        HourCategorySummary.fromJson,
      );
      setState(() => _categories = categories);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ชั่วโมงสะสมของฉัน'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'โหลดใหม่',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _categories.isEmpty
                  ? const EmptyState(
                      icon: Icons.timelapse,
                      title: 'ยังไม่มีข้อมูลชั่วโมง',
                      message: 'เมื่อหลักฐานการเข้าร่วมได้รับการอนุมัติ ชั่วโมงจะแสดงที่นี่',
                    )
                  : HourSummaryView(categories: _categories),
    );
  }
}
