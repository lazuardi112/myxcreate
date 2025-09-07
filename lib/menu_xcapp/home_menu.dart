import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/accessibility_event.dart';

class XcappPage extends StatefulWidget {
  const XcappPage({super.key});

  @override
  State<XcappPage> createState() => _XcappPageState();
}

class _XcappPageState extends State<XcappPage> {
  StreamSubscription<AccessibilityEvent?>? _sub;

  @override
  void initState() {
    super.initState();
    _listenEvents();
  }

  void _listenEvents() async {
    bool enabled =
        await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (!enabled) {
      await FlutterAccessibilityService.requestAccessibilityPermission();
    }

    _sub = FlutterAccessibilityService.accessStream.listen((event) {
      if (event != null) {
        debugPrint("Event dari ${event.packageName}: ${event.eventType}");
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text("Listening Accessibility Events...")),
    );
  }
}
