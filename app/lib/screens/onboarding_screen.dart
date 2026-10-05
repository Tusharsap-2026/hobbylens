import 'package:flutter/material.dart';

import '../services/services.dart';
import '../ui/format.dart';

/// First run: language choice and the plain-language disclaimer.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(Icons.local_florist_outlined, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(l10n.welcomeTitle, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(l10n.welcomeBody, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            Text(l10n.chooseLanguage, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'bn', label: Text(l10n.languageBangla)),
                ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
              ],
              selected: {settings.languageCode},
              onSelectionChanged: (s) => settings.setLanguage(s.first),
            ),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.disclaimerTitle, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(l10n.disclaimerBody),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(onPressed: settings.setOnboarded, child: Text(l10n.getStarted)),
          ],
        ),
      ),
    );
  }
}
