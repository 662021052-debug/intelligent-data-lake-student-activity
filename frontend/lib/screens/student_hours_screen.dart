import 'package:flutter/material.dart';

import '../models/hour_summary.dart';
import '../services/api_service.dart';
import '../utils/api_error.dart';
import '../widgets/hour_summary_view.dart';

/// Read-only view of a single student's accumulated hours, opened from the
/// at-risk table on the dashboard. Uses GET /students/{id}/hours-summary.
class StudentHoursScreen extends StatefulWidget {
  final int studentId;
  final String studentName;

  const StudentHoursScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentHoursScreen> createState() => _StudentHoursScreenState();
}

class _StudentHoursScreenState extends State<StudentHoursScreen> {
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
        '/students/${widget.studentId}/hours-summary',
        HourCategorySummary.fromJson,
      );
      setState(() => _categories = categories);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ชั่วโมงสะสม: ${widget.studentName}'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : HourSummaryView(categories: _categories, showSubcategories: false),
    );
  }
}
