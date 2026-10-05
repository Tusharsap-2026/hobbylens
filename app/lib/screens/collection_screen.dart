import 'dart:io';

import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../models/kind.dart';
import '../services/services.dart';
import '../ui/format.dart';
import 'collection_item_screen.dart';

/// My Collection. Read from the phone's own database, so it opens with no network.
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).collection;
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => FutureBuilder<List<CollectionItem>>(
        future: repo.items(),
        builder: (context, snap) {
          final items = snap.data;
          if (items == null) return const Center(child: CircularProgressIndicator());
          return RefreshIndicator(
            onRefresh: repo.sync,
            child: items.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 80),
                      Icon(Icons.collections_bookmark_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(l10n.collectionEmpty, textAlign: TextAlign.center),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      if (i == 0) return Text(l10n.navCollection, style: Theme.of(context).textTheme.headlineSmall);
                      final item = items[i - 1];
                      return Card(
                        child: ListTile(
                          leading: CollectionThumb(item: item),
                          title: Text(item.displayName(context.lang)),
                          subtitle: Text(
                            item.nickname == null ? kindLabel(l10n, item.kind) : item.speciesName(context.lang),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(builder: (_) => CollectionItemScreen(itemId: item.id)),
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

/// The saved photo from the phone, or a kind icon when there is none on this phone.
class CollectionThumb extends StatelessWidget {
  const CollectionThumb({super.key, required this.item, this.size = 48});

  final CollectionItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = item.localPhotoPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(path), width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round()),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Icon(item.kind == Kind.plant ? Icons.local_florist_outlined : Icons.pets, size: size * 0.6),
    );
  }
}
