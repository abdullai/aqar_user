import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/marketing_flow_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/field_group_frame.dart';

class CreateListingRequestPage extends StatefulWidget {
  const CreateListingRequestPage({super.key});

  @override
  State<CreateListingRequestPage> createState() =>
      _CreateListingRequestPageState();
}

class _CreateListingRequestPageState extends State<CreateListingRequestPage> {
  final _title = TextEditingController();
  final _city = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  bool loading = false;

  Future<void> submit() async {
    setState(() => loading = true);
    final svc = MarketingFlowService(Supabase.instance.client);

    await svc.createListingRequest(
      title: _title.text,
      city: _city.text,
      lat: double.parse(_lat.text),
      lng: double.parse(_lng.text),
    );

    if (!mounted) return;
    setState(() => loading = false);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _title.dispose();
    _city.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(t.fieldGroupListingRequestTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            FieldGroupFrame(
              title: t.fieldGroupListingRequestTitle,
              subtitle: t.fieldGroupListingRequestSubtitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _title,
                    decoration: InputDecoration(
                      labelText: t.listingRequestFieldTitleLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _city,
                    decoration: InputDecoration(
                      labelText: t.listingRequestFieldCityLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lat,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: t.listingRequestFieldLatLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lng,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: t.listingRequestFieldLngLabel,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: loading ? null : submit,
                      child: loading
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: AppLogoLoading(compact: true, size: 26),
                            )
                          : Text(t.fieldGroupListingRequestSubmit),
                    ),
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
