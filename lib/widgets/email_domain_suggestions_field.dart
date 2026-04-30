import 'package:flutter/material.dart';

/// After typing `@`, shows common domains the user can tap to complete the address.
class EmailDomainSuggestionsField extends StatefulWidget {
  const EmailDomainSuggestionsField({
    super.key,
    required this.controller,
    this.labelText = 'البريد الإلكتروني',
    this.hintText,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final bool readOnly;

  static const List<String> domains = [
    'gmail.com',
    'outlook.com',
    'hotmail.com',
    'yahoo.com',
    'icloud.com',
    'proton.me',
    'protonmail.com',
  ];

  @override
  State<EmailDomainSuggestionsField> createState() =>
      _EmailDomainSuggestionsFieldState();
}

class _EmailDomainSuggestionsFieldState
    extends State<EmailDomainSuggestionsField> {
  bool _showDomains = false;

  void _onChanged(String v) {
    final at = v.lastIndexOf('@');
    if (at < 0) {
      setState(() => _showDomains = false);
      return;
    }
    final after = v.substring(at + 1);
    if (after.contains(' ') || after.contains(',')) {
      setState(() => _showDomains = false);
      return;
    }
    setState(() => _showDomains = true);
  }

  void _pickDomain(String domain) {
    final v = widget.controller.text;
    final at = v.lastIndexOf('@');
    if (at < 0) return;
    final local = v.substring(0, at + 1);
    final next = '$local$domain';
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() => _showDomains = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          readOnly: widget.readOnly,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
          ),
          onChanged: widget.readOnly ? null : _onChanged,
        ),
        if (_showDomains && !widget.readOnly) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in EmailDomainSuggestionsField.domains)
                ActionChip(
                  label: Text(d, style: const TextStyle(fontSize: 12)),
                  onPressed: () => _pickDomain(d),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
