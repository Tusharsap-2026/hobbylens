import 'package:flutter/material.dart';

import '../models/identify_result.dart';
import '../services/api_service.dart';
import '../ui/format.dart';

/// Plain-language message for an error the user can act on.
String errorMessage(BuildContext context, Object error) {
  final l10n = context.l10n;
  if (error is ApiException) {
    return switch (error.kind) {
      ApiErrorKind.network => l10n.errorNoInternet,
      ApiErrorKind.timeout => l10n.errorTimeout,
      ApiErrorKind.quota => error.limit == null ? l10n.errorServer : l10n.errorQuota(error.limit!),
      ApiErrorKind.photo => l10n.errorPhoto,
      ApiErrorKind.unauthorised || ApiErrorKind.server => l10n.errorServer,
    };
  }
  return l10n.errorServer;
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final retryable = !(error is ApiException && (error as ApiException).kind == ApiErrorKind.quota);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(errorMessage(context, error), textAlign: TextAlign.center),
            if (onRetry != null && retryable) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: Text(context.l10n.tryAgain)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small grey note, used for disclaimers and the labels on unreviewed care text.
class NoteText extends StatelessWidget {
  const NoteText(this.text, {super.key, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: style?.color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip({super.key, required this.match, required this.showPercent});

  final IdMatch match;

  /// Plant engines give a real probability; for animals the vision model only gives a band,
  /// so a percentage would suggest more precision than there is.
  final bool showPercent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (match.band) {
      Band.high => (scheme.primaryContainer, scheme.onPrimaryContainer),
      Band.medium => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      Band.low => (scheme.errorContainer, scheme.onErrorContainer),
    };
    final label = showPercent && match.confidence != null
        ? context.l10n.confidencePercent(formatPercent(context, match.confidence!))
        : bandLabel(context.l10n, match.band);
    return Chip(
      label: Text(label, style: TextStyle(color: fg)),
      backgroundColor: bg,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class CareTipsCard extends StatelessWidget {
  const CareTipsCard({super.key, required this.care});

  final CareCard care;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.careBasics, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final tip in care.tips) ...[
              Text(topicLabel(l10n, tip.topic), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 2),
              Text(tip.text(context.lang)),
              const SizedBox(height: 10),
            ],
            if (care.isFallback) NoteText(l10n.careGeneral),
            if (care.status == CareStatus.draft) NoteText(l10n.careDraft, icon: Icons.edit_note),
            if (care.status == CareStatus.aiGenerated) NoteText(l10n.careAiGenerated, icon: Icons.auto_awesome_outlined),
          ],
        ),
      ),
    );
  }
}
