import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/government/nafath_models.dart';
import '../core/session/app_session.dart';
import '../services/nafath_auth_service.dart';

/// Example of the supported Nafath flow; JWT validation stays on the server.
class NafathLoginExample extends StatefulWidget {
  const NafathLoginExample({super.key});

  @override
  State<NafathLoginExample> createState() => _NafathLoginExampleState();
}

class _NafathLoginExampleState extends State<NafathLoginExample> {
  final _idController = TextEditingController();
  late final NafathAuthService _nafathService;
  String? _requestId;
  String? _random;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nafathService = NafathAuthService(Supabase.instance.client);
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final nationalId = _idController.text.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[123456]\d{9}$').hasMatch(nationalId)) {
      setState(() => _error = 'أدخل رقم هوية أو إقامة صحيحاً من 10 أرقام.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _random = null;
    });

    final result = await _nafathService.startLogin(nationalId: nationalId);
    if (!mounted) return;
    if (result.mode != NafathSessionMode.polling ||
        (result.requestId ?? '').isEmpty) {
      setState(() {
        _busy = false;
        _error = result.messageAr ?? 'تعذر بدء طلب نفاذ.';
      });
      return;
    }

    setState(() {
      _requestId = result.requestId;
      _random = result.random;
      _busy = false;
    });
    await _poll();
  }

  Future<void> _poll() async {
    final requestId = _requestId;
    if (requestId == null) return;

    setState(() => _busy = true);
    for (var attempt = 0; attempt < 150 && mounted; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final result = await _nafathService.pollStatus(requestId);
      if (!mounted) return;

      if (result.mode == NafathSessionMode.redirect &&
          result.status == 'COMPLETED') {
        await _completeLogin(result);
        return;
      }
      if (result.mode == NafathSessionMode.error ||
          result.mode == NafathSessionMode.notConfigured) {
        setState(() {
          _busy = false;
          _error = result.messageAr ?? 'تعذر التحقق من طلب نفاذ.';
        });
        return;
      }
      if ((result.random ?? '').isNotEmpty) {
        setState(() => _random = result.random);
      }
    }

    if (mounted) {
      setState(() {
        _busy = false;
        _error = 'انتهت مهلة الانتظار. ابدأ طلباً جديداً.';
      });
    }
  }

  Future<void> _completeLogin(NafathSessionResult result) async {
    final completed = await _nafathService.completeAuthenticationFlow(result);
    if (!mounted) return;
    if (completed.mode == NafathSessionMode.error) {
      setState(() {
        _busy = false;
        _error = completed.messageAr ?? 'تعذر إكمال تسجيل الدخول.';
      });
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'تم التحقق من نفاذ لكن تعذر فتح جلسة المستخدم.';
      });
      return;
    }
    await context.read<AppSession>().setUser(userId);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/userDashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الدخول عبر نفاذ')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _idController,
              decoration: const InputDecoration(
                labelText: 'رقم الهوية / الإقامة',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              enabled: !_busy,
            ),
            if (_random != null) ...[
              const SizedBox(height: 16),
              Text(
                'اختر الرقم ${_random!} في تطبيق نفاذ',
                textAlign: TextAlign.center,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _start,
              child: _busy
                  ? const CircularProgressIndicator()
                  : const Text('الدخول عبر نفاذ'),
            ),
          ],
        ),
      ),
    );
  }
}
