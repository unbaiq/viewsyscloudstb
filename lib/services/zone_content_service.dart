import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../providers/player_provider.dart';
import '../providers/zone_content_provider.dart';
import '../models/media_item.dart';
import 'file_manager.dart';

class ZoneContentService {
  static final ZoneContentService instance = ZoneContentService._init();
  ZoneContentService._init();

  Timer? _timer;
  bool _isSyncing = false;
  WidgetRef? _ref;

  /// Starts the zone content polling loop.
  void start(WidgetRef ref) {
    _ref = ref;
    _timer?.cancel();
    // Delay initial sync to let main layout stabilize
    _scheduleNextSync(const Duration(seconds: 2));
  }

  void _scheduleNextSync(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      await _performSync();

      final activeRef = _ref;
      if (activeRef != null && activeRef.context.mounted) {
        final state = activeRef.read(activationProvider);
        if (state.isActivated) {
          // Re-use sync interval from main activation state
          final interval = state.syncInterval > 0 ? state.syncInterval : 10;
          _scheduleNextSync(Duration(seconds: interval));
        } else {
          // Stop polling if deactivated
          stop();
        }
      }
    });
  }

  /// Stops the polling loop.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isSyncing = false;
    _ref = null;
  }

  Future<void> _performSync() async {
    if (_isSyncing) return;
    final activeRef = _ref;
    if (activeRef == null || !activeRef.context.mounted) return;

    final actState = activeRef.read(activationProvider);
    if (!actState.isActivated || (actState.layout != 'half_split' && actState.layout != 'menu_board' && actState.layout != 'four_grid' && actState.layout != 'sidebar' && actState.layout != 'triple')) return;

    if (kIsWeb || (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'))) {
      // Mock data for web demo mode
      final mockItem = MediaItem(
        id: 9999,
        url: 'https://cms.thelocads.com/assets/images/logo.png',
        type: 'image',
        duration: 10,
        order: 1,
      );
      activeRef.read(zoneContentProvider.notifier).updateItem(mockItem);
      activeRef.read(leftZoneProvider.notifier).updateItem(mockItem);
      activeRef.read(topRightZoneProvider.notifier).updateItem(mockItem);
      activeRef.read(bottomLeftZoneProvider.notifier).updateItem(mockItem);
      activeRef.read(bottomRightZoneProvider.notifier).updateItem(mockItem);
      activeRef.read(centerZoneProvider.notifier).updateItem(mockItem);
      activeRef.read(rightZoneProvider.notifier).updateItem(mockItem);
      return;
    }

    _isSyncing = true;
    final screenId = actState.screenId;

    try {
      // TODO: Confirm correct backend URL for "right zone content" with backend team.
      // Re-using the schedule sync endpoint as a placeholder that will return the unified JSON.
      final scheduleUrl = Uri.parse(
        'https://cms.thelocads.com/api/player/schedule?screen_id=$screenId',
      );

      final response = await http.get(
        scheduleUrl,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Defensive multi-key fallback pattern for the zone content field
        // TODO: Update field names when confirmed by backend team
        dynamic zoneData = data['zone_content'] ?? data['right_zone'] ?? data['cms_content'];

        if (zoneData == null && data['data'] is Map) {
          final innerData = data['data'] as Map;
          zoneData = innerData['zone_content'] ?? innerData['right_zone'] ?? innerData['cms_content'];
        }
        
        if (zoneData == null && data['cluster'] is Map) {
          final innerData = data['cluster'] as Map;
          zoneData = innerData['zone_content'] ?? innerData['right_zone'] ?? innerData['cms_content'];
        }

        if (data['layouts'] is Map) {
          final layoutsData = data['layouts'] as Map;
          zoneData ??= layoutsData['right'] ?? layoutsData['sidebar'];
        }

        dynamic leftZoneData = data['left_zone'] ?? data['menu_zone'] ?? data['menu_content'] ?? data['menu'];
        dynamic topRightZoneData = data['top_right_zone'] ?? data['top_right'] ?? data['grid_top_right_zone'] ?? data['grid_top_right'] ?? data['zone2'];
        dynamic bottomLeftZoneData = data['bottom_left_zone'] ?? data['bottom_left'] ?? data['grid_bottom_left_zone'] ?? data['grid_bottom_left'] ?? data['zone3'];
        dynamic bottomRightZoneData = data['bottom_right_zone'] ?? data['bottom_right'] ?? data['grid_bottom_right_zone'] ?? data['grid_bottom_right'] ?? data['zone4'];
        dynamic centerZoneData = data['center_zone'] ?? data['center'] ?? data['triple_center'] ?? data['triple_center_zone'];
        dynamic rightZoneData = data['right_zone'] ?? data['right'] ?? data['triple_right'] ?? data['triple_right_zone'];

        if (data['data'] is Map) {
          final innerData = data['data'] as Map;
          leftZoneData ??= innerData['left_zone'] ?? innerData['menu_zone'] ?? innerData['menu_content'] ?? innerData['menu'];
          topRightZoneData ??= innerData['top_right_zone'] ?? innerData['top_right'] ?? innerData['grid_top_right_zone'] ?? innerData['grid_top_right'] ?? innerData['zone2'];
          bottomLeftZoneData ??= innerData['bottom_left_zone'] ?? innerData['bottom_left'] ?? innerData['grid_bottom_left_zone'] ?? innerData['grid_bottom_left'] ?? innerData['zone3'];
          bottomRightZoneData ??= innerData['bottom_right_zone'] ?? innerData['bottom_right'] ?? innerData['grid_bottom_right_zone'] ?? innerData['grid_bottom_right'] ?? innerData['zone4'];
          centerZoneData ??= innerData['center_zone'] ?? innerData['center'] ?? innerData['triple_center'] ?? innerData['triple_center_zone'];
          rightZoneData ??= innerData['right_zone'] ?? innerData['right'] ?? innerData['triple_right'] ?? innerData['triple_right_zone'];
        }
        if (data['cluster'] is Map) {
          final innerData = data['cluster'] as Map;
          leftZoneData ??= innerData['left_zone'] ?? innerData['menu_zone'] ?? innerData['menu_content'] ?? innerData['menu'];
          topRightZoneData ??= innerData['top_right_zone'] ?? innerData['top_right'] ?? innerData['grid_top_right_zone'] ?? innerData['grid_top_right'] ?? innerData['zone2'];
          bottomLeftZoneData ??= innerData['bottom_left_zone'] ?? innerData['bottom_left'] ?? innerData['grid_bottom_left_zone'] ?? innerData['grid_bottom_left'] ?? innerData['zone3'];
          bottomRightZoneData ??= innerData['bottom_right_zone'] ?? innerData['bottom_right'] ?? innerData['grid_bottom_right_zone'] ?? innerData['grid_bottom_right'] ?? innerData['zone4'];
          centerZoneData ??= innerData['center_zone'] ?? innerData['center'] ?? innerData['triple_center'] ?? innerData['triple_center_zone'];
          rightZoneData ??= innerData['right_zone'] ?? innerData['right'] ?? innerData['triple_right'] ?? innerData['triple_right_zone'];
        }
        if (data['layout'] is Map) {
          final layoutMap = data['layout'] as Map;
          leftZoneData ??= layoutMap['left'] ?? layoutMap['menu'];
          topRightZoneData ??= layoutMap['top_right'] ?? layoutMap['top_right_zone'] ?? layoutMap['grid_top_right'] ?? layoutMap['zone2'];
          bottomLeftZoneData ??= layoutMap['bottom_left'] ?? layoutMap['bottom_left_zone'] ?? layoutMap['grid_bottom_left'] ?? layoutMap['zone3'];
          bottomRightZoneData ??= layoutMap['bottom_right'] ?? layoutMap['bottom_right_zone'] ?? layoutMap['grid_bottom_right'] ?? layoutMap['zone4'];
          centerZoneData ??= layoutMap['center'] ?? layoutMap['center_zone'];
          rightZoneData ??= layoutMap['right'] ?? layoutMap['right_zone'];
        }
        if (data['layouts'] is Map) {
          final layoutsData = data['layouts'] as Map;
          leftZoneData ??= layoutsData['left'] ?? layoutsData['menu'];
          topRightZoneData ??= layoutsData['top_right'] ?? layoutsData['top_right_zone'] ?? layoutsData['grid_top_right'] ?? layoutsData['zone2'];
          bottomLeftZoneData ??= layoutsData['bottom_left'] ?? layoutsData['bottom_left_zone'] ?? layoutsData['grid_bottom_left'] ?? layoutsData['zone3'];
          bottomRightZoneData ??= layoutsData['bottom_right'] ?? layoutsData['bottom_right_zone'] ?? layoutsData['grid_bottom_right'] ?? layoutsData['zone4'];
          centerZoneData ??= layoutsData['center'] ?? layoutsData['center_zone'];
          rightZoneData ??= layoutsData['right'] ?? layoutsData['right_zone'];
          
          // Fallback for specific layout key (e.g., layoutsData['triple']['center'])
          if (actState.layout != null && layoutsData[actState.layout] is Map) {
            final specificLayoutData = layoutsData[actState.layout] as Map;
            leftZoneData ??= specificLayoutData['left'] ?? specificLayoutData['menu'];
            topRightZoneData ??= specificLayoutData['top_right'] ?? specificLayoutData['top_right_zone'] ?? specificLayoutData['grid_top_right'] ?? specificLayoutData['zone2'];
            bottomLeftZoneData ??= specificLayoutData['bottom_left'] ?? specificLayoutData['bottom_left_zone'] ?? specificLayoutData['grid_bottom_left'] ?? specificLayoutData['zone3'];
            bottomRightZoneData ??= specificLayoutData['bottom_right'] ?? specificLayoutData['bottom_right_zone'] ?? specificLayoutData['grid_bottom_right'] ?? specificLayoutData['zone4'];
            centerZoneData ??= specificLayoutData['center'] ?? specificLayoutData['center_zone'];
            rightZoneData ??= specificLayoutData['right'] ?? specificLayoutData['right_zone'];
          }
        }

        // Final absolute fallback: if the backend just sends everything under the legacy `zone_content` key
        leftZoneData ??= zoneData;
        
        // If it's a grid, and the backend only sent a single list in `zone_content`, maybe it has multiple items
        if (topRightZoneData == null && zoneData is List && zoneData.isNotEmpty) {
          topRightZoneData = [zoneData[0]]; // first item
        } else {
          topRightZoneData ??= zoneData;
        }

        if (bottomLeftZoneData == null && zoneData is List && zoneData.length > 1) {
          bottomLeftZoneData = [zoneData[1]]; // second item
        } else {
          bottomLeftZoneData ??= zoneData;
        }

        if (bottomRightZoneData == null && zoneData is List && zoneData.length > 2) {
          bottomRightZoneData = [zoneData[2]]; // third item
        } else {
          bottomRightZoneData ??= zoneData;
        }

        if (centerZoneData == null && zoneData is List && zoneData.isNotEmpty) {
          centerZoneData = [zoneData[0]]; // first item for triple layout
        } else {
          centerZoneData ??= zoneData;
        }

        if (rightZoneData == null && zoneData is List && zoneData.length > 1) {
          rightZoneData = [zoneData[1]]; // second item for triple layout
        } else {
          rightZoneData ??= zoneData;
        }

        Future<void> updateProvider(dynamic provider, dynamic zData) async {
          if (zData != null && (zData is Map<String, dynamic> || (zData is List && zData.isNotEmpty && zData.first is Map))) {
            final Map<String, dynamic> dataMap = zData is List ? zData.first as Map<String, dynamic> : zData as Map<String, dynamic>;
            MediaItem item = MediaItem.fromJson(dataMap);
            
            // If it's a video, download it completely BEFORE pushing to the UI to avoid stuttering streams
            if (!kIsWeb && item.type == 'video' && item.url.isNotEmpty) {
              final localPath = await FileManager.instance.downloadFile(item.url, item.id, itemType: item.type);
              if (localPath != null) {
                item = item.copyWith(localPath: localPath);
              }
            }
            
            if (activeRef.context.mounted) {
              activeRef.read(provider.notifier).updateItem(item);
            }
          } else {
            if (activeRef.context.mounted) {
              activeRef.read(provider.notifier).setLoading(false);
            }
          }
        }

        print('[ZoneContentService] Raw data layout keys: leftZoneData=$leftZoneData, zoneData=$zoneData');

        updateProvider(zoneContentProvider, zoneData);
        updateProvider(leftZoneProvider, leftZoneData);
        updateProvider(topRightZoneProvider, topRightZoneData);
        updateProvider(bottomLeftZoneProvider, bottomLeftZoneData);
        updateProvider(bottomRightZoneProvider, bottomRightZoneData);
        updateProvider(centerZoneProvider, centerZoneData);
        updateProvider(rightZoneProvider, rightZoneData);

      } else {
        print('Zone Content API returned error status: ${response.statusCode}');
        if (activeRef.context.mounted) {
          activeRef.read(zoneContentProvider.notifier).setError('HTTP ${response.statusCode}');
          activeRef.read(centerZoneProvider.notifier).setError('HTTP ${response.statusCode}');
          activeRef.read(rightZoneProvider.notifier).setError('HTTP ${response.statusCode}');
        }
      }
    } catch (e) {
      print('Zone Content synchronization failed: $e');
      if (activeRef.context.mounted) {
        activeRef.read(zoneContentProvider.notifier).setError('Sync failed: $e');
        activeRef.read(centerZoneProvider.notifier).setError('Sync failed: $e');
        activeRef.read(rightZoneProvider.notifier).setError('Sync failed: $e');
      }
    } finally {
      _isSyncing = false;
    }
  }
}
