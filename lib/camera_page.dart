import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image/image.dart' as img;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'shared.dart';

const int kServerPort = 8080;

// Payload passed to the isolate that encodes a frame to JPEG.
class _EncodeJob {
  final Uint8List y, u, v;
  final int width, height, yRowStride, uvRowStride, uvPixelStride;
  _EncodeJob(this.y, this.u, this.v, this.width, this.height, this.yRowStride,
      this.uvRowStride, this.uvPixelStride);
}

// Runs in a background isolate via compute(). Converts YUV420 -> RGB ->
// downscaled JPEG. No camera/Flutter objects are touched here.
Uint8List _encodeJob(_EncodeJob j) {
  const scale = 2;
  final ow = j.width ~/ scale, oh = j.height ~/ scale;
  final image = img.Image(width: ow, height: oh);
  for (int y = 0; y < oh; y++) {
    final sy = y * scale;
    for (int x = 0; x < ow; x++) {
      final sx = x * scale;
      final yIndex = sy * j.yRowStride + sx;
      final uvIndex = (sy ~/ 2) * j.uvRowStride + (sx ~/ 2) * j.uvPixelStride;
      final yVal = j.y[yIndex];
      final uVal = j.u[uvIndex];
      final vVal = j.v[uvIndex];
      final r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
      final g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
          .round()
          .clamp(0, 255);
      final b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return img.encodeJpg(image, quality: 55);
}

class CameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FlutterLocalNotificationsPlugin notifications;
  const CameraPage(
      {super.key, required this.cameras, required this.notifications});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  late final Alerter _alerter;

  bool _busy = false;
  bool _encoding = false;
  bool _serviceOn = false;

  DetectedColor _current = DetectedColor.other;
  DetectedColor _last = DetectedColor.other;
  double _hue = 0, _sat = 0, _val = 0;
  DateTime _lastAlert = DateTime.fromMillisecondsSinceEpoch(0);

  HttpServer? _server;
  String _ip = '...';
  Uint8List? _latestJpeg;
  String _viewerHtml = '<html><body>Loading…</body></html>';
  DateTime _lastEncode = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastChange = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _alerter = Alerter(widget.notifications);
    _init();
  }

  Future<void> _init() async {
    await _initForegroundTask();
    await _initCamera();
    await _startServer();
  }

  Future<void> _initForegroundTask() async {
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'color_watch_service',
        channelName: 'Color Watch background service',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _startService() async {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Color Watch активно',
      notificationText: 'Слежу за цветом и раздаю видео',
      callback: startCallback,
    );
    setState(() => _serviceOn = true);
  }

  Future<void> _stopService() async {
    await FlutterForegroundTask.stopService();
    setState(() => _serviceOn = false);
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    final controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.startImageStream(_onFrame);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _startServer() async {
    try {
      _viewerHtml = await rootBundle.loadString('assets/viewer.html');
    } catch (_) {}
    _ip = await _detectIp();
    try {
      _server = await shelf_io.serve(
          const Pipeline().addHandler(_router), InternetAddress.anyIPv4, kServerPort);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  // Finds the address other devices should use to reach this phone. On a normal
  // Wi-Fi network getWifiIP() returns the right client IP. But when this phone is
  // the hotspot host, its Wi-Fi client interface is down and getWifiIP() returns
  // null — the real address lives on the access-point interface (e.g.
  // 192.168.43.205, not always the textbook 192.168.43.1). So fall back to
  // scanning the network interfaces for a private LAN address.
  Future<String> _detectIp() async {
    try {
      final wifiIp = await NetworkInfo().getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0') {
        return wifiIp;
      }
    } catch (_) {}
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? firstIp;
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          firstIp ??= addr.address;
          if (_isPrivateLan(addr.address)) return addr.address;
        }
      }
      if (firstIp != null) return firstIp;
    } catch (_) {}
    return '192.168.43.1';
  }

  bool _isPrivateLan(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    // 172.16.0.0 – 172.31.255.255
    final m = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
    if (m != null) {
      final second = int.tryParse(m.group(1)!) ?? 0;
      return second >= 16 && second <= 31;
    }
    return false;
  }

  Future<Response> _router(Request req) async {
    final path = req.url.path;
    if (path == 'status') {
      return Response.ok(
        jsonEncode({
          'color': _current.label,
          'lastChangeMs': _lastChange.millisecondsSinceEpoch,
          'hue': _hue.round(),
        }),
        headers: {'content-type': 'application/json'},
      );
    }
    if (path == 'stream') {
      final controller = StreamController<List<int>>();
      const boundary = 'frame';
      final timer = Timer.periodic(const Duration(milliseconds: 160), (t) {
        if (controller.isClosed) {
          t.cancel();
          return;
        }
        final jpeg = _latestJpeg;
        if (jpeg == null) return;
        controller.add(utf8.encode(
            '--$boundary\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpeg.length}\r\n\r\n'));
        controller.add(jpeg);
        controller.add(utf8.encode('\r\n'));
      });
      controller.onCancel = () => timer.cancel();
      return Response.ok(
        controller.stream,
        headers: {
          'content-type': 'multipart/x-mixed-replace; boundary=$boundary',
          'cache-control': 'no-cache',
        },
        context: {'shelf.io.buffer_output': false},
      );
    }
    return Response.ok(
      _viewerHtml,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }

  void _onFrame(CameraImage image) {
    if (_busy) return;
    _busy = true;

    final rgb = _averageCenterColorYuv(image);
    final hsv = rgbToHsv(rgb[0], rgb[1], rgb[2]);
    final color = classify(hsv[0], hsv[1], hsv[2]);

    _hue = hsv[0];
    _sat = hsv[1];
    _val = hsv[2];
    _current = color;

    if (color != DetectedColor.other &&
        _last != DetectedColor.other &&
        color != _last) {
      _lastChange = DateTime.now();
      _alert(_last, color);
    }
    if (color != DetectedColor.other) _last = color;

    // Encode a JPEG for the stream ~5 fps, off the UI thread.
    final now = DateTime.now();
    if (!_encoding && now.difference(_lastEncode).inMilliseconds > 200) {
      _lastEncode = now;
      _encodeFrame(image);
    }

    if (mounted) setState(() {});
    _busy = false;
  }

  Future<void> _encodeFrame(CameraImage image) async {
    _encoding = true;
    try {
      final job = _EncodeJob(
        image.planes[0].bytes,
        image.planes[1].bytes,
        image.planes[2].bytes,
        image.width,
        image.height,
        image.planes[0].bytesPerRow,
        image.planes[1].bytesPerRow,
        image.planes[1].bytesPerPixel ?? 1,
      );
      final jpeg = await compute(_encodeJob, job);
      _latestJpeg = jpeg;
    } catch (_) {
    } finally {
      _encoding = false;
    }
  }

  Future<void> _alert(DetectedColor from, DetectedColor to) async {
    final now = DateTime.now();
    if (now.difference(_lastAlert).inSeconds < 3) return;
    _lastAlert = now;
    await _alerter.alert('Смена цвета', '${from.label} -> ${to.label}');
  }

  List<int> _averageCenterColorYuv(CameraImage image) {
    final width = image.width, height = image.height;
    final x0 = width ~/ 3, x1 = width * 2 ~/ 3;
    final y0 = height ~/ 3, y1 = height * 2 ~/ 3;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    int rSum = 0, gSum = 0, bSum = 0, count = 0;
    const step = 4;
    for (int y = y0; y < y1; y += step) {
      for (int x = x0; x < x1; x += step) {
        final yIndex = y * yPlane.bytesPerRow + x;
        final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
        final yVal = yPlane.bytes[yIndex];
        final uVal = uPlane.bytes[uvIndex];
        final vVal = vPlane.bytes[uvIndex];
        final r = (yVal + 1.370705 * (vVal - 128)).round();
        final g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
            .round();
        final b = (yVal + 1.732446 * (uVal - 128)).round();
        rSum += r.clamp(0, 255);
        gSum += g.clamp(0, 255);
        bSum += b.clamp(0, 255);
        count++;
      }
    }
    if (count == 0) return [0, 0, 0];
    return [rSum ~/ count, gSum ~/ count, bSum ~/ count];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      if (!_serviceOn) c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null || !_controller!.value.isInitialized) {
        _initCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _server?.close(force: true);
    _alerter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Режим: Камера')),
      body: (widget.cameras.isEmpty)
          ? const Center(child: Text('Камера не найдена'))
          : (c == null || !c.value.isInitialized)
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CameraPreview(c),
                          FractionallySizedBox(
                            widthFactor: 1 / 3,
                            heightFactor: 1 / 3,
                            child: Container(
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      width: double.infinity,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            color: Colors.black12,
                            child: Column(
                              children: [
                                const Text('Адрес для второго телефона:'),
                                SelectableText(
                                  'http://$_ip:$kServerPort',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _current.swatch,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(_current.label.toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed:
                                _serviceOn ? _stopService : _startService,
                            icon: Icon(
                                _serviceOn ? Icons.stop : Icons.play_arrow),
                            label: Text(_serviceOn
                                ? 'Остановить режим 24/7'
                                : 'Включить режим 24/7'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_CamTaskHandler());
}

class _CamTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime t, TaskStarter s) async {}
  @override
  void onRepeatEvent(DateTime t) {}
  @override
  Future<void> onDestroy(DateTime t) async {}
}
