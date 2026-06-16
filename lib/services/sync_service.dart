import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../providers/player_provider.dart';
import '../models/media_item.dart';
import 'screenshot_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  Timer? _timer;
  bool _isSyncing = false;

  /// Starts the synchronization scheduler with a delay to allow activation preferences to load.
  void start(WidgetRef ref) {
    _timer?.cancel();
    _scheduleNextSync(ref, const Duration(milliseconds: 600));
  }

  void _scheduleNextSync(WidgetRef ref, Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      await _performSync(ref);
      
      final state = ref.read(activationProvider);
      if (state.isActivated) {
        final interval = state.syncInterval > 0 ? state.syncInterval : 10;
        _scheduleNextSync(ref, Duration(seconds: interval));
      }
    });
  }

  /// Cancels sync scheduler execution.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _performSync(WidgetRef ref) async {
    // Avoid double syncing if an operation is still in progress
    if (_isSyncing) return;

    final actState = ref.read(activationProvider);
    print('Sync check called. Activated: ${actState.isActivated}, Device Code: ${actState.deviceCode}, Screen ID: ${actState.screenId}');
    if (!actState.isActivated) return;

    if (kIsWeb) {
      // Bypass network sync in Web demo mode
      ref.read(playlistProvider.notifier).setOnlineStatus(true);
      return;
    }

    _isSyncing = true;
    final screenId = actState.screenId;

    try {
      final prefs = await SharedPreferences.getInstance();
      final localVersion = prefs.getInt('playlist_version') ?? 0;
      print('Sync check initiated: Screen ID: $screenId, Local playlist version: $localVersion');

      // 1. Perform Sync query
      final syncUrl = Uri.parse(
        'https://viewsys.co.in/api/player/sync?screen_id=$screenId&version=$localVersion',
      );

      final response = await http.get(
        syncUrl,
        headers: {'Accept': 'application/json'},
      );

      ref.read(playlistProvider.notifier).setOnlineStatus(true);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          final serverVersion = data['version'] as int? ?? localVersion;
          final scheduleChanged = data['schedule_changed'] as bool? ?? false;
          final mediaChanged = data['media_changed'] as bool? ?? false;
          final takeScreenshot = data['take_screenshot'] as bool? ?? false;
          final orientation = data['orientation'] as String?;
          final restartFlag = data['restart'] as bool? ?? false;

          // Check if local database playlist is currently empty
          final isDbEmpty = ref.read(playlistProvider).items.isEmpty;

          // 2. Fetch updated schedule manifest if marked changed, versions mismatch, or local database is empty
          if (scheduleChanged || mediaChanged || serverVersion > localVersion || isDbEmpty) {
            await _fetchAndCacheSchedule(ref, screenId, serverVersion);
          }

          // 3. Capture screen if requested
          if (takeScreenshot) {
            await ScreenshotService.captureAndUpload(screenId);
          }

          // 4. Update orientation layout parameters dynamically
          if (orientation != null && orientation.isNotEmpty) {
            await ref.read(activationProvider.notifier).updateOrientation(orientation);
          }

          // 5. Handle software restarts (reloads cached lists)
          if (restartFlag) {
            await ref.read(playlistProvider.notifier).loadCachedPlaylist();
          }
        }
      } else {
        print('Sync check returned error status: ${response.statusCode}');
        if (response.statusCode == 422 || response.statusCode == 401 || response.statusCode == 400) {
          try {
            final data = jsonDecode(response.body);
            final isInvalidScreen = data is Map &&
                (data['message']?.toString().toLowerCase().contains('invalid') == true ||
                 data['errors']?.toString().toLowerCase().contains('screen_id') == true);

            if (isInvalidScreen) {
              print('Screen ID $screenId is reported invalid by server. Attempting to refresh activation...');
              // Release sync lock to allow retry
              _isSyncing = false;
              final success = await ref.read(activationProvider.notifier).refreshActivationDetails();
              if (success) {
                print('Activation details refreshed successfully. Retrying sync...');
                _performSync(ref);
                return;
              }
            }
          } catch (e) {
            print('Failed to parse sync error response: $e');
          }
        }
      }
    } catch (e) {
      print('Sync connectivity failure: $e');
      ref.read(playlistProvider.notifier).setOnlineStatus(false);
    } finally {
      _isSyncing = false;
      ref.read(playlistProvider.notifier).markInitialized();
    }
  }

  /// Helper to fetch and cache playlist schedule manifest from `/schedule`.
  Future<void> _fetchAndCacheSchedule(WidgetRef ref, String screenId, int newVersion) async {
    print('Fetching playlist schedule for Screen ID: $screenId...');
    try {
      final scheduleUrl = Uri.parse(
        'https://viewsys.co.in/api/player/schedule?screen_id=$screenId',
      );

      final response = await http.get(
        scheduleUrl,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        print('Raw schedule API response: ${response.body}');
        final data = jsonDecode(response.body);
        List<dynamic>? playlistData;
        if (data is List) {
          playlistData = data;
        } else if (data is Map && data['playlist'] is List) {
          playlistData = data['playlist'] as List<dynamic>;
        }

        if (playlistData != null) {
          // Parse JSON entries
          final List<MediaItem> items = playlistData.map((json) {
            return MediaItem.fromJson(json as Map<String, dynamic>);
          }).toList();
          print('Parsed ${items.length} media items from schedule.');

          // Caches files internally and updates provider list
          await ref.read(playlistProvider.notifier).updatePlaylist(items);

          // Update local version tracker
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('playlist_version', newVersion);
          print('Successfully synchronized playlist to version: $newVersion');
        } else {
          print('Schedule response body is not a list or a valid playlist map.');
        }
      } else {
        print('Schedule fetch returned error status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e) {
      print('Schedule synchronization failed: $e');
    }
  }
}
