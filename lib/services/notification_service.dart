import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Envuelve flutter_local_notifications para mostrar notificaciones
/// nativas (barra de notificaciones del teléfono) cuando se detecta un
/// reporte nuevo dentro del radio del usuario.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  Future<void>? _initialization;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'nearby_reports',
    'Reportes cercanos',
    description: 'Avisa cuando se crea un reporte dentro de tu radio.',
    importance: Importance.high,
  );
  static const AndroidNotificationChannel _englishChannel =
      AndroidNotificationChannel(
        'nearby_reports_en',
        'Nearby reports',
        description: 'Alerts when a report is created near you.',
        importance: Importance.high,
      );

  /// Inicializa el plugin sin bloquear el arranque ni solicitar permisos.
  Future<void> init() async {
    if (_initialized) return;
    final initialization = _initialization ??= _initialize();
    try {
      await initialization;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.createNotificationChannel(_englishChannel);

    _initialized = true;
  }

  /// Requests OS permission only after the user enables community alerts.
  Future<bool> requestPermissions() async {
    await init();
    final androidGranted = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final iosGranted = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    return androidGranted ?? iosGranted ?? true;
  }

  /// Shows a nearby community report notification if OS permission exists.
  Future<void> showNearbyReportNotification({
    required String title,
    required String body,
    bool isEnglish = false,
  }) async {
    await init();
    final channel = isEnglish ? _englishChannel : _channel;
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}
