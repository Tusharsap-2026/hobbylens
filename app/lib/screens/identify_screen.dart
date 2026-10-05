import 'dart:async';

import 'package:flutter/material.dart';

import '../models/identify_result.dart';
import '../models/kind.dart';
import '../services/local_db.dart';
import '../services/photo_service.dart';
import '../services/services.dart';
import '../ui/format.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

enum IdentifyOutcome { done, retake }

/// Sends the photo and shows the outcome: result, "not sure" or "not recognised".
class IdentifyScreen extends StatefulWidget {
  const IdentifyScreen({super.key, required this.photo, required this.category, required this.hint});

  final PickedPhoto photo;
  final RequestCategory category;
  final PhotoHint? hint;

  @override
  State<IdentifyScreen> createState() => _IdentifyScreenState();
}

class _IdentifyScreenState extends State<IdentifyScreen> {
  IdentifyResult? _result;
  Object? _error;
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    // No setState before the first frame: the initial state already shows the progress view.
    unawaited(_run(reset: false));
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  Future<void> _run({bool reset = true}) async {
    final services = AppScope.of(context);
    if (reset) {
      setState(() {
        _error = null;
        _result = null;
        _slow = false;
      });
    }
    _slowTimer?.cancel();
    // The target is a result within 6 seconds on 4G; beyond that, say the network may be slow.
    _slowTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _slow = true);
    });
    try {
      final result = await services.api.identify(
        jpeg: widget.photo.bytes,
        category: widget.category,
        hint: widget.hint?.toJson(),
      );
      final top = result.top;
      if (top != null) {
        await services.db.addRecent(RecentIdentification(
          id: result.identificationId,
          createdAt: DateTime.now(),
          kind: result.detectedKind,
          nameEn: top.nameEn,
          nameBn: top.nameBn,
          confident: result.status == IdStatus.confident,
        ));
      }
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _slowTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = _result;
    final Widget body;
    if (_error != null) {
      body = ErrorView(error: _error!, onRetry: _run);
    } else if (result == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(widget.photo.bytes, height: 200, fit: BoxFit.cover),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l10n.identifying, style: Theme.of(context).textTheme.titleMedium),
              if (_slow) ...[
                const SizedBox(height: 8),
                Text(l10n.slowNetwork, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      );
    } else {
      body = ResultView(
        result: result,
        photo: widget.photo,
        requested: widget.category,
        onRetake: () => Navigator.pop(context, IdentifyOutcome.retake),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(result == null ? l10n.identifying : l10n.resultTitle)),
      body: body,
    );
  }
}
