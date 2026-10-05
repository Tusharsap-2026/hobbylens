import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/kind.dart';
import '../models/shop.dart';
import '../services/location_service.dart';
import '../services/services.dart';
import '../ui/format.dart';
import '../widgets/common.dart';
import '../widgets/shop_actions.dart';
import 'shop_detail_screen.dart';

/// Nearby nurseries, pet shops or vets within a chosen radius. Partner shops with confirmed
/// stock come first, then shops that sell the right category, then the rest by distance.
class WhereToBuyScreen extends StatefulWidget {
  const WhereToBuyScreen({super.key, required this.title, this.kind, this.taxonId, this.itemName, this.types});

  final String title;
  final Kind? kind;
  final int? taxonId;
  final String? itemName;
  final List<ShopType>? types;

  @override
  State<WhereToBuyScreen> createState() => _WhereToBuyScreenState();
}

class _WhereToBuyScreenState extends State<WhereToBuyScreen> {
  int _radiusKm = 3;
  bool _explained = false;
  bool _loading = false;
  Object? _error;
  List<Shop>? _shops;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shops == null && !_loading && _error == null) {
      _explained = AppScope.of(context).settings.locationExplained;
      if (_explained) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
    }
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pos = await services.location.current();
      final shops = await services.api.nearbyShops(
        lat: pos.latitude,
        lng: pos.longitude,
        radiusKm: _radiusKm,
        kind: widget.kind,
        taxonId: widget.taxonId,
        types: widget.types,
      );
      if (mounted) setState(() => _shops = shops);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _allow() async {
    await AppScope.of(context).settings.setLocationExplained();
    if (!mounted) return;
    setState(() => _explained = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final km in AppConfig.radiiKm)
                  ChoiceChip(
                    label: Text(context.l10n.radiusKm(formatNumber(context, km))),
                    selected: _radiusKm == km,
                    onSelected: _loading || !_explained
                        ? null
                        : (_) {
                            setState(() => _radiusKm = km);
                            unawaited(_load());
                          },
                  ),
              ],
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    if (!_explained) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.location_on_outlined),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l10n.locationWhyTitle, style: Theme.of(context).textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: 8),
                  Text(l10n.locationWhyBody),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _allow, child: Text(l10n.allowLocation)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error is LocationException) return _locationProblem(context, error.problem);
    if (error != null) return ErrorView(error: error, onRetry: _load);
    final shops = _shops ?? const <Shop>[];
    if (shops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.noShopsFound(formatNumber(context, _radiusKm)), textAlign: TextAlign.center),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: shops.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => ShopCard(shop: shops[i], itemName: widget.itemName, showLikely: widget.kind == Kind.plant),
      ),
    );
  }

  Widget _locationProblem(BuildContext context, LocationProblem problem) {
    final l10n = context.l10n;
    final services = AppScope.of(context);
    final text = switch (problem) {
      LocationProblem.serviceOff => l10n.locationServiceOff,
      LocationProblem.unavailable => l10n.locationUnavailable,
      LocationProblem.denied || LocationProblem.deniedForever => l10n.locationDenied,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (problem == LocationProblem.deniedForever)
              OutlinedButton(onPressed: services.location.openSettings, child: Text(l10n.openSettings))
            else
              OutlinedButton(onPressed: _load, child: Text(l10n.tryAgain)),
          ],
        ),
      ),
    );
  }
}

class ShopCard extends StatelessWidget {
  const ShopCard({super.key, required this.shop, this.itemName, this.showLikely = false});

  final Shop shop;
  final String? itemName;

  /// For plants: say "likely available" when the shop sells the plant's category.
  final bool showLikely;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final open = shop.openNow;
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => ShopDetailScreen(shop: shop, itemName: itemName)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(shop.name(context.lang), style: theme.textTheme.titleMedium)),
                  if (shop.verified) ...[
                    const SizedBox(width: 8),
                    Tooltip(message: l10n.verifiedShop, child: Icon(Icons.verified_outlined, color: theme.colorScheme.primary)),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text('${shopTypeLabel(l10n, shop.type)} · ${formatDistance(context, shop.distanceM)}'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    open == null ? l10n.hoursUnknown : (open ? l10n.openNow : l10n.closedNow),
                    style: TextStyle(color: open == true ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                  ),
                  if (shop.rating != null)
                    Semantics(
                      label: l10n.ratingLabel(formatNumber(context, shop.rating!, decimals: 1), formatNumber(context, shop.ratingCount)),
                      excludeSemantics: true,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
                        Text(' ${formatNumber(context, shop.rating!, decimals: 1)} (${formatNumber(context, shop.ratingCount)})'),
                      ]),
                    ),
                ],
              ),
              if (shop.inStock) ...[
                const SizedBox(height: 8),
                Chip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(shop.stockPriceBdt == null
                      ? l10n.inStockBadge
                      : '${l10n.inStockBadge} · ৳${formatTaka(context, shop.stockPriceBdt!)}'),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  side: BorderSide.none,
                ),
              ] else if (showLikely && shop.categoryMatch) ...[
                const SizedBox(height: 8),
                Text(l10n.likelyAvailable, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              ShopActions(shop: shop, itemName: itemName),
            ],
          ),
        ),
      ),
    );
  }
}
