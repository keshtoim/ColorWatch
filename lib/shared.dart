import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shared color types, classifier, and alerting used by both camera and viewer.

enum DetectedColor { green, red, other }

extension DetectedColorX on DetectedColor {
  String get label {
    switch (this) {
      case DetectedColor.green:
        return 'green';
      case DetectedColor.red:
        return 'red';
      case DetectedColor.other:
        return 'other';
    }
  }

  Color get swatch {
    switch (this) {
      case DetectedColor.green:
        return Colors.green;
      case DetectedColor.red:
        return Colors.red;
      case DetectedColor.other:
        return Colors.grey;
    }
  }

  static DetectedColor fromLabel(String s) {
    switch (s) {
      case 'green':
        return DetectedColor.green;
      case 'red':
        return DetectedColor.red;
      default:
        return DetectedColor.other;
    }
  }
}

/// Returns [hue(0-360), sat(0-1), val(0-1)].
List<double> rgbToHsv(int r, int g, int b) {
  final rf = r / 255, gf = g / 255, bf = b / 255;
  final maxC = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
  final minC = [rf, gf, bf].reduce((a, b) => a < b ? a : b);
  final delta = maxC - minC;

  double h = 0;
  if (delta != 0) {
    if (maxC == rf) {
      h = 60 * (((gf - bf) / delta) % 6);
    } else if (maxC == gf) {
      h = 60 * (((bf - rf) / delta) + 2);
    } else {
      h = 60 * (((rf - gf) / delta) + 4);
    }
  }
  if (h < 0) h += 360;
  final s = maxC == 0 ? 0.0 : delta / maxC;
  return [h, s, maxC];
}

DetectedColor classify(double h, double s, double v) {
  if (s < 0.35 || v < 0.20) return DetectedColor.other;
  if (h >= 90 && h <= 160) return DetectedColor.green;
  if (h <= 12 || h >= 345) return DetectedColor.red;
  return DetectedColor.other;
}

/// Plays the ring melody + shows a notification. Throttled by the caller.
class Alerter {
  final AudioPlayer _player = AudioPlayer();
  final FlutterLocalNotificationsPlugin notifications;

  Alerter(this.notifications);

  Future<void> alert(String title, String body) async {
    try {
      await _player.stop();
      await _player.play(AssetSource('alarm.mp3'));
    } catch (_) {}
    await notifications.show(
      0,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'color_watch_channel',
          'Color Watch',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  void dispose() => _player.dispose();
}
