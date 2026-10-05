import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/auth_service.dart';
import '../services/phone.dart';
import '../services/services.dart';
import '../ui/format.dart';

/// Phone OTP. Pops with true once the phone is verified.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _e164;
  PhoneFlow? _flow;
  String? _error;
  String? _info;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final l10n = context.l10n;
    final e164 = normaliseBdMobile(_phone.text);
    if (e164 == null) {
      setState(() => _error = l10n.phoneInvalid);
      return;
    }
    final auth = AppScope.of(context).auth;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final flow = await auth.sendCode(e164);
      if (!mounted) return;
      setState(() {
        _e164 = e164;
        _flow = flow;
        _info = flow == PhoneFlow.signInExisting ? l10n.phoneExistsSwitch : null;
      });
      _startCountdown();
    } on AuthException {
      if (mounted) setState(() => _error = l10n.errorServer);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.errorNoInternet);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final l10n = context.l10n;
    final services = AppScope.of(context);
    final code = _code.text.trim();
    if (code.length < 4 || _e164 == null || _flow == null) {
      setState(() => _error = l10n.codeInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final wasGuest = _flow == PhoneFlow.linkToGuest;
      await services.auth.verifyCode(_e164!, code, _flow!);
      // Signing in to an existing account replaces the guest: pull that account's collection.
      if (!wasGuest) await services.collection.clearLocal();
      unawaited(services.collection.sync());
      if (mounted) Navigator.pop(context, true);
    } on AuthException {
      if (mounted) setState(() => _error = l10n.codeInvalid);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.errorNoInternet);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final codeSent = _e164 != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.verifyPhone)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(l10n.signInTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.signInBody),
          const SizedBox(height: 24),
          TextField(
            controller: _phone,
            enabled: !codeSent && !_busy,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: InputDecoration(labelText: l10n.phoneLabel, hintText: l10n.phoneHint, prefixText: '+88 '),
          ),
          if (codeSent) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 8,
              decoration: InputDecoration(labelText: l10n.codeLabel),
            ),
          ],
          if (_info != null) ...[
            const SizedBox(height: 8),
            Text(_info!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          if (!codeSent)
            FilledButton(onPressed: _busy ? null : _sendCode, child: Text(l10n.sendCode))
          else ...[
            FilledButton(onPressed: _busy ? null : _verify, child: Text(l10n.verify)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy || _resendIn > 0 ? null : _sendCode,
              child: Text(_resendIn > 0 ? l10n.resendIn(_resendIn) : l10n.resendCode),
            ),
          ],
        ],
      ),
    );
  }
}
