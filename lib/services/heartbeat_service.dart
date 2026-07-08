import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import '../providers/player_provider.dart';

class HeartbeatService {
  static final HeartbeatService instance = HeartbeatService._init();
  HeartbeatService._init();

  Timer? _timer;
  WidgetRef? _ref;

  /// Starts the telemetry heartbeat checker executing every 5 minutes.
  void start(WidgetRef ref) {
    _ref = ref;
    _timer?.cancel();
    // Immediate call on activation, then trigger periodically
    _sendHeartbeat();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _sendHeartbeat());
  }

  /// Cancels telemetry heartbeat checker execution.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sendHeartbeat() async {
    final activeRef = _ref;
    if (activeRef == null || !activeRef.context.mounted) return;

    final state = activeRef.read(activationProvider);
    if (!state.isActivated) return;

    final coords = await _determinePosition();
    final screenIdInt = int.tryParse(state.screenId) ?? 0;
    final Map<String, dynamic> bodyData = {
      'screen_id': screenIdInt,
      'app_version': '1.0',
    };
    if (coords != null) {
      bodyData['latitude'] = coords['latitude'];
      bodyData['longitude'] = coords['longitude'];
    }

    try {
      final url = Uri.parse('https://viewsys.co.in/api/player/heartbeat');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(bodyData),
      );

      if (response.statusCode == 200) {
        print('Heartbeat status ok: ${response.body}');
      } else {
        print('Heartbeat error status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e) {
      print('Heartbeat connection failed: $e');
    }
  }

  /// Determines geolocation exactly. Returns null if permission is denied/service is disabled.
  Future<Map<String, double>?> _determinePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
  
      var status = await Permission.location.status;
      if (status.isDenied) {
        status = await Permission.location.request();
        if (status.isDenied) return null;
      }

      if (status.isPermanentlyDenied) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
      };
    } catch (e) {
      print('Geolocation lookup failure: $e');
      return null;
    }
  }
}
