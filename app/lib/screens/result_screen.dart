import 'package:flutter/material.dart';

import '../models/identify_result.dart';
import '../models/kind.dart';
import '../services/photo_service.dart';
import '../services/services.dart';
import '../ui/format.dart';
import '../widgets/common.dart';
import 'accessories_screen.dart';
import 'report_sheet.dart';
import 'sign_in_screen.dart';
import 'vet_help_screen.dart';
import 'where_to_buy_screen.dart';

/// The outcome of one identification. Only a confident result is shown as an answer; anything
/// below the threshold is presented as "not sure" with the guesses clearly marked.
class ResultView extends StatefulWidget {
  const ResultView({super.key, required this.result, required this.photo, required this.requested, required this.onRetake});

  final IdentifyResult result;
  final PickedPhoto photo;
  final RequestCategory requested;
  final VoidCallback onRetake;

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  int _selected = 0;
  final Map<int, CareCard> _loadedCare = {};
  bool _loadingCare = false;
  bool _saving = false;

  Kind get _kind => widget.result.detectedKind ?? widget.requested.kind ?? Kind.plant;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    switch (r.status) {
      case IdStatus.confident:
        // Defensive: a confident answer always has a match, but never index an empty list.
        return r.matches.isEmpty ? _notRecognised(context) : _confident(context);
      case IdStatus.lowConfidence:
        return _notSure(context);
      case IdStatus.notRecognised:
      case IdStatus.failed:
        return _notRecognised(context);
    }
  }

  Widget _photo() => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(widget.photo.bytes, height: 220, width: double.infinity, fit: BoxFit.cover),
      );

  Widget _confident(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final matches = widget.result.matches;
    final match = matches[_selected];
    final care = match.care ?? _loadedCare[_selected];
    final safety = _kind == Kind.plant ? petSafetyLabel(l10n, match.petSafety) : null;
    final requestedKind = widget.requested.kind;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _photo(),
        const SizedBox(height: 16),
        if (requestedKind != null && widget.result.detectedKind != null && requestedKind != widget.result.detectedKind) ...[
          NoteText(l10n.detectedDifferent(kindLabel(l10n, widget.result.detectedKind!))),
          const SizedBox(height: 8),
        ],
        Text(match.displayName(context.lang), style: theme.textTheme.headlineSmall),
        if (context.lang == 'bn' && match.nameBn != null) Text(match.nameEn, style: theme.textTheme.titleMedium),
        Text(match.scientificName, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [ConfidenceChip(match: match, showPercent: _kind == Kind.plant)]),
        if (safety != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                match.petSafety?.startsWith('toxic') ?? false ? Icons.warning_amber_rounded : Icons.pets,
                color: match.petSafety?.startsWith('toxic') ?? false ? theme.colorScheme.error : theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(safety)),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (care != null && care.tips.isNotEmpty)
          CareTipsCard(care: care)
        else
          Card(
            child: ListTile(
              title: Text(l10n.careNone),
              trailing: _loadingCare
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: () => _loadCare(match), child: Text(l10n.loadCareTips)),
            ),
          ),
        if (_kind.isAnimal) ...[
          const SizedBox(height: 12),
          _vetCard(context, emphasise: widget.result.vetAdvice),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => WhereToBuyScreen(
                title: _kind == Kind.plant ? l10n.whereToBuy : l10n.whereToBuySupplies,
                kind: _kind,
                taxonId: _kind == Kind.plant ? match.taxonId : null,
                itemName: match.displayName(context.lang),
              ),
            ),
          ),
          icon: const Icon(Icons.storefront_outlined),
          label: Text(_kind == Kind.plant ? l10n.whereToBuy : l10n.whereToBuySupplies),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => AccessoriesScreen(kind: _kind, taxonId: match.taxonId)),
          ),
          icon: const Icon(Icons.checklist),
          label: Text(l10n.whatYouNeed),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : () => _save(match),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(l10n.saveToCollection),
        ),
        if (matches.length > 1) ...[
          const SizedBox(height: 24),
          Text(l10n.otherPossibilities, style: theme.textTheme.titleMedium),
          for (var i = 0; i < matches.length; i++)
            if (i != _selected)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(matches[i].displayName(context.lang)),
                subtitle: Text(matches[i].scientificName),
                trailing: ConfidenceChip(match: matches[i], showPercent: _kind == Kind.plant),
                onTap: () => setState(() => _selected = i),
              ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showReportSheet(context, widget.result.identificationId),
            icon: const Icon(Icons.flag_outlined),
            label: Text(l10n.notRight),
          ),
        ),
        NoteText(l10n.resultDisclaimer),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _notSure(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _photo(),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.help_outline, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.lowConfidenceTitle, style: theme.textTheme.titleLarge)),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.lowConfidenceBody),
        const SizedBox(height: 8),
        NoteText(l10n.retakeTips, icon: Icons.lightbulb_outline),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: widget.onRetake, icon: const Icon(Icons.photo_camera_outlined), label: Text(l10n.retakePhoto)),
        if (widget.result.matches.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(l10n.possibleMatches, style: theme.textTheme.titleSmall),
          for (final m in widget.result.matches)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(m.displayName(context.lang)),
              subtitle: Text(m.scientificName),
              trailing: ConfidenceChip(match: m, showPercent: _kind == Kind.plant),
            ),
        ],
        if (_kind.isAnimal) ...[
          const SizedBox(height: 16),
          _vetCard(context, emphasise: widget.result.vetAdvice),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showReportSheet(context, widget.result.identificationId),
            icon: const Icon(Icons.flag_outlined),
            label: Text(l10n.notRight),
          ),
        ),
      ],
    );
  }

  Widget _notRecognised(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _photo(),
        const SizedBox(height: 16),
        Text(l10n.notRecognisedTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(l10n.notRecognisedBody),
        const SizedBox(height: 8),
        NoteText(l10n.retakeTips, icon: Icons.lightbulb_outline),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: widget.onRetake, icon: const Icon(Icons.photo_camera_outlined), label: Text(l10n.retakePhoto)),
      ],
    );
  }

  Widget _vetCard(BuildContext context, {required bool emphasise}) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: emphasise ? scheme.errorContainer : null,
      child: ListTile(
        leading: Icon(Icons.medical_services_outlined, color: emphasise ? scheme.onErrorContainer : scheme.primary),
        title: Text(l10n.vetAdviceTitle),
        subtitle: Text(l10n.vetAdviceBody),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const VetHelpScreen())),
      ),
    );
  }

  Future<void> _loadCare(IdMatch match) async {
    final services = AppScope.of(context);
    final index = _selected; // the user may pick another match while this loads
    setState(() => _loadingCare = true);
    try {
      final care = await services.api.careTips(kind: _kind, scientificName: match.scientificName, commonName: match.nameEn);
      if (mounted) setState(() => _loadedCare[index] = care);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(context, e))));
    } finally {
      if (mounted) setState(() => _loadingCare = false);
    }
  }

  Future<void> _save(IdMatch match) async {
    final services = AppScope.of(context);
    final l10n = context.l10n;
    final index = _selected;
    if (!services.auth.isRegistered) {
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SignInScreen()));
      if (ok != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final care = match.care ?? _loadedCare[index];
      final toSave = care == match.care
          ? match
          : IdMatch(
              rank: match.rank,
              taxonId: match.taxonId,
              taxonKey: match.taxonKey,
              scientificName: match.scientificName,
              nameEn: match.nameEn,
              nameBn: match.nameBn,
              confidence: match.confidence,
              band: match.band,
              petSafety: match.petSafety,
              care: care,
            );
      await services.collection.saveFromResult(
        match: toSave,
        kind: _kind,
        identificationId: widget.result.identificationId,
        photoPath: widget.photo.path,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.savedToCollection)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.errorServer)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
