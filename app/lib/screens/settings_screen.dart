import 'package:flutter/material.dart';

import '../services/services.dart';
import '../ui/format.dart';
import '../widgets/common.dart';
import 'sign_in_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return StreamBuilder(
      stream: services.auth.changes,
      builder: (context, _) {
        final registered = services.auth.isRegistered;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.navSettings, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            Text(l10n.settingsLanguage, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'bn', label: Text(l10n.languageBangla)),
                ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
              ],
              selected: {services.settings.languageCode},
              onSelectionChanged: (s) async {
                await services.settings.setLanguage(s.first);
                // Reminder notifications carry text, so re-create them in the new language.
                await services.collection.rescheduleAll();
              },
            ),
            const SizedBox(height: 24),
            Text(l10n.settingsAccount, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (registered)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(l10n.signedInAs(services.auth.phone ?? '')),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(l10n.guestAccount),
                trailing: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute<bool>(builder: (_) => const SignInScreen())),
                  child: Text(l10n.verifyPhone),
                ),
              ),
            if (registered)
              TextButton(
                onPressed: () => _signOut(context),
                child: Text(l10n.signOut),
              ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              onPressed: () => _deleteAccount(context),
              child: Text(l10n.deleteAccount),
            ),
            const SizedBox(height: 24),
            Text(l10n.settingsPrivacy, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l10n.privacySummary),
            const SizedBox(height: 24),
            Text(l10n.settingsAbout, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l10n.disclaimerBody),
          ],
        );
      },
    );
  }

  /// Pushes pending changes first; if some cannot be sent, asks before discarding them.
  Future<void> _signOut(BuildContext context) async {
    final services = AppScope.of(context);
    final l10n = context.l10n;
    await services.collection.sync();
    if (await services.collection.hasUnsyncedChanges()) {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.signOutUnsynced),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.signOutAnyway)),
          ],
        ),
      );
      if (ok != true) return;
    }
    await services.collection.clearLocal();
    await services.auth.signOut();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final services = AppScope.of(context);
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAccount),
        content: Text(l10n.deleteAccountConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await services.api.deleteAccount();
      await services.collection.clearLocal();
      await services.auth.signOut();
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
    } catch (e) {
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(errorMessage(context, e))));
    }
  }
}
