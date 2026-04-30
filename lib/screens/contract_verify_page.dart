import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../services/marketing_flow_service.dart';
import '../widgets/app_logo_loading.dart';

/// صفحة تحقق بسيطة من عقد تسويق (رابط الويب / QR). يعتمد على صلاحيات RLS للمستخدم الحالي.
class ContractVerifyPage extends StatefulWidget {
  const ContractVerifyPage({
    super.key,
    required this.contractId,
    required this.lang,
  });

  final String contractId;
  final String lang;

  @override
  State<ContractVerifyPage> createState() => _ContractVerifyPageState();
}

class _ContractVerifyPageState extends State<ContractVerifyPage> {
  final _flow = MarketingFlowService(Supabase.instance.client);

  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _row;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final c = await _flow.contractById(widget.contractId.trim());
      if (!mounted) return;
      setState(() {
        _row = c == null ? null : Map<String, dynamic>.from(c);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isAr ? 'التحقق من العقد' : 'Contract verification',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final pad = EdgeInsets.symmetric(
                horizontal: (c.maxWidth >= 600 ? 24.0 : 16.0).clamp(12.0, 32.0),
                vertical: 12,
              );
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppConfig.maxContentWidth,
                  ),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: AppLogoLoading()),
                        )
                      : SingleChildScrollView(
                          padding: pad,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${_isAr ? 'رقم العقد' : 'Contract ID'}:',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                widget.contractId,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: cs.onSurface,
                                ),
                                strutStyle: const StrutStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  forceStrutHeight: true,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (_err != null)
                                Text(
                                  _err!,
                                  style: TextStyle(
                                    color: cs.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              else if (_row == null)
                                Text(
                                  _isAr
                                      ? 'لا يمكن عرض هذا العقد. قد لا يكون موجوداً أو ليست لديك صلاحية (سجّل الدخول كطرف في العقد).'
                                      : 'This contract could not be shown. It may not exist or you lack access (sign in as a party).',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                )
                              else ...[
                                _line(
                                  _isAr ? 'الحالة' : 'Status',
                                  (_row!['status'] ?? '—').toString(),
                                  cs,
                                ),
                                _line(
                                  _isAr ? 'توقيع المالك' : 'Owner signed',
                                  _row!['owner_signed_at'] != null
                                      ? _row!['owner_signed_at'].toString()
                                      : (_isAr ? 'لا' : 'No'),
                                  cs,
                                ),
                                _line(
                                  _isAr ? 'توقيع المسوّق' : 'Marketer signed',
                                  _row!['marketer_signed_at'] != null
                                      ? _row!['marketer_signed_at'].toString()
                                      : (_isAr ? 'لا' : 'No'),
                                  cs,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _isAr
                                      ? 'للمقارنة، استخدم نسخة PDF المصدَّرة من داخل محادثة العقد بعد اكتمال التوقيعين.'
                                      : 'Compare with the PDF exported from contract chat after both parties sign.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _line(String k, String v, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            k,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.primary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            v,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
