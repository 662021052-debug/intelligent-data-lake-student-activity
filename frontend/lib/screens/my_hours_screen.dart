import 'package:flutter/material.dart';

import '../models/hour_summary.dart';
import '../services/api_service.dart';
import '../utils/format.dart';

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
    final totalRequired = _categories.fold<double>(0, (sum, c) => sum + c.requiredHours);
    final totalEarned = _categories.fold<double>(
      0,
      (sum, c) => sum + (c.earnedHours > c.requiredHours ? c.requiredHours : c.earnedHours),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('ชั่วโมงสะสมของฉัน'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('รวมทุกหมวด', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text('${formatHours(totalEarned)} / ${formatHours(totalRequired)} ชั่วโมง'),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: totalRequired == 0
                                    ? 0
                                    : (totalEarned / totalRequired).clamp(0, 1),
                                minHeight: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._categories.map(_buildCategoryCard),
                  ],
                ),
    );
  }

  Widget _buildCategoryCard(HourCategorySummary c) {
    final progress = c.requiredHours == 0 ? 0.0 : (c.earnedHours / c.requiredHours).clamp(0, 1);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (c.completed)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.check_circle, color: Colors.green, size: 20),
                  ),
                Expanded(
                  child: Text(
                    c.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${formatHours(c.earnedHours)} / ${formatHours(c.requiredHours)} ชม.'),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.toDouble(),
                minHeight: 8,
                color: c.completed ? Colors.green : null,
              ),
            ),
            const SizedBox(height: 8),
            ...c.subcategories.map(
              (s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      s.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 16,
                      color: s.completed ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.name, style: Theme.of(context).textTheme.bodySmall)),
                    Text(
                      '${formatHours(s.earnedHours)}/${formatHours(s.requiredHours)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
