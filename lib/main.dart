import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:listen_around/auth/login.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:listen_around/spotify.dart';
import 'package:flutter/services.dart';
import 'package:listen_around/notification.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:listen_around/super_like_notification_page.dart';
import 'dart:convert';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Load and initialize FCM service
  final serviceAccountJson = await rootBundle.loadString('assets/listen-around-firebase-adminsdk-b1ffs-d04a168c30.json');
  await FCMService.initialize(serviceAccountJson);

  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');


  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
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
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
    'superlike_channel', // Channel ID
    'Super Like Notifications', // Channel name
    channelDescription: 'Notifications for super likes',
    importance: Importance.high,
    priority: Priority.high,
    enableVibration: true, // Enable vibration
  );

  const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

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

void _handleNotificationTap(String payload) {
  final Map<String, dynamic> data = jsonDecode(payload);

  if (data['type'] == 'superlike') {
    final userId = data['userId'];
    Navigator.of(MyApp.navigatorKey.currentContext!).push(
      MaterialPageRoute(
        builder: (context) => SuperLikeInteractionPage(userId: userId, superLikeSenderId: userId,),
      ),
    );
  }
}


class MyApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // Assign the global key

      title: 'Spotify Locator',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }
    )
      ),
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
