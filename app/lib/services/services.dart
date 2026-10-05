import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'collection_repository.dart';
import 'local_db.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'photo_service.dart';
import 'settings.dart';
import 'sync_service.dart';

/// Everything the screens use, created once at start-up.
class Services {
  Services._({
    required this.settings,
    required this.auth,
    required this.api,
    required this.db,
    required this.collection,
    required this.photos,
    required this.location,
    required this.notifications,
  });

  final Settings settings;
  final AuthService auth;
  final ApiService api;
  final LocalDb db;
  final CollectionRepository collection;
  final PhotoService photos;
  final LocationService location;
  final NotificationService notifications;

  static Future<Services> create() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = Settings(prefs);
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabasePublishableKey);
    final client = Supabase.instance.client;
    final auth = AuthService(client.auth);
    final db = await LocalDb.open();
    final notifications = NotificationService();
    try {
      await notifications.init();
    } catch (_) {
      // Reminders still save; they just cannot notify on this device.
    }
    final sync = SyncService(client, db, auth, notifications);
    final collection = CollectionRepository(db, sync, notifications, settings);
    final services = Services._(
      settings: settings,
      auth: auth,
      api: ApiService(client, auth),
      db: db,
      collection: collection,
      photos: PhotoService(),
      location: LocationService(),
      notifications: notifications,
    );
    // Start-up work that must not delay the first screen.
    unawaited(collection.rescheduleAll().then((_) => collection.sync()).catchError((Object _) {}));
    return services;
  }
}

/// Makes [Services] available to every screen.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final Services services;

  static Services of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => !identical(services, oldWidget.services);
}
