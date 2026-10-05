/// Build-time settings, passed with --dart-define (see docs/SETUP.md). No secrets live in the
/// app: the publishable key only identifies the project, and row-level security protects data.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Radius options offered on the shop search, in kilometres.
  static const radiiKm = [1, 3, 5, 10];

  /// Longest edge of the photo sent for identification, and its JPEG quality.
  static const photoMaxEdge = 1024.0;
  static const photoQuality = 80;

  /// Largest photo the gateway accepts.
  static const photoMaxBytes = 1500000;

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
