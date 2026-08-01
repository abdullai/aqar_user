import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/account_completion_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/profile_completion_sheet.dart';

/// بوابة موحّدة لاستكمال بيانات الملف (جوال / اسم الظهور / هوية / رخصة فال).
/// لا تُعرض للمستخدم إلا عند وجود نواقص حقيقية؛ عند الاكتمال تُغلق فوراً.
class ProfileEnrollmentGateScreen extends StatefulWidget {
  const ProfileEnrollmentGateScreen({
    super.key,
    required this.lang,
    this.onOpenSettings,
    this.onRecheck,
    this.onRemindLater,
    this.embeddedInSettings = false,
  });

  final String lang;
  /// لم يعد يُستخدم كمسار أساسي — الاستكمال عبر النافذة المنبثقة.
  final VoidCallback? onOpenSettings;
  final Future<void> Function()? onRecheck;
  final Future<void> Function()? onRemindLater;

  /// عند الفتح من الإعدادات — لا حاجة لزر «ذكرني لاحقاً» إن رغبت بالإخفاء لاحقاً.
  final bool embeddedInSettings;

  @override
  State<ProfileEnrollmentGateScreen> createState() =>
      _ProfileEnrollmentGateScreenState();
}

class _ProfileEnrollmentGateScreenState
    extends State<ProfileEnrollmentGateScreen> {
  List<String>? _missing;
  Map<String, dynamic>? _row;
  bool _loading = true;
  bool _reminding = false;
  bool _rechecking = false;
  bool _completingPass = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  bool get _canRemindLater =>
      !widget.embeddedInSettings &&
      AccountCompletionService.allowRemindLater(_row);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _passThroughComplete() async {
    if (_completingPass) return;
    _completingPass = true;
    try {
      await AccountCompletionService.clearEnrollmentDeferred();
      final recheck = widget.onRecheck;
      if (recheck != null) await recheck();
      if (widget.embeddedInSettings && mounted) {
        Navigator.of(context).maybePop(true);
      }
    } finally {
      _completingPass = false;
    }
  }

  Future<void> _load({bool announceComplete = true}) async {
    setState(() => _loading = true);
    final row = await AccountCompletionService.loadRow(Supabase.instance.client);
    if (!mounted) return;
    final missing = AccountCompletionService.missingFieldLabels(
      row,
      isAr: _isAr,
      includeFalWeekWarning: false,
    );
    // لا نواقص → لا تُعرض هذه الشاشة؛ مرّر للوحة فوراً.
    if (missing.isEmpty) {
      setState(() {
        _row = row;
        _missing = missing;
        _rechecking = false;
        // أبقِ مؤشر التحميل أثناء الانتقال حتى لا تظهر رسالة «لا نواقص».
      });
      await _passThroughComplete();
      return;
    }
    setState(() {
      _row = row;
      _missing = missing;
      _loading = false;
      _rechecking = false;
    });
    if (!announceComplete) return;
  }

  Future<void> _openCompleteSheet() async {
    final done = await ProfileCompletionSheet.show(
      context,
      lang: widget.lang,
      initialRow: _row,
    );
    await _load(announceComplete: false);
    if (!mounted) return;
    if (done == true || (_missing ?? const []).isEmpty) {
      await _passThroughComplete();
    } else {
      await widget.onRecheck?.call();
    }
  }

  Future<void> _recheck() async {
    setState(() => _rechecking = true);
    await _load(announceComplete: true);
    if (!mounted) return;
    if ((_missing ?? const []).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'ما زالت هناك نواقص — أكملها من الزر أعلاه.'
                : 'Still incomplete — use Complete data above.',
          ),
        ),
      );
    }
  }

  Future<void> _remindLater() async {
    if (_reminding || !_canRemindLater) return;
    setState(() => _reminding = true);
    try {
      await widget.onRemindLater?.call();
    } finally {
      if (mounted) setState(() => _reminding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mustComplete = !_canRemindLater && !widget.embeddedInSettings;
    final missing = _missing ?? const <String>[];

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isAr ? 'استكمال الملف الشخصي' : 'Complete your profile',
          ),
        ),
        body: _loading
            ? const Center(child: AppLogoLoading())
            : ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  Icon(
                    Icons.assignment_ind_rounded,
                    size: 56,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    mustComplete
                        ? (_isAr
                            ? 'لديك بيانات أو رخصة منتهية/موقوفة. أكمل النواقص أدناه للمتابعة — لا يمكن التأجيل.'
                            : 'You have expired or suspended identity/license data. Complete the items below — deferral is not available.')
                        : (_isAr
                            ? 'بياناتك غير مكتملة أو تحتاج تحديثاً. راجع النواقص ثم اضغط «استكمال البيانات».'
                            : 'Your profile is incomplete or needs updates. Review what is missing, then tap Complete data.'),
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _isAr ? 'النواقص الحالية' : 'Currently missing',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  ...missing.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: cs.errorContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: cs.error,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  m,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _openCompleteSheet,
                      child: Text(
                        _isAr ? 'استكمال البيانات' : 'Complete data',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _rechecking ? null : _recheck,
                      child: _rechecking
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : Text(_isAr ? 'إعادة الفحص' : 'Recheck'),
                    ),
                  ),
                  if (_canRemindLater) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: _reminding ? null : _remindLater,
                        child: _reminding
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Text(
                                _isAr ? 'ذكرني لاحقاً' : 'Remind me later',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
