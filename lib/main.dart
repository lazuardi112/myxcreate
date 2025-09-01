// lib/main.dart
import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

/// AppState implements WidgetsBindingObserver in order to try to (re)start
/// the notification stream when the app resumes (user may have gone to Settings)
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<ServiceNotificationEvent?>? _subscription;
  final List<ServiceNotificationEvent> _events = [];
  bool _isPermissionGranted = false;
  bool _isStreaming = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionAndAutoStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStream();
    super.dispose();
  }

  /// Called when app lifecycle changes — when returning from Settings we try again
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // brief delay to allow system settings to settle
      Future.delayed(const Duration(milliseconds: 400), () {
        _checkPermissionAndAutoStart();
      });
    }
  }

  /// Check permission and start stream if granted
  Future<void> _checkPermissionAndAutoStart() async {
    try {
      final granted = await NotificationListenerService.isPermissionGranted();
      setState(() {
        _isPermissionGranted = granted;
        _statusMessage = granted ? 'Permission granted' : 'Permission NOT granted';
      });

      if (granted && !_isStreaming) {
        await _startStream();
      }
    } catch (e, st) {
      log('Error checking permission: $e\n$st');
      setState(() {
        _statusMessage = 'Error checking permission';
      });
    }
  }

  /// Ask OS to grant notification access (opens Settings on Android)
  Future<void> _requestPermission() async {
    try {
      final result = await NotificationListenerService.requestPermission();
      // requestPermission opens Settings — user must enable the "Notification access".
      // After returning to the app, didChangeAppLifecycleState will trigger _checkPermissionAndAutoStart()
      setState(() {
        _statusMessage = 'requestPermission returned: $result';
      });
      // also run check now
      await _checkPermissionAndAutoStart();
    } catch (e, st) {
      log('requestPermission error: $e\n$st');
      setState(() {
        _statusMessage = 'requestPermission failed';
      });
    }
  }

  /// Start listening to notifications stream
  Future<void> _startStream() async {
    if (_isStreaming) return;
    try {
      // ensure permission still present
      final granted = await NotificationListenerService.isPermissionGranted();
      if (!granted) {
        setState(() {
          _isPermissionGranted = false;
          _statusMessage = 'Permission not granted - cannot start stream';
        });
        return;
      }

      // cancel existing subscription if any
      await _subscription?.cancel();

      _subscription = NotificationListenerService.notificationsStream.listen(
        (ServiceNotificationEvent? event) {
          try {
            if (event == null) return;
            log('Incoming notification: ${event.packageName} | ${event.title}');
            // insert to top
            setState(() {
              _events.insert(0, event);
            });
          } catch (e, st) {
            log('Error handling event: $e\n$st');
          }
        },
        onError: (err, st) {
          log('notificationsStream error: $err\n$st');
          setState(() {
            _statusMessage = 'Stream error: $err';
          });
        },
        cancelOnError: false,
      );

      setState(() {
        _isStreaming = true;
        _isPermissionGranted = true;
        _statusMessage = 'Stream started';
      });
    } catch (e, st) {
      log('startStream failed: $e\n$st');
      setState(() {
        _statusMessage = 'Failed to start stream';
      });
    }
  }

  /// Stop listening
  Future<void> _stopStream() async {
    try {
      await _subscription?.cancel();
      _subscription = null;
    } catch (e) {
      log('stopStream cancel error: $e');
    }
    setState(() {
      _isStreaming = false;
      _statusMessage = 'Stream stopped';
    });
  }

  /// Send a direct reply if the event supports reply
  Future<void> _sendReply(ServiceNotificationEvent ev) async {
    try {
      if (ev.canReply == true) {
        final ok = await ev.sendReply('This is an auto response');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Reply sent' : 'Reply failed')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply not supported for this notification')));
      }
    } catch (e) {
      log('sendReply error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('sendReply error (see log)')));
    }
  }

  /// Clear displayed list
  void _clearEvents() {
    setState(() {
      _events.clear();
    });
  }

  Widget _buildEventTile(ServiceNotificationEvent ev) {
    final title = ev.title ?? '(No title)';
    final content = ev.content ?? '(No content)';
    final pkg = ev.packageName ?? '-';
    Widget leading = const SizedBox.shrink();

    try {
      if (ev.appIcon != null) {
        leading = Image.memory(ev.appIcon!, width: 48, height: 48, fit: BoxFit.contain);
      } else if (ev.largeIcon != null) {
        leading = Image.memory(ev.largeIcon!, width: 48, height: 48, fit: BoxFit.contain);
      } else {
        leading = const Icon(Icons.notifications, size: 40);
      }
    } catch (_) {
      leading = const Icon(Icons.notifications, size: 40);
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: ListTile(
        leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: leading),
        title: Text(title),
        subtitle: Text('$pkg\n$content', maxLines: 3, overflow: TextOverflow.ellipsis),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.reply),
              tooltip: ev.canReply == true ? 'Reply' : 'No reply',
              onPressed: ev.canReply == true ? () => _sendReply(ev) : null,
            ),
          ],
        ),
        onTap: () {
          // show details dialog
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Package: $pkg'),
                    const SizedBox(height: 8),
                    Text('Content:\n$content'),
                    const SizedBox(height: 8),
                    Text('Can reply: ${ev.canReply == true}'),
                    const SizedBox(height: 8),
                    ev.largeIcon != null ? Image.memory(ev.largeIcon!) : const SizedBox.shrink(),
                    ev.extrasPicture != null ? Image.memory(ev.extrasPicture!) : const SizedBox.shrink(),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permissionText = _isPermissionGranted ? 'Granted' : 'Not granted';
    final streamText = _isStreaming ? 'Running' : 'Stopped';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Notification Listener Example',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Notification Listener Demo'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: 'Clear list',
              onPressed: _clearEvents,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // status row
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Text('Permission: $permissionText'),
                    const SizedBox(width: 12),
                    Text('Stream: $streamText'),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_statusMessage, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),

              // control buttons
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.settings),
                      label: const Text('Request Permission'),
                      onPressed: _requestPermission,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Check Permission'),
                      onPressed: _checkPermissionAndAutoStart,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Stream'),
                      onPressed: _startStream,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Stream'),
                      onPressed: _stopStream,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear UI'),
                      onPressed: _clearEvents,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // events list
              Expanded(
                child: _events.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.notifications_off, size: 60, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('No notifications received yet'),
                            SizedBox(height: 8),
                            Text('Press Request Permission → enable "Notification access" in Settings'),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          // simply rebuild; most recent are at index 0
                          setState(() {});
                        },
                        child: ListView.builder(
                          itemCount: _events.length,
                          itemBuilder: (_, idx) => _buildEventTile(_events[idx]),
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
