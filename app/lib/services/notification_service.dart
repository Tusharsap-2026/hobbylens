import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/collection.dart';

/// Local reminder notifications. Scheduled on the phone, so they fire with no network.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'care_reminders';

  Future<void> init() async {
    tzdata.initializeTimeZones();
    // Reminders are entered in the phone's own time. They are scheduled as absolute instants
    // (converted through UTC), so the device time zone is respected without a time-zone plugin.
    tz.setLocalLocation(tz.UTC);
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Asks for permission (Android 13+, iOS). Returns false if the user refused.
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    return true;
  }

  /// Schedules the next occurrence of [r]. Repeating reminders are re-scheduled each time the
  /// app opens or the user marks one done, so the interval can be any number of days.
  Future<void> schedule(Reminder r, {required String title, required String body, required String channelName}) async {
    if (!_ready) return;
    await cancel(r);
    if (!r.enabled || r.deletedAt != null) return;
    final when = tz.TZDateTime.from(r.nextFireLocal, tz.UTC);
    if (!when.isAfter(tz.TZDateTime.now(tz.UTC))) return;
    await _plugin.zonedSchedule(
      id: r.notificationId,
      scheduledDate: when,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(_channelId, channelName, importance: Importance.defaultImportance),
        iOS: const DarwinNotificationDetails(),
      ),
      // Inexact alarms need no special permission; a reminder a few minutes late is fine.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancel(Reminder r) async {
    if (!_ready) return;
    await _plugin.cancel(id: r.notificationId);
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }
}
