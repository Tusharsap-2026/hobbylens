import 'package:flutter/material.dart';

import '../models/shop.dart';
import '../ui/format.dart';
import 'where_to_buy_screen.dart';

/// Shown for any health question about a pet: the app never diagnoses.
class VetHelpScreen extends StatelessWidget {
  const VetHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.vetHelpTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.medical_services_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(l10n.vetHelpTitle, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(l10n.vetHelpBody, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => WhereToBuyScreen(title: l10n.vetClinicsNearby, types: const [ShopType.vetClinic]),
              ),
            ),
            icon: const Icon(Icons.local_hospital_outlined),
            label: Text(l10n.findVet),
          ),
        ],
      ),
    );
  }
}
