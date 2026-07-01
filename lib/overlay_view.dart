import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:http/http.dart' as http;

// The floating overlay window's UI. Runs in a SEPARATE Flutter engine/isolate
// (started via the overlayMain entry point in main.dart), so it has no access
// to the main app's state. It receives the camera address from the main app
// via the overlay message channel and streams MJPEG itself.
class OverlayApp extends StatefulWidget {
  const OverlayApp({super.key});

  @override
  State<OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<OverlayApp> {
  String? _base;
  Uint8List? _frame;
  Timer? _frameTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The main app sends the camera base URL (e.g. http://192.168.43.1:8080).
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is String && event.isNotEmpty) {
        _base = event;
        _frameTimer?.cancel();
        _frameTimer = Timer.periodic(
            const Duration(milliseconds: 150), (_) => _fetchFrame());
      }
    });
  }

  // Image.network can't render an MJPEG stream, so poll single JPEG frames.
  Future<void> _fetchFrame() async {
    final base = _base;
    if (base == null || _busy) return;
    _busy = true;
    try {
      final res = await http
          .get(Uri.parse('$base/frame'))
          .timeout(const Duration(seconds: 2));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty && mounted) {
        setState(() => _frame = res.bodyBytes);
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_frame == null)
              const Center(
                child: Text('Ожидание...',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              )
            else
              Image.memory(
                _frame!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            // Tap the overlay to close it.
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => FlutterOverlayWindow.closeOverlay(),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  color: Colors.black54,
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
