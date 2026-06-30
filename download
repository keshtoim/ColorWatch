import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'camera_page.dart';
import 'overlay_view.dart';
import 'viewer_page.dart';

late List<CameraDescription> _cameras;
final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await _notifications.initialize(initSettings);
  await _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  try {
    _cameras = await availableCameras();
  } catch (_) {
    _cameras = [];
  }

  runApp(const ColorWatchApp());
}

// Entry point for the floating overlay window. The native side of
// flutter_overlay_window looks up this top-level function by name in the
// main Dart library, so it must live here (not in another file).
@pragma('vm:entry-point')
void overlayMain() {
  runApp(const OverlayApp());
}

class ColorWatchApp extends StatelessWidget {
  const ColorWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Color Watch',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const ModeSelectPage(),
    );
  }
}

class ModeSelectPage extends StatelessWidget {
  const ModeSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Color Watch')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Выберите режим',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Камера — следит за лампочкой и раздаёт видео.\n'
                'Зритель — смотрит видео и уведомления с другого телефона.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WithForegroundTask(
                        child: CameraPage(
                          cameras: _cameras,
                          notifications: _notifications,
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.videocam),
                  label: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Камера', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ViewerPage(notifications: _notifications),
                    ),
                  ),
                  icon: const Icon(Icons.phone_android),
                  label: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Зритель', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
