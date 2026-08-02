import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/pending_checkin.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await authService.login(_usernameController.text.trim(), _passwordController.text);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.school, size: 64, color: Colors.indigo),
                  const SizedBox(height: 12),
                  Text(
                    'Intelligent Data Lake',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text('ระบบจัดการข้อมูลกิจกรรมนิสิต', textAlign: TextAlign.center),
                  // มาจากการสแกน QR แล้วยังไม่ได้ล็อกอิน — บอกให้รู้ว่าทำไมต้อง
                  // ล็อกอินก่อน และย้ำว่าลิงก์ที่สแกนมาไม่หาย (F4b)
                  if (pendingCheckin.hasPending) ...[
                    const SizedBox(height: 16),
                    const _PendingCheckinBanner(),
                  ],
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อผู้ใช้',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'กรอกชื่อผู้ใช้' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'รหัสผ่าน',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                    validator: (v) => (v == null || v.isEmpty) ? 'กรอกรหัสผ่าน' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('เข้าสู่ระบบ'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingCheckinBanner extends StatelessWidget {
  const _PendingCheckinBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StatusPalette.info.background,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.qr_code_scanner, size: 20, color: StatusPalette.info.foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'เข้าสู่ระบบด้วยบัญชีนิสิตเพื่อเช็กอินกิจกรรมที่สแกนมา '
              'ระบบจะพาไปหน้ายืนยันให้เองหลังเข้าสู่ระบบ',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: StatusPalette.info.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
