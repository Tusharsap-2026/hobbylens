import 'package:supabase_flutter/supabase_flutter.dart';

enum PhoneFlow {
  /// The guest account is being upgraded: same user id, earlier identifications kept.
  linkToGuest,

  /// The number already belongs to an account: sign in to that account instead.
  signInExisting,
}

/// Guest-first sign-in. Every install gets an anonymous session on first use; a phone number is
/// verified only when the user first saves to My Collection.
class AuthService {
  AuthService(this._auth);

  final GoTrueClient _auth;

  User? get user => _auth.currentUser;
  bool get hasSession => _auth.currentSession != null;
  bool get isRegistered => user != null && !user!.isAnonymous;
  String? get phone => user?.phone;
  Stream<AuthState> get changes => _auth.onAuthStateChange;

  /// Makes sure there is a session, creating a guest one if needed. Needs the network once.
  Future<void> ensureSession() {
    if (_auth.currentSession != null) return Future.value();
    // Concurrent first calls share one sign-in, so only one guest account is created.
    return _signingIn ??= _auth.signInAnonymously().then((_) {}).whenComplete(() => _signingIn = null);
  }

  Future<void>? _signingIn;

  /// Sends the SMS code. Returns which flow the code belongs to.
  Future<PhoneFlow> sendCode(String e164Phone) async {
    await ensureSession();
    if (user?.isAnonymous ?? true) {
      try {
        await _auth.updateUser(UserAttributes(phone: e164Phone));
        return PhoneFlow.linkToGuest;
      } on AuthException catch (e) {
        if (e.code != 'phone_exists') rethrow;
      }
    }
    await _auth.signInWithOtp(phone: e164Phone, shouldCreateUser: true);
    return PhoneFlow.signInExisting;
  }

  Future<void> verifyCode(String e164Phone, String code, PhoneFlow flow) async {
    await _auth.verifyOTP(
      phone: e164Phone,
      token: code.trim(),
      type: flow == PhoneFlow.linkToGuest ? OtpType.phoneChange : OtpType.sms,
    );
  }

  Future<void> signOut() => _auth.signOut();
}
