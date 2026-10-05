import 'package:flutter/material.dart';

import '../services/services.dart';
import '../ui/format.dart';
import '../widgets/common.dart';

/// "Not right?" - lets the user flag a wrong identification for the admin review queue.
Future<void> showReportSheet(BuildContext context, String identificationId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _ReportForm(identificationId: identificationId),
    ),
  );
}

class _ReportForm extends StatefulWidget {
  const _ReportForm({required this.identificationId});

  final String identificationId;

  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> {
  String _reason = 'wrong_match';
  final _name = TextEditingController();
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final thanks = context.l10n.reportThanks;
    setState(() => _sending = true);
    try {
      await services.api.reportResult(
        identificationId: widget.identificationId,
        reason: _reason,
        suggestedName: _name.text,
        note: _note.text,
      );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(thanks)));
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        messenger.showSnackBar(SnackBar(content: Text(errorMessage(context, e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reasons = {
      'wrong_match': l10n.reportWrongMatch,
      'not_a_plant_or_pet': l10n.reportNotPlantOrPet,
      'other': l10n.reportOther,
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.reportTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v ?? _reason),
              child: Column(
                children: [
                  for (final e in reasons.entries)
                    RadioListTile<String>(value: e.key, title: Text(e.value), contentPadding: EdgeInsets.zero),
                ],
              ),
            ),
            if (_reason == 'wrong_match')
              TextField(
                controller: _name,
                maxLength: 120,
                decoration: InputDecoration(labelText: l10n.reportSuggestedName),
              ),
            TextField(
              controller: _note,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.reportNote),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _sending ? null : _send, child: Text(l10n.reportSend)),
          ],
        ),
      ),
    );
  }
}
