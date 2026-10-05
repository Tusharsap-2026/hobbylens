import 'package:flutter/material.dart';

import '../models/kind.dart';
import '../services/local_db.dart';
import '../services/services.dart';
import '../ui/format.dart';
import 'capture_flow.dart';
import 'collection_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: const [IdentifyTab(), CollectionScreen(), SettingsScreen()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.center_focus_strong_outlined), label: l10n.navIdentify),
          NavigationDestination(icon: const Icon(Icons.collections_bookmark_outlined), label: l10n.navCollection),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), label: l10n.navSettings),
        ],
      ),
    );
  }
}

class IdentifyTab extends StatefulWidget {
  const IdentifyTab({super.key});

  @override
  State<IdentifyTab> createState() => _IdentifyTabState();
}

class _IdentifyTabState extends State<IdentifyTab> {
  late Future<List<RecentIdentification>> _recents;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recents = AppScope.of(context).db.recents();
  }

  Future<void> _start(RequestCategory c) async {
    await startIdentification(context, c);
    if (!mounted) return;
    setState(() {
      _recents = AppScope.of(context).db.recents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.appTitle, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        const SizedBox(height: 4),
        Text(l10n.homeTitle, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            _CategoryTile(icon: Icons.local_florist_outlined, label: l10n.categoryPlant, onTap: () => _start(RequestCategory.plant)),
            _CategoryTile(icon: Icons.pets_outlined, label: l10n.categoryCat, onTap: () => _start(RequestCategory.cat)),
            _CategoryTile(icon: Icons.pets, label: l10n.categoryDog, onTap: () => _start(RequestCategory.dog)),
            _CategoryTile(icon: Icons.flutter_dash, label: l10n.categoryBird, onTap: () => _start(RequestCategory.bird)),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _start(RequestCategory.auto),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(l10n.categoryAuto),
        ),
        const SizedBox(height: 24),
        FutureBuilder<List<RecentIdentification>>(
          future: _recents,
          builder: (context, snap) {
            final items = snap.data ?? const <RecentIdentification>[];
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.recentIdentifications, style: theme.textTheme.titleMedium),
                for (final r in items.take(8))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(r.confident ? Icons.check_circle_outline : Icons.help_outline),
                    title: Text(r.name(context.lang)),
                    subtitle: Text(
                      [if (r.kind != null) kindLabel(l10n, r.kind!), formatDate(context, r.createdAt.toLocal())].join(' · '),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: scheme.onSecondaryContainer),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSecondaryContainer)),
            ],
          ),
        ),
      ),
    );
  }
}
