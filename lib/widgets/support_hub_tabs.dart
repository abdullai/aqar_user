import 'package:flutter/material.dart';

import '../screens/support_page.dart';
import 'support/complaint_submit_form.dart';
import 'support/support_tickets_panel.dart';

/// تبويبات الدعم: الدعم الفني + الإدارة + التذاكر.
class SupportHubTabs extends StatefulWidget {
  const SupportHubTabs({
    super.key,
    required this.userId,
    required this.isAr,
    required this.bankColor,
    required this.adminSoonLabel,
    required this.initialTabHeight,
  });

  final String userId;
  final bool isAr;
  final Color bankColor;
  final String adminSoonLabel;
  final double initialTabHeight;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: widget.isAr ? 'الدعم الفني' : 'Help center'),
            Tab(text: widget.isAr ? 'الإدارة' : 'Administration'),
            Tab(text: widget.isAr ? 'التذاكر' : 'Tickets'),
          ],
        ),
        SizedBox(
          height: widget.initialTabHeight,
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  ComplaintSubmitForm(
                    isAr: widget.isAr,
                    userId: widget.userId,
                    accentColor: widget.bankColor,
                    onSubmittedInApp: _goToTickets,
                  ),
                  const SizedBox(height: 16),
                  SupportPage(
                    userId: widget.userId,
                    isAr: widget.isAr,
                    bankColor: widget.bankColor,
                    wrapInScaffold: false,
                    hideComplaintForm: true,
                  ),
                ],
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    widget.adminSoonLabel,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                  ),
                ),
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
