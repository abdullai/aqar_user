import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/input_normalizers.dart';
import '../services/account_completion_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/field_group_frame.dart';

/// استكمال الحقول الناقصة فقط — الحقول الأخرى للقراءة.
class MandatoryDataCompletionScreen extends StatefulWidget {
  final String lang;
  final VoidCallback onDone;

  const MandatoryDataCompletionScreen({
    super.key,
    required this.lang,
    required this.onDone,
  });

  @override
  State<MandatoryDataCompletionScreen> createState() =>
      _MandatoryDataCompletionScreenState();
}

class _MandatoryDataCompletionScreenState
    extends State<MandatoryDataCompletionScreen> {
  static const Color _bankColor = Color(0xFF0F766E);

  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _err;
  Map<String, dynamic>? _row;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AccountCompletionService.loadRow(Supabase.instance.client);
    if (!mounted) return;
    setState(() => _row = r);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await AccountCompletionService.saveUnifiedNational(
        sb: Supabase.instance.client,
        tenDigits700: _ctrl.text,
      );
      if (!mounted) return;
      widget.onDone();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = _isAr
            ? 'الرقم الوطني الموحّد يجب أن يكون 10 أرقام تبدأ بـ 700.'
            : 'Unified national number must be 10 digits starting with 700.';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_err ?? (_isAr ? 'تعذر الحفظ' : 'Could not save'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final un = _row == null
        ? ''
        : digitsOnly(
            normalizeAsciiDigits(
              (_row!['username'] ?? '').toString(),
            ),
          );
    final lic = _row == null
        ? ''
        : digitsOnly(
            normalizeAsciiDigits(
              (_row!['license_no'] ?? '').toString(),
            ),
          );

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isAr ? 'استكمال البيانات' : 'Complete your profile',
          ),
        ),
        body: _row == null
            ? const Center(child: AppLogoLoading())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _isAr
                        ? 'يُطلب الرقم الوطني الموحّد (10 أرقام تبدأ بـ 700) لحسابات التسويق والجهات المهنية.'
                        : 'Unified national number (10 digits starting with 700) is required for marketing/pro accounts.',
                    style: const TextStyle(height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  if (un.length == 10) ...[
                    Text(
                      _isAr ? 'اسم المستخدم المخزّن (للقراءة)' : 'Stored username (read-only)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: TextEditingController(text: un),
                      readOnly: true,
                      decoration: const InputDecoration(
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (lic.length == 10) ...[
                    Text(
                      _isAr ? 'رخصة فال المسجّلة (للقراءة)' : 'FAL license on file (read-only)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: TextEditingController(text: lic),
                      readOnly: true,
                      decoration: const InputDecoration(
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FieldGroupFrame(
                    title: _isAr
                        ? 'الرقم الوطني الموحّد'
                        : 'Unified national number',
                    subtitle: _isAr
                        ? 'عشرة أرقام تبدأ بـ 700'
                        : '10 digits starting with 700',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _ctrl,
                          keyboardType: TextInputType.text,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9٠-٩۰-۹\u0646]'),
                            ),
                            LengthLimitingTextInputFormatter(13),
                          ],
                          decoration: InputDecoration(
                            hintText: _isAr
                                ? 'مثال: ن7001234567 أو 7001234567'
                                : 'e.g. 7001234567',
                          ),
                        ),
                        if (_err != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _err!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _bankColor,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _busy ? null : _save,
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Text(_isAr ? 'حفظ' : 'Save'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
