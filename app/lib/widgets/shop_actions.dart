import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/shop.dart';
import '../services/services.dart';
import '../ui/format.dart';

/// Links that hand the user over to the phone app, WhatsApp or Maps.
Uri callUri(String phone) => Uri(scheme: 'tel', path: phone);

Uri whatsappUri(String e164, String message) =>
    Uri.https('wa.me', '/${e164.replaceAll(RegExp(r'[^\d]'), '')}', {'text': message});

Uri directionsUri(double lat, double lng) =>
    Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': '$lat,$lng'});

/// Call, WhatsApp and Directions buttons. Each tap is logged (shop id and action only) so the
/// shop can be shown how many people contacted it.
class ShopActions extends StatelessWidget {
  const ShopActions({super.key, required this.shop, this.itemName});

  final Shop shop;
  final String? itemName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (shop.phone != null)
          FilledButton.tonalIcon(
            onPressed: () => _open(context, callUri(shop.phone!), 'call'),
            icon: const Icon(Icons.call_outlined),
            label: Text(l10n.callShop),
          ),
        if (shop.whatsapp != null)
          FilledButton.tonalIcon(
            onPressed: () => _open(
              context,
              whatsappUri(shop.whatsapp!, itemName == null ? l10n.whatsappHello : l10n.whatsappAskItem(itemName!)),
              'whatsapp',
            ),
            icon: const Icon(Icons.chat_outlined),
            label: Text(l10n.whatsappShop),
          ),
        OutlinedButton.icon(
          onPressed: () => _open(context, directionsUri(shop.lat, shop.lng), 'directions'),
          icon: const Icon(Icons.directions_outlined),
          label: Text(l10n.directions),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, Uri uri, String action) async {
    AppScope.of(context).api.logShopContact(shop.id, action);
    final messenger = ScaffoldMessenger.of(context);
    final failText = context.l10n.couldNotOpen;
    bool ok;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(failText)));
  }
}
