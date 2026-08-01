import 'package:flutter/material.dart';

class OrgRequestCard extends StatelessWidget {
  const OrgRequestCard({
    super.key,
    required this.title,
    this.message,
    required this.actions,
  });

  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            if (message != null && message!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(message!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Row(children: actions),
          ],
        ),
      ),
    );
  }
}
