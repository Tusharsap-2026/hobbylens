import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/shop.dart';
import '../ui/format.dart';
import '../widgets/shop_actions.dart';

class ShopDetailScreen extends StatelessWidget {
  const ShopDetailScreen({super.key, required this.shop, this.itemName});

  final Shop shop;
  final String? itemName;

  // The Bangladeshi week starts on Saturday. 3 October 2026 is a Saturday.
  static const _days = ['sat', 'sun', 'mon', 'tue', 'wed', 'thu', 'fri'];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final address = shop.address(context.lang);
    final hours = shop.hours;
    return Scaffold(
      appBar: AppBar(title: Text(shop.name(context.lang))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(shop.name(context.lang), style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('${shopTypeLabel(l10n, shop.type)} · ${formatDistance(context, shop.distanceM)}'),
          if (shop.verified) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.verified_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(l10n.verifiedShop),
            ]),
          ],
          const SizedBox(height: 16),
          ShopActions(shop: shop, itemName: itemName),
          if (address != null || shop.area != null) ...[
            const SizedBox(height: 24),
            Text(l10n.shopAddress, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text([address, shop.area].whereType<String>().where((s) => s.isNotEmpty).join(', ')),
          ],
          const SizedBox(height: 24),
          Text(l10n.openingHours, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (hours == null)
            Text(l10n.hoursUnknown)
          else
            for (var i = 0; i < _days.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(DateFormat.EEEE(context.lang).format(DateTime(2026, 10, 3 + i)))),
                    Text(_slotsText(context, hours[_days[i]])),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  String _slotsText(BuildContext context, List<HoursSlot>? slots) {
    if (slots == null || slots.isEmpty) return context.l10n.closedDay;
    return slots.map((s) => '${_time(context, s.open)} – ${_time(context, s.close)}').join(', ');
  }

  String _time(BuildContext context, String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return formatTime(context, h % 24, m);
  }
}
