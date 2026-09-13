import 'package:flutter/material.dart';

import '../core/gestures/app_keyboard_inset.dart';
import '../core/navigation/safe_overlay_pop.dart';
import '../l10n/app_localizations.dart';
import '../screens/support_page.dart';
import '../widgets/app_page_close_button.dart';
import 'support/complaint_submit_form.dart';
import 'support/support_tickets_panel.dart';

/// جسم الدعم: مساعدة + شكوى داخل التطبيق + تذاكر.
class SupportHubTabs extends StatefulWidget {
  const SupportHubTabs({
    super.key,
    required this.userId,
    required this.isAr,
    required this.bankColor,
    this.helpScrollController,
  });

  final String userId;
  final bool isAr;
  final Color bankColor;
  final ScrollController? helpScrollController;

  @override
  State<SupportHubTabs> createState() => _SupportHubTabsState();
}

class _SupportHubTabsState extends State<SupportHubTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _ticketsKey = GlobalKey<SupportTicketsPanelState>();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _goToTickets() {
    _tabCtrl.animateTo(2);
    _ticketsKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: l10n.supportHubTechnicalTab),
            Tab(text: l10n.supportHubComplaintTab),
            Tab(text: l10n.supportHubTicketsTab),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              SupportPage(
                userId: widget.userId,
                isAr: widget.isAr,
                bankColor: widget.bankColor,
                wrapInScaffold: false,
                hideComplaintForm: true,
                scrollController: widget.helpScrollController,
              ),
              ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  ComplaintSubmitForm(
                    isAr: widget.isAr,
                    userId: widget.userId,
                    accentColor: widget.bankColor,
                    onSubmittedInApp: _goToTickets,
                  ),
                ],
              ),
              SupportTicketsPanel(
                key: _ticketsKey,
                isAr: widget.isAr,
                userId: widget.userId,
                accentColor: widget.bankColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// محتوى الدعم مع تبويبات كاملة — يُستخدم داخل التراكب أو تبويب اللوحة.
class SupportHubBody extends StatelessWidget {
  const SupportHubBody({
    super.key,
    required this.userId,
    required this.isAr,
    required this.accentColor,
    this.onLogin,
    this.helpScrollController,
    this.showChatInbox = false,
  });

  final String userId;
  final bool isAr;
  final Color accentColor;
  final VoidCallback? onLogin;
  final ScrollController? helpScrollController;
  final bool showChatInbox;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (userId.isEmpty) {
      return ListView(
        controller: helpScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        children: [
          const SizedBox(height: 24),
          Icon(
            Icons.lock_outline,
            size: 84,
            color: cs.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.supportHubNeedLogin,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (onLogin != null)
            Center(
              child: ElevatedButton(
                onPressed: onLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: Text(
                  l10n.loginNowLabel,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      );
    }

    return SupportHubTabs(
      userId: userId,
      isAr: isAr,
      bankColor: accentColor,
      helpScrollController: helpScrollController,
    );
  }
}

/// شاشة دعم كاملة فوق التبويبات — X يعيد الصفحة السابقة.
class SupportHubScreen extends StatelessWidget {
  const SupportHubScreen({
    super.key,
    required this.userId,
    required this.isAr,
    required this.accentColor,
    this.onLogin,
  });

  final String userId;
  final bool isAr;
  final Color accentColor;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: AppPageCloseButton(
          isArabic: isAr,
          onPressed: () => SafeOverlayPop.pop(context),
        ),
        title: Text(l10n.supportLabel),
      ),
      body: AppKeyboardPad(
        child: SupportHubBody(
          userId: userId,
          isAr: isAr,
          accentColor: accentColor,
          onLogin: onLogin,
        ),
      ),
    );
  }
}
