import 'package:flutter/material.dart';

import '../models/accessory.dart';
import '../models/kind.dart';
import '../services/services.dart';
import '../ui/format.dart';
import '../widgets/common.dart';

/// "What you'll need": essentials first, then nice-to-haves, each with an indicative BDT range.
class AccessoriesScreen extends StatefulWidget {
  const AccessoriesScreen({super.key, required this.kind, this.taxonId});

  final Kind kind;
  final int? taxonId;

  @override
  State<AccessoriesScreen> createState() => _AccessoriesScreenState();
}

class _AccessoriesScreenState extends State<AccessoriesScreen> {
  late Future<List<Accessory>> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _fetch();
  }

  Future<List<Accessory>> _fetch() =>
      AppScope.of(context).api.accessories(taxonId: widget.taxonId, kind: widget.kind);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.whatYouNeed)),
      body: FutureBuilder<List<Accessory>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return ErrorView(error: snap.error!, onRetry: () => setState(() {
                _future = _fetch();
              }));
          }
          final items = snap.data ?? const <Accessory>[];
          if (items.isEmpty) return Center(child: Text(l10n.accessoriesEmpty));
          final essential = items.where((a) => a.essential).toList();
          final optional = items.where((a) => !a.essential).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (essential.isNotEmpty) _section(context, l10n.essential, essential),
              if (optional.isNotEmpty) _section(context, l10n.niceToHave, optional),
              NoteText(l10n.resultDisclaimer),
            ],
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Accessory> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final a in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(a.name(context.lang)),
              subtitle: Text('${a.category(context.lang)}\n${priceText(context, a)}'),
              isThreeLine: true,
            ),
        ],
      ),
    );
  }
}

/// Indicative price range in taka, or "ask the shop" while prices are still being surveyed.
String priceText(BuildContext context, Accessory a) {
  final l10n = context.l10n;
  final min = a.priceMinBdt;
  final max = a.priceMaxBdt;
  if (min != null && max != null && max > min) return l10n.priceRange(formatTaka(context, min), formatTaka(context, max));
  if (min != null) return l10n.priceFrom(formatTaka(context, min));
  return l10n.priceAskShop;
}
