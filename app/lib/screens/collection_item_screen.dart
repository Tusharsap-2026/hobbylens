import 'dart:async';

import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../models/identify_result.dart';
import '../models/kind.dart';
import '../services/collection_repository.dart';
import '../services/services.dart';
import '../ui/format.dart';
import '../widgets/common.dart';
import 'collection_screen.dart';

class CollectionItemScreen extends StatefulWidget {
  const CollectionItemScreen({super.key, required this.itemId});

  final String itemId;

  @override
  State<CollectionItemScreen> createState() => _CollectionItemScreenState();
}

class _CollectionItemScreenState extends State<CollectionItemScreen> {
  CollectionItem? _item;
  List<Reminder> _reminders = const [];
  CareCard? _care;
  bool _loaded = false;

  CollectionRepository get _repo => AppScope.of(context).collection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final repo = _repo;
    final api = AppScope.of(context).api;
    final item = await repo.item(widget.itemId);
    final reminders = item == null ? const <Reminder>[] : await repo.reminders(item.id);
    if (!mounted) return;
    setState(() {
      _item = item;
      _reminders = reminders;
      _care = item?.care;
    });
    // Items synced from another phone carry no cached care card: fetch the curated one.
    if (item != null && item.care == null && item.taxonId != null) {
      try {
        final care = await api.careForTaxon(item.taxonId!);
        if (mounted && care != null) setState(() => _care = care);
      } catch (_) {
        // Offline: the screen still works without care tips.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final item = _item;
    if (item == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(item.displayName(context.lang)),
        actions: [
          IconButton(tooltip: l10n.nickname, icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(item)),
          IconButton(tooltip: l10n.delete, icon: const Icon(Icons.delete_outline), onPressed: () => _delete(item)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: CollectionThumb(item: item, size: 160)),
          const SizedBox(height: 16),
          Text(item.speciesName(context.lang), style: theme.textTheme.titleLarge),
          if (item.scientificName != null)
            Text(item.scientificName!, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text(l10n.reminders, style: theme.textTheme.titleMedium)),
              TextButton.icon(
                onPressed: () => _addReminder(item),
                icon: const Icon(Icons.alarm_add_outlined),
                label: Text(l10n.addReminder),
              ),
            ],
          ),
          if (_reminders.isEmpty) Text(l10n.noReminders),
          for (final r in _reminders)
            Card(
              child: ListTile(
                leading: const Icon(Icons.alarm_outlined),
                title: Text(r.label == null ? reminderTypeLabel(l10n, r.type) : '${reminderTypeLabel(l10n, r.type)}: ${r.label}'),
                subtitle: Text([
                  l10n.reminderNext('${formatDate(context, r.nextDue)}, ${formatTime(context, r.hour, r.minute)}'),
                  r.everyDays == null ? l10n.reminderOnce : l10n.everyNDays(r.everyDays!),
                ].join('\n')),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    final repo = _repo;
                    if (v == 'done') await repo.markDone(r);
                    if (v == 'delete') await repo.deleteReminder(r);
                    if (mounted) await _reload();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'done', child: Text(l10n.markDone)),
                    PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          if (_care != null && _care!.tips.isNotEmpty) CareTipsCard(care: _care!),
        ],
      ),
    );
  }

  Future<void> _rename(CollectionItem item) async {
    final repo = _repo;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: item.nickname ?? ''),
    );
    if (name == null || !mounted) return;
    await repo.rename(item, name);
    if (mounted) await _reload();
  }

  Future<void> _delete(CollectionItem item) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.deleteItemConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = _repo;
    await repo.delete(item);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addReminder(CollectionItem item) async {
    final services = AppScope.of(context);
    final repo = services.collection;
    final l10n = context.l10n;
    final draft = await showModalBottomSheet<_ReminderDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _ReminderForm(kind: item.kind),
      ),
    );
    if (draft == null || !mounted) return;
    final granted = await services.notifications.requestPermission();
    await repo.addReminder(
      item: item,
      type: draft.type,
      date: draft.date,
      hour: draft.time.hour,
      minute: draft.time.minute,
      everyDays: draft.everyDays,
      label: draft.label,
    );
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.notificationsOff)));
    }
    await _reload();
  }
}

/// Owns its text controller, so it is disposed only after the dialog has fully closed.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.nickname),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(hintText: l10n.nicknameHint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(l10n.save)),
      ],
    );
  }
}

class _ReminderDraft {
  const _ReminderDraft(this.type, this.date, this.time, this.everyDays, this.label);
  final ReminderType type;
  final DateTime date;
  final TimeOfDay time;
  final int? everyDays;
  final String? label;
}

class _ReminderForm extends StatefulWidget {
  const _ReminderForm({required this.kind});
  final Kind kind;

  @override
  State<_ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<_ReminderForm> {
  late ReminderType _type = ReminderType.forKind(widget.kind).first;
  // Default: 9:00 today, or tomorrow if 9:00 has already passed.
  DateTime _date = DateTime.now().hour >= 9 ? DateTime.now().add(const Duration(days: 1)) : DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  int? _everyDays = 7;
  bool _pastError = false;
  final _label = TextEditingController();

  static const _repeatOptions = <int?>[null, 1, 2, 3, 7, 14, 30, 90, 365];

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.addReminder, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final t in ReminderType.forKind(widget.kind))
                  ChoiceChip(
                    label: Text(reminderTypeLabel(l10n, t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _label, maxLength: 60, decoration: InputDecoration(labelText: l10n.reminderLabel)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.reminderDate),
              trailing: Text(formatDate(context, _date)),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(now.year, now.month, now.day),
                  lastDate: DateTime(now.year + 2),
                );
                if (d != null && mounted) setState(() => _date = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.reminderTime),
              trailing: Text(formatTime(context, _time.hour, _time.minute)),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null && mounted) setState(() => _time = t);
              },
            ),
            const SizedBox(height: 8),
            Text(l10n.reminderRepeat, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final d in _repeatOptions)
                  ChoiceChip(
                    label: Text(d == null ? l10n.reminderOnce : l10n.everyNDays(d)),
                    selected: _everyDays == d,
                    onSelected: (_) => setState(() => _everyDays = d),
                  ),
              ],
            ),
            if (_pastError) ...[
              const SizedBox(height: 8),
              Text(l10n.reminderInPast, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final first = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
                // A one-off reminder must be in the future; a repeating one rolls forward itself.
                if (_everyDays == null && !first.isAfter(DateTime.now())) {
                  setState(() => _pastError = true);
                  return;
                }
                Navigator.pop(context, _ReminderDraft(_type, _date, _time, _everyDays, _label.text));
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
