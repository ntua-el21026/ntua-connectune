import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:listen_around/auth/login.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:listen_around/spotify.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:listen_around/super_like_notification_page.dart';
import 'dart:convert';
import 'notification.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: DarwinInitializationSettings(),
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null) {
        _handleNotificationTap(response.payload!);
      }
    },
  );

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('Message opened app');
    if (message.data.isNotEmpty) {
      final payload = jsonEncode(message.data);
      _handleNotificationTap(payload);
    }
  });

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.notification != null) {
      _showLocalNotification(message);
    }
  });

  runApp(MyApp());
  WidgetsBinding.instance
      .addPostFrameCallback((_) => _openPendingNotification());
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user == null) {
      _pendingSender = null;
    } else {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _openPendingNotification());
    }
  });
  // Cold-start taps arrive separately from onMessageOpenedApp.
  try {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleNotificationTap(jsonEncode(initial.data));
    final localLaunch =
        await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    final payload = localLaunch?.notificationResponse?.payload;
    if (localLaunch?.didNotificationLaunchApp == true && payload != null)
      _handleNotificationTap(payload);
  } catch (_) {
    debugPrint('Initial notification unavailable');
  }
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'superlike_channel', // Channel ID
    'Super Like Notifications', // Channel name
    channelDescription: 'Notifications for super likes',
    importance: Importance.high,
    priority: Priority.high,
    enableVibration: true, // Enable vibration
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  final payload = jsonEncode({
    'type': message.data['type'],
    'userId': message.data['userId'], // Include the sender's userId
  });

  await flutterLocalNotificationsPlugin.show(
    message.hashCode, // Unique ID for each notification
    message.notification?.title ?? 'Notification',
    message.notification?.body ?? '',
    platformChannelSpecifics,
    payload: payload, // Include payload for interaction
  );
}

String? _pendingSender;
String? _topRouteName;

class _NotificationObserver extends NavigatorObserver {
  void _changed(Route<dynamic>? route) {
    _topRouteName = route?.settings.name;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _openPendingNotification());
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _changed(newRoute);
}

void _handleNotificationTap(String payload) {
  final sender = superLikeSender(payload);
  if (sender == null || FirebaseAuth.instance.currentUser == null) return;
  _pendingSender = sender;
  _openPendingNotification();
}

void _openPendingNotification() {
  final navigator = MyApp.navigatorKey.currentState;
  final sender = _pendingSender;
  if (navigator == null ||
      sender == null ||
      _topRouteName != '/home' ||
      FirebaseAuth.instance.currentUser == null) return;
  _pendingSender = null;
  navigator.push(MaterialPageRoute(
      builder: (_) =>
          SuperLikeInteractionPage(userId: sender, superLikeSenderId: sender)));
}

class MyApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // Assign the global key
      navigatorObservers: [_NotificationObserver()],

      title: 'Spotify Locator',
      theme: ThemeData(
          primarySwatch: Colors.blue,
          pageTransitionsTheme: const PageTransitionsTheme(builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          })),
      home: Builder(
        builder: (BuildContext context) {
          User? user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            return LoginPage();
          } else {
            return SpotifyAuthPage();
          }
        },
      ),
    );
  }
}
