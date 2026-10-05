import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models/kind.dart';
import '../services/photo_service.dart';
import '../services/services.dart';
import '../ui/format.dart';
import 'identify_screen.dart';

/// Photo -> on-device check -> identification -> result, looping back when the user asks to
/// retake the photo.
Future<void> startIdentification(BuildContext context, RequestCategory category) async {
  final services = AppScope.of(context);
  while (true) {
    if (!context.mounted) return;
    final useCamera = await _chooseSource(context, category);
    if (!context.mounted) return;
    if (useCamera == null) return;

    final PickedPhoto? picked;
    try {
      picked = await services.photos.pick(camera: useCamera);
    } on PlatformException {
      if (context.mounted) _snack(context, context.l10n.errorPhoto);
      return;
    }
    if (!context.mounted) return;
    if (picked == null) return;
    // A non-nullable local, so the route builder closure below can use it without a null check.
    final PickedPhoto photo = picked;
    if (photo.bytes.length > AppConfig.photoMaxBytes) {
      _snack(context, context.l10n.errorPhoto);
      continue;
    }

    final hint = await services.photos.hint(photo.path);
    if (!context.mounted) return;
    if (hint != null && hint.looksUnrelated) {
      final proceed = await _confirmUnrelated(context);
      if (!context.mounted) return;
      if (proceed == null) return;
      if (!proceed) continue;
    }

    final outcome = await Navigator.of(context).push<IdentifyOutcome>(
      MaterialPageRoute(builder: (_) => IdentifyScreen(photo: photo, category: category, hint: hint)),
    );
    if (outcome != IdentifyOutcome.retake) return;
  }
}

Future<bool?> _chooseSource(BuildContext context, RequestCategory category) {
  final l10n = context.l10n;
  final tip = category == RequestCategory.plant ? l10n.photoTipPlant : (category.kind?.isAnimal ?? false) ? l10n.photoTipAnimal : null;
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(categoryLabel(l10n, category), style: Theme.of(context).textTheme.titleLarge),
            if (tip != null) ...[
              const SizedBox(height: 12),
              Text(l10n.photoTipsTitle, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(tip),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l10n.takePhoto),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.chooseFromGallery),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Returns true to identify anyway, false to take another photo, null if dismissed.
Future<bool?> _confirmUnrelated(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.notPlantOrPetTitle),
      content: Text(l10n.notPlantOrPetBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.retakePhoto)),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.identifyAnyway)),
      ],
    ),
  );
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
