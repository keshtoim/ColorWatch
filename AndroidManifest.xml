import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

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
  String? _streamUrl;

  @override
  void initState() {
    super.initState();
    // The main app sends the camera base URL (e.g. http://192.168.43.1:8080).
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is String && event.isNotEmpty) {
        setState(() => _streamUrl = '$event/stream');
      }
    });
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
            if (_streamUrl == null)
              const Center(
                child: Text('Ожидание...',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              )
            else
              Image.network(
                _streamUrl!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Center(
                  child: Text('Нет видео',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                loadingBuilder: (_, child, prog) => child,
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
