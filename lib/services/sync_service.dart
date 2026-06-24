import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../providers/player_provider.dart';
import '../models/media_item.dart';
import '../models/ticker_item.dart';
import 'screenshot_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  Timer? _timer;
  bool _isSyncing = false;
  bool _isFirstSync = true;
  bool _forceSyncOnStartup = true;
  WidgetRef? _ref;

  /// Starts the synchronization scheduler with a delay to allow activation preferences to load.
  void start(WidgetRef ref) {
    _ref = ref;
    _timer?.cancel();
    _scheduleNextSync(const Duration(milliseconds: 600));
  }

  void _scheduleNextSync(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      await _performSync();

      final activeRef = _ref;
      if (activeRef != null && activeRef.context.mounted) {
        final state = activeRef.read(activationProvider);
        if (state.isActivated) {
          final interval = state.syncInterval > 0 ? state.syncInterval : 10;
          _scheduleNextSync(Duration(seconds: interval));
        }
      }
    });
  }

  /// Cancels sync scheduler execution.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isFirstSync = true;
    _forceSyncOnStartup = true;
  }

  Future<void> _performSync() async {
    // Avoid double syncing if an operation is still in progress
    if (_isSyncing) return;

    final activeRef = _ref;
    if (activeRef == null || !activeRef.context.mounted) return;

    final actState = activeRef.read(activationProvider);
    print(
      'Sync check called. Activated: ${actState.isActivated}, Device Code: ${actState.deviceCode}, Screen ID: ${actState.screenId}',
    );
    if (!actState.isActivated) return;

    if (_isFirstSync) {
      _isFirstSync = false;
      try {
        await activeRef.read(activationProvider.notifier).refreshActivationDetails();
      } catch (e) {
        print('Initial activation refresh failed: $e');
      }
    }

    if (kIsWeb || (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'))) {
      // Bypass network sync in Web demo mode or widget test mode
      final currentRef = _ref;
      if (currentRef != null && currentRef.context.mounted) {
        currentRef.read(playlistProvider.notifier).setOnlineStatus(true);
        currentRef.read(playlistProvider.notifier).markInitialized();
      }
      return;
    }

    _isSyncing = true;
    final screenId = actState.screenId;

    try {
      final prefs = await SharedPreferences.getInstance();
      final localVersion = prefs.getInt('playlist_version') ?? 0;
      print(
        'Sync check initiated: Screen ID: $screenId, Local playlist version: $localVersion',
      );

      // Perform sync ping and schedule sync in parallel to run continuously and independently
      await Future.wait([
        _runSyncPing(screenId, localVersion),
        _runScheduleSync(screenId),
      ]);
    } catch (e) {
      print('Sync loop global exception: $e');
      final currentRef = _ref;
      if (currentRef != null && currentRef.context.mounted) {
        currentRef.read(playlistProvider.notifier).setOnlineStatus(false);
      }
    } finally {
      _isSyncing = false;
      final currentRef = _ref;
      if (currentRef != null && currentRef.context.mounted) {
        currentRef.read(playlistProvider.notifier).markInitialized();
      }
    }
  }

  Future<void> _runSyncPing(String screenId, int localVersion) async {
    try {
      final syncUrl = Uri.parse(
        'https://cms.thelocads.com/api/player/sync?screen_id=$screenId&version=$localVersion',
      );

      final response = await http.get(
        syncUrl,
        headers: {'Accept': 'application/json'},
      );

      final currentRef = _ref;
      if (currentRef == null || !currentRef.context.mounted) return;

      currentRef.read(playlistProvider.notifier).setOnlineStatus(true);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          final serverVersion = data['version'] as int? ?? localVersion;
          final takeScreenshot = data['take_screenshot'] as bool? ?? false;
          final orientation = data['orientation'] as String?;
          final restartFlag = data['restart'] as bool? ?? false;

          final currentRefAfterFetch = _ref;
          if (currentRefAfterFetch == null || !currentRefAfterFetch.context.mounted) return;

          // Update orientation layout parameters dynamically
          if (orientation != null && orientation.isNotEmpty) {
            final currentActState = currentRefAfterFetch.read(activationProvider);
            if (currentActState.orientation != orientation) {
              await currentRefAfterFetch
                  .read(activationProvider.notifier)
                  .updateOrientation(orientation);
            }
          }

          // Update layout dynamically
          String? layout = data['layout_type']?.toString() ?? data['layout']?.toString();
          if (layout == null && data['data'] is Map) {
            layout = (data['data'] as Map)['layout_type']?.toString() ?? (data['data'] as Map)['layout']?.toString();
          }
          if (layout == null && data['cluster'] is Map) {
            layout = (data['cluster'] as Map)['layout_type']?.toString() ?? (data['cluster'] as Map)['layout']?.toString();
          }

          // TODO: Confirm exactly which JSON key the backend uses for the sidebar URL and remove the fallback defensive parsing here
          String? parsedSidebarUrl = data['menu_url']?.toString() ?? data['sidebar_url']?.toString() ?? data['webview_url']?.toString() ?? data['cms_url']?.toString();
          if (parsedSidebarUrl == null && data['data'] is Map) {
            final inner = data['data'] as Map;
            parsedSidebarUrl = inner['menu_url']?.toString() ?? inner['sidebar_url']?.toString() ?? inner['webview_url']?.toString() ?? inner['cms_url']?.toString();
          }
          if (parsedSidebarUrl == null && data['cluster'] is Map) {
            final inner = data['cluster'] as Map;
            parsedSidebarUrl = inner['menu_url']?.toString() ?? inner['sidebar_url']?.toString() ?? inner['webview_url']?.toString() ?? inner['cms_url']?.toString();
          }

          // TODO: Confirm exactly which JSON keys the backend uses for triple layout URLs
          String? parsedCenterUrl = data['center_url']?.toString() ?? data['triple_center_url']?.toString() ?? data['webview_center_url']?.toString();
          String? parsedRightUrl = data['right_url']?.toString() ?? data['triple_right_url']?.toString() ?? data['webview_right_url']?.toString();
          if (parsedCenterUrl == null && data['data'] is Map) {
            final inner = data['data'] as Map;
            parsedCenterUrl = inner['center_url']?.toString() ?? inner['triple_center_url']?.toString() ?? inner['webview_center_url']?.toString();
          }
          if (parsedRightUrl == null && data['data'] is Map) {
            final inner = data['data'] as Map;
            parsedRightUrl = inner['right_url']?.toString() ?? inner['triple_right_url']?.toString() ?? inner['webview_right_url']?.toString();
          }
          if (parsedCenterUrl == null && data['cluster'] is Map) {
            final inner = data['cluster'] as Map;
            parsedCenterUrl = inner['center_url']?.toString() ?? inner['triple_center_url']?.toString() ?? inner['webview_center_url']?.toString();
          }
          if (parsedRightUrl == null && data['cluster'] is Map) {
            final inner = data['cluster'] as Map;
            parsedRightUrl = inner['right_url']?.toString() ?? inner['triple_right_url']?.toString() ?? inner['webview_right_url']?.toString();
          }

          // TODO: Confirm exactly which JSON key the backend uses for four_grid layout URLs
          String? parsedTopRightUrl = data['top_right_url']?.toString() ?? data['grid_top_right_url']?.toString() ?? data['zone2_url']?.toString();
          String? parsedBottomLeftUrl = data['bottom_left_url']?.toString() ?? data['grid_bottom_left_url']?.toString() ?? data['zone3_url']?.toString();
          String? parsedBottomRightUrl = data['bottom_right_url']?.toString() ?? data['grid_bottom_right_url']?.toString() ?? data['zone4_url']?.toString();
          if (parsedTopRightUrl == null && data['data'] is Map) {
            final inner = data['data'] as Map;
            parsedTopRightUrl = inner['top_right_url']?.toString() ?? inner['grid_top_right_url']?.toString() ?? inner['zone2_url']?.toString();
            parsedBottomLeftUrl = inner['bottom_left_url']?.toString() ?? inner['grid_bottom_left_url']?.toString() ?? inner['zone3_url']?.toString();
            parsedBottomRightUrl = inner['bottom_right_url']?.toString() ?? inner['grid_bottom_right_url']?.toString() ?? inner['zone4_url']?.toString();
          }
          if (parsedTopRightUrl == null && data['cluster'] is Map) {
            final inner = data['cluster'] as Map;
            parsedTopRightUrl = inner['top_right_url']?.toString() ?? inner['grid_top_right_url']?.toString() ?? inner['zone2_url']?.toString();
            parsedBottomLeftUrl = inner['bottom_left_url']?.toString() ?? inner['grid_bottom_left_url']?.toString() ?? inner['zone3_url']?.toString();
            parsedBottomRightUrl = inner['bottom_right_url']?.toString() ?? inner['grid_bottom_right_url']?.toString() ?? inner['zone4_url']?.toString();
          }

          parsedSidebarUrl ??= 'https://cms.thelocads.com/clusters';
          parsedCenterUrl ??= 'https://cms.thelocads.com/clusters';
          parsedRightUrl ??= 'https://cms.thelocads.com/clusters';
          parsedTopRightUrl ??= 'https://cms.thelocads.com/clusters';
          parsedBottomLeftUrl ??= 'https://cms.thelocads.com/clusters';
          parsedBottomRightUrl ??= 'https://cms.thelocads.com/clusters';

          final currentActState = currentRefAfterFetch.read(activationProvider);
          layout = layout?.trim().toLowerCase();
          if (layout == 'half') layout = 'half_split';
          if (layout == 'menu') layout = 'menu_board';
          if (layout == 'grid') layout = 'four_grid';
          if (layout != null && layout != 'ticker' && layout != 'header' && layout != 'half_split' && layout != 'sidebar' && layout != 'triple' && layout != 'menu_board' && layout != 'four_grid') {
            layout = 'fullscreen';
          }

          final finalLayoutToSave = layout ?? currentActState.layout;
          final finalSidebarUrlToSave = parsedSidebarUrl ?? currentActState.sidebarUrl;
          final finalCenterUrlToSave = parsedCenterUrl ?? currentActState.centerUrl;
          final finalRightUrlToSave = parsedRightUrl ?? currentActState.rightUrl;
          final finalTopRightUrlToSave = parsedTopRightUrl ?? currentActState.topRightUrl;
          final finalBottomLeftUrlToSave = parsedBottomLeftUrl ?? currentActState.bottomLeftUrl;
          final finalBottomRightUrlToSave = parsedBottomRightUrl ?? currentActState.bottomRightUrl;

          if (currentActState.layout != finalLayoutToSave || 
              currentActState.sidebarUrl != finalSidebarUrlToSave || 
              currentActState.centerUrl != finalCenterUrlToSave || 
              currentActState.rightUrl != finalRightUrlToSave ||
              currentActState.topRightUrl != finalTopRightUrlToSave ||
              currentActState.bottomLeftUrl != finalBottomLeftUrlToSave ||
              currentActState.bottomRightUrl != finalBottomRightUrlToSave) {
            await currentRefAfterFetch.read(activationProvider.notifier).updateLayout(
              finalLayoutToSave, 
              sidebarUrl: finalSidebarUrlToSave, 
              centerUrl: finalCenterUrlToSave, 
              rightUrl: finalRightUrlToSave,
              topRightUrl: finalTopRightUrlToSave,
              bottomLeftUrl: finalBottomLeftUrlToSave,
              bottomRightUrl: finalBottomRightUrlToSave,
            );
          }

          final activeLayout = finalLayoutToSave;
          dynamic tickersData = _extractTextForLayout(data as Map<String, dynamic>, activeLayout);

          if (tickersData != null) {
            final List<TickerItem> parsedTickers = [];
            if (tickersData is List) {
              for (final item in tickersData) {
                if (item is Map) {
                  parsedTickers.add(TickerItem.fromJson(Map<String, dynamic>.from(item)));
                } else if (item != null) {
                  parsedTickers.add(TickerItem(
                    id: parsedTickers.length + 1,
                    text: item.toString(),
                  ));
                }
              }
            } else if (tickersData is Map) {
              parsedTickers.add(TickerItem.fromJson(Map<String, dynamic>.from(tickersData)));
            } else {
              parsedTickers.add(TickerItem(
                id: 1,
                text: tickersData.toString(),
              ));
            }

            if (parsedTickers.isNotEmpty) {
              print('Parsed ${parsedTickers.length} ticker items from sync successfully: ${parsedTickers.map((e) => e.text).join(", ")}');
              await currentRefAfterFetch.read(tickersProvider.notifier).updateTickers(parsedTickers);
            }
          }



          // Capture screen if requested
          if (takeScreenshot) {
            await ScreenshotService.captureAndUpload(screenId);
          }

          // Handle software restarts (reloads cached lists)
          if (restartFlag) {
            await currentRefAfterFetch.read(activationProvider.notifier).refreshActivationDetails();
            await currentRefAfterFetch.read(playlistProvider.notifier).loadCachedPlaylist();
          }

          // Update local version tracker
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('playlist_version', serverVersion);
        }
      } else {
        print('Sync check returned error status: ${response.statusCode}');
        if (response.statusCode == 422 ||
            response.statusCode == 401 ||
            response.statusCode == 400) {
          try {
            final data = jsonDecode(response.body);
            final isInvalidScreen =
                data is Map &&
                (data['message']?.toString().toLowerCase().contains(
                          'invalid',
                        ) ==
                    true ||
                    data['errors']?.toString().toLowerCase().contains(
                          'screen_id',
                        ) ==
                    true);

            if (isInvalidScreen) {
              print('Screen ID $screenId is reported invalid by server. Attempting to refresh activation...');
              final success = await currentRef
                  .read(activationProvider.notifier)
                  .refreshActivationDetails();
              if (success) {
                print('Activation details refreshed successfully.');
              } else {
                print('Failed to refresh activation, disconnecting screen...');
                await currentRef.read(activationProvider.notifier).disconnect();
              }
            }
          } catch (e) {
            print('Failed to parse sync error response: $e');
          }
        }
      }
    } catch (e) {
      print('Sync ping connection failure: $e');
    }
  }

  Future<void> _runScheduleSync(String screenId) async {
    print('Fetching playlist schedule for Screen ID: $screenId...');
    try {
      final scheduleUrl = Uri.parse(
        'https://cms.thelocads.com/api/player/schedule?screen_id=$screenId',
      );

      final response = await http.get(
        scheduleUrl,
        headers: {'Accept': 'application/json'},
      );

      final currentRef = _ref;
      if (currentRef == null || !currentRef.context.mounted) return;

      if (response.statusCode == 200) {
        print('Raw schedule API response: ${response.body}');
        final data = jsonDecode(response.body);
        
        if (data is Map) {
          String? layout = data['layout_type']?.toString() ?? data['layout']?.toString();
          if (layout == null && data['data'] is Map) {
            layout = (data['data'] as Map)['layout_type']?.toString() ?? (data['data'] as Map)['layout']?.toString();
          }
          if (layout == null && data['cluster'] is Map) {
            layout = (data['cluster'] as Map)['layout_type']?.toString() ?? (data['cluster'] as Map)['layout']?.toString();
          }

          // TODO: Confirm exactly which JSON key the backend uses for the sidebar URL and remove the fallback defensive parsing here
          String? parsedSidebarUrl = data['menu_url']?.toString() ?? data['sidebar_url']?.toString() ?? data['webview_url']?.toString() ?? data['cms_url']?.toString();
          if (parsedSidebarUrl == null && data['data'] is Map) {
            final inner = data['data'] as Map;
            parsedSidebarUrl = inner['menu_url']?.toString() ?? inner['sidebar_url']?.toString() ?? inner['webview_url']?.toString() ?? inner['cms_url']?.toString();
          }
          if (parsedSidebarUrl == null && data['cluster'] is Map) {
            final inner = data['cluster'] as Map;
            parsedSidebarUrl = inner['menu_url']?.toString() ?? inner['sidebar_url']?.toString() ?? inner['webview_url']?.toString() ?? inner['cms_url']?.toString();
          }

          // TODO: Confirm exactly which JSON keys the backend uses for triple layout URLs
          String? parsedCenterUrl = data['center_url']?.toString() ?? data['triple_center_url']?.toString() ?? data['webview_center_url']?.toString();
          String? parsedRightUrl = data['right_url']?.toString() ?? data['triple_right_url']?.toString() ?? data['webview_right_url']?.toString();
          if (parsedCenterUrl == null && data['data'] is Map) {
            final inner = data['data'] as Map;
            parsedCenterUrl = inner['center_url']?.toString() ?? inner['triple_center_url']?.toString() ?? inner['webview_center_url']?.toString();
          }
          if (parsedRightUrl == null && data['data'] is Map) {
            final inner = data['data'] as Map;
            parsedRightUrl = inner['right_url']?.toString() ?? inner['triple_right_url']?.toString() ?? inner['webview_right_url']?.toString();
          }
          if (parsedCenterUrl == null && data['cluster'] is Map) {
            final inner = data['cluster'] as Map;
            parsedCenterUrl = inner['center_url']?.toString() ?? inner['triple_center_url']?.toString() ?? inner['webview_center_url']?.toString();
          }
          if (parsedRightUrl == null && data['cluster'] is Map) {
            final inner = data['cluster'] as Map;
            parsedRightUrl = inner['right_url']?.toString() ?? inner['triple_right_url']?.toString() ?? inner['webview_right_url']?.toString();
          }

          // TODO: Confirm exactly which JSON key the backend uses for four_grid layout URLs
          String? parsedTopRightUrl = data['top_right_url']?.toString() ?? data['grid_top_right_url']?.toString() ?? data['zone2_url']?.toString();
          String? parsedBottomLeftUrl = data['bottom_left_url']?.toString() ?? data['grid_bottom_left_url']?.toString() ?? data['zone3_url']?.toString();
          String? parsedBottomRightUrl = data['bottom_right_url']?.toString() ?? data['grid_bottom_right_url']?.toString() ?? data['zone4_url']?.toString();
          if (parsedTopRightUrl == null && data['data'] is Map) {
            final inner = data['data'] as Map;
            parsedTopRightUrl = inner['top_right_url']?.toString() ?? inner['grid_top_right_url']?.toString() ?? inner['zone2_url']?.toString();
            parsedBottomLeftUrl = inner['bottom_left_url']?.toString() ?? inner['grid_bottom_left_url']?.toString() ?? inner['zone3_url']?.toString();
            parsedBottomRightUrl = inner['bottom_right_url']?.toString() ?? inner['grid_bottom_right_url']?.toString() ?? inner['zone4_url']?.toString();
          }
          if (parsedTopRightUrl == null && data['cluster'] is Map) {
            final inner = data['cluster'] as Map;
            parsedTopRightUrl = inner['top_right_url']?.toString() ?? inner['grid_top_right_url']?.toString() ?? inner['zone2_url']?.toString();
            parsedBottomLeftUrl = inner['bottom_left_url']?.toString() ?? inner['grid_bottom_left_url']?.toString() ?? inner['zone3_url']?.toString();
            parsedBottomRightUrl = inner['bottom_right_url']?.toString() ?? inner['grid_bottom_right_url']?.toString() ?? inner['zone4_url']?.toString();
          }

          parsedSidebarUrl ??= 'https://cms.thelocads.com/clusters';
          parsedCenterUrl ??= 'https://cms.thelocads.com/clusters';
          parsedRightUrl ??= 'https://cms.thelocads.com/clusters';
          parsedTopRightUrl ??= 'https://cms.thelocads.com/clusters';
          parsedBottomLeftUrl ??= 'https://cms.thelocads.com/clusters';
          parsedBottomRightUrl ??= 'https://cms.thelocads.com/clusters';

          final currentActState = currentRef.read(activationProvider);
          layout = layout?.trim().toLowerCase();
          if (layout == 'half') layout = 'half_split';
          if (layout == 'menu') layout = 'menu_board';
          if (layout == 'grid') layout = 'four_grid';
          if (layout != null && layout != 'ticker' && layout != 'header' && layout != 'half_split' && layout != 'sidebar' && layout != 'triple' && layout != 'menu_board' && layout != 'four_grid') {
            layout = 'fullscreen';
          }

          final finalLayoutToSave = layout ?? currentActState.layout;
          final finalSidebarUrlToSave = parsedSidebarUrl ?? currentActState.sidebarUrl;
          final finalCenterUrlToSave = parsedCenterUrl ?? currentActState.centerUrl;
          final finalRightUrlToSave = parsedRightUrl ?? currentActState.rightUrl;
          final finalTopRightUrlToSave = parsedTopRightUrl ?? currentActState.topRightUrl;
          final finalBottomLeftUrlToSave = parsedBottomLeftUrl ?? currentActState.bottomLeftUrl;
          final finalBottomRightUrlToSave = parsedBottomRightUrl ?? currentActState.bottomRightUrl;

          if (currentActState.layout != finalLayoutToSave || 
              currentActState.sidebarUrl != finalSidebarUrlToSave || 
              currentActState.centerUrl != finalCenterUrlToSave || 
              currentActState.rightUrl != finalRightUrlToSave ||
              currentActState.topRightUrl != finalTopRightUrlToSave ||
              currentActState.bottomLeftUrl != finalBottomLeftUrlToSave ||
              currentActState.bottomRightUrl != finalBottomRightUrlToSave) {
            await currentRef.read(activationProvider.notifier).updateLayout(
              finalLayoutToSave, 
              sidebarUrl: finalSidebarUrlToSave, 
              centerUrl: finalCenterUrlToSave, 
              rightUrl: finalRightUrlToSave,
              topRightUrl: finalTopRightUrlToSave,
              bottomLeftUrl: finalBottomLeftUrlToSave,
              bottomRightUrl: finalBottomRightUrlToSave,
            );
          }

          final activeLayout = finalLayoutToSave;
          dynamic tickersData = _extractTextForLayout(data as Map<String, dynamic>, activeLayout);

          if (tickersData != null) {
            final List<TickerItem> parsedTickers = [];
            if (tickersData is List) {
              for (final item in tickersData) {
                if (item is Map) {
                  parsedTickers.add(TickerItem.fromJson(Map<String, dynamic>.from(item)));
                } else if (item != null) {
                  parsedTickers.add(TickerItem(
                    id: parsedTickers.length + 1,
                    text: item.toString(),
                  ));
                }
              }
            } else if (tickersData is Map) {
              parsedTickers.add(TickerItem.fromJson(Map<String, dynamic>.from(tickersData)));
            } else {
              parsedTickers.add(TickerItem(
                id: 1,
                text: tickersData.toString(),
              ));
            }

            if (parsedTickers.isNotEmpty) {
              print('Parsed ${parsedTickers.length} ticker items successfully: ${parsedTickers.map((e) => e.text).join(", ")}');
              await currentRef.read(tickersProvider.notifier).updateTickers(parsedTickers);
            }
          }
        }

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
          await currentRef.read(playlistProvider.notifier).updatePlaylist(items);
        } else {
          print(
            'Schedule response body is not a list or a valid playlist map.',
          );
        }
      } else {
        print(
          'Schedule fetch returned error status: ${response.statusCode}, Body: ${response.body}',
        );
      }
    } catch (e) {
      print('Schedule synchronization failed: $e');
    }
  }

  dynamic _extractTextForLayout(Map<String, dynamic> data, String layout) {
    dynamic extract(Map<String, dynamic> map, String layoutType) {
      if (layoutType == 'header') {
        return map['header_text'] ?? map['headerText'];
      } else {
        return map['ticker_type'] ?? 
               map['tickerType'] ?? 
               map['tickers'] ?? 
               map['ticker'] ?? 
               map['ticker_text'] ?? 
               map['tickerText'] ?? 
               map['tickers_text'];
      }
    }

    dynamic textData = extract(data, layout);
    if (textData == null && data['data'] is Map) {
      textData = extract(data['data'] as Map<String, dynamic>, layout);
    }
    if (textData == null && data['cluster'] is Map) {
      textData = extract(data['cluster'] as Map<String, dynamic>, layout);
    }
    return textData;
  }
}
