import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:http/http.dart' as http;

import 'shared.dart';

class ViewerPage extends StatefulWidget {
  final FlutterLocalNotificationsPlugin notifications;
  const ViewerPage({super.key, required this.notifications});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  final TextEditingController _addr =
      TextEditingController(text: 'http://192.168.43.1:8080');
  late final Alerter _alerter;

  bool _connected = false;
  String _base = '';
  Timer? _poll;

  DetectedColor _current = DetectedColor.other;
  int _lastChangeSeen = 0;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _alerter = Alerter(widget.notifications);
  }

  void _connect() {
    var base = _addr.text.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    setState(() {
      _base = base;
      _connected = true;
      _error = '';
      _lastChangeSeen = 0;
    });
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _fetchStatus());
  }

  void _disconnect() {
    _poll?.cancel();
    setState(() => _connected = false);
  }

  // Open the live stream in a floating window over other apps.
  Future<void> _openOverlay() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      // Opens system settings; returns true once the user grants it.
      final ok = await FlutterOverlayWindow.requestPermission();
      if (ok != true) {
        if (mounted) {
          setState(() => _error =
              'Нужно разрешение «Поверх других приложений»');
        }
        return;
      }
    }

    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
    await FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      overlayTitle: 'Color Watch',
      overlayContent: 'Трансляция камеры',
      flag: OverlayFlag.defaultFlag,
      height: 320,
      width: 420,
      positionGravity: PositionGravity.auto,
    );
    // The overlay runs in a separate engine that needs a moment to start and
    // subscribe to the listener. Send the address a few times to be safe.
    for (final ms in [400, 900, 1600]) {
      await Future.delayed(Duration(milliseconds: ms));
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.shareData(_base);
      }
    }
  }

  Future<void> _fetchStatus() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/status'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final color = DetectedColorX.fromLabel(data['color'] as String? ?? 'other');
      final lastChange = (data['lastChangeMs'] as num?)?.toInt() ?? 0;

      // New color change detected on the camera side.
      if (lastChange != 0 &&
          lastChange != _lastChangeSeen &&
          _lastChangeSeen != 0) {
        _alerter.alert('Смена цвета (камера)', 'Сейчас: ${color.label}');
      }
      _lastChangeSeen = lastChange;
      if (mounted) {
        setState(() {
          _current = color;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Нет связи с камерой');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _alerter.dispose();
    _addr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Режим: Зритель')),
      body: !_connected
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Введите адрес телефона-камеры '
                    '(он показан на его экране):',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addr,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Адрес камеры',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _connect,
                    icon: const Icon(Icons.link),
                    label: const Text('Подключиться'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Container(
                    color: Colors.black,
                    width: double.infinity,
                    child: Image.network(
                      '$_base/stream',
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('Видео недоступно',
                            style: TextStyle(color: Colors.white)),
                      ),
                      loadingBuilder: (ctx, child, prog) => child,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  child: Column(
                    children: [
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
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (_error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_error,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _openOverlay,
                            icon: const Icon(Icons.picture_in_picture_alt),
                            label: const Text('Плавающее окно'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _disconnect,
                            icon: const Icon(Icons.link_off),
                            label: const Text('Отключиться'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
