import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import '../models/ticker_item.dart';
import '../services/database_helper.dart';
import '../services/file_manager.dart';
import '../services/video_preload_manager.dart';

// --- Activation State Model & Notifier ---

class ActivationState {
  final bool isActivated;
  final bool isLoading;
  final String deviceCode;
  final String screenId;
  final String companyId;
  final String orientation;
  final int syncInterval;
  final String layout;
  final String? sidebarUrl;
  final String? centerUrl;
  final String? rightUrl;
  final String? topRightUrl;
  final String? bottomLeftUrl;
  final String? bottomRightUrl;

  const ActivationState({
    required this.isActivated,
    required this.isLoading,
    required this.deviceCode,
    required this.screenId,
    required this.companyId,
    required this.orientation,
    required this.syncInterval,
    required this.layout,
    this.sidebarUrl,
    this.centerUrl,
    this.rightUrl,
    this.topRightUrl,
    this.bottomLeftUrl,
    this.bottomRightUrl,
  });

  ActivationState copyWith({
    bool? isActivated,
    bool? isLoading,
    String? deviceCode,
    String? screenId,
    String? companyId,
    String? orientation,
    int? syncInterval,
    String? layout,
    String? sidebarUrl,
    String? centerUrl,
    String? rightUrl,
    String? topRightUrl,
    String? bottomLeftUrl,
    String? bottomRightUrl,
  }) {
    return ActivationState(
      isActivated: isActivated ?? this.isActivated,
      isLoading: isLoading ?? this.isLoading,
      deviceCode: deviceCode ?? this.deviceCode,
      screenId: screenId ?? this.screenId,
      companyId: companyId ?? this.companyId,
      orientation: orientation ?? this.orientation,
      syncInterval: syncInterval ?? this.syncInterval,
      layout: layout ?? this.layout,
      sidebarUrl: sidebarUrl ?? this.sidebarUrl,
      centerUrl: centerUrl ?? this.centerUrl,
      rightUrl: rightUrl ?? this.rightUrl,
      topRightUrl: topRightUrl ?? this.topRightUrl,
      bottomLeftUrl: bottomLeftUrl ?? this.bottomLeftUrl,
      bottomRightUrl: bottomRightUrl ?? this.bottomRightUrl,
    );
  }
}

class ActivationNotifier extends StateNotifier<ActivationState> {
  ActivationNotifier()
      : super(const ActivationState(
          isActivated: false,
          isLoading: true,
          deviceCode: '------',
          screenId: '',
          companyId: '',
          orientation: 'landscape',
          syncInterval: 10,
          layout: 'fullscreen',
          sidebarUrl: null,
          centerUrl: null,
          rightUrl: null,
        )) {
    loadActivationFromPrefs();
  }

  String _normalizeLayout(String? raw) {
    final clean = raw?.trim().toLowerCase();
    if (clean == 'half') return 'half_split';
    if (clean == 'menu') return 'menu_board';
    if (clean == 'grid') return 'four_grid';
    if (clean == 'ticker' || clean == 'header' || clean == 'half_split' || clean == 'sidebar' || clean == 'triple' || clean == 'menu_board' || clean == 'four_grid') {
      return clean!;
    }
    return 'fullscreen';
  }

  /// Initial load from disk SharedPreferences
  Future<void> loadActivationFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final isActivated = prefs.getBool('is_activated') ?? false;
    final deviceCode = prefs.getString('activation_code') ?? '------';
    final screenId = prefs.getString('screen_id') ?? '';
    final companyId = prefs.getString('company_id') ?? '';
    final orientation = prefs.getString('orientation') ?? 'landscape';
    final syncIntervalStr = prefs.getString('sync_interval') ?? '10';
    final syncInterval = int.tryParse(syncIntervalStr) ?? 10;
    final layout = _normalizeLayout(prefs.getString('screen_layout'));
    final sidebarUrl = prefs.getString('sidebar_url');
    final centerUrl = prefs.getString('center_url');
    final rightUrl = prefs.getString('right_url');
    final topRightUrl = prefs.getString('top_right_url');
    final bottomLeftUrl = prefs.getString('bottom_left_url');
    final bottomRightUrl = prefs.getString('bottom_right_url');

    state = ActivationState(
      isActivated: isActivated && deviceCode != '------' && screenId.isNotEmpty,
      isLoading: false,
      deviceCode: deviceCode,
      screenId: screenId,
      companyId: companyId,
      orientation: orientation,
      syncInterval: syncInterval,
      layout: layout,
      sidebarUrl: sidebarUrl,
      centerUrl: centerUrl,
      rightUrl: rightUrl,
      topRightUrl: topRightUrl,
      bottomLeftUrl: bottomLeftUrl,
      bottomRightUrl: bottomRightUrl,
    );
  }

  /// Registers server authorization details
  Future<void> activateDevice({
    required String screenId,
    required String companyId,
    required String orientation,
    required int syncInterval,
    String? layout,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final oldScreenId = prefs.getString('screen_id');

    // Wipe cached playlists and local files if the screen ID changes to avoid stale bleed
    if (oldScreenId != screenId) {
      await prefs.remove('playlist_version');
      await DatabaseHelper.instance.clearPlaylist();
      await FileManager.instance.clearAllCachedMedia();
      VideoPreloadManager.instance.clearAll();
    }

    final cleanLayout = _normalizeLayout(layout);

    await prefs.setBool('is_activated', true);
    await prefs.setString('screen_id', screenId);
    await prefs.setString('company_id', companyId);
    await prefs.setString('orientation', orientation);
    await prefs.setString('sync_interval', syncInterval.toString());
    await prefs.setString('screen_layout', cleanLayout);

    state = state.copyWith(
      isActivated: true,
      screenId: screenId,
      companyId: companyId,
      orientation: orientation,
      syncInterval: syncInterval,
      layout: cleanLayout,
      isLoading: false, // Ensure loading is false on activation
    );
  }

  /// Update layout orientation dynamically from central CMS sync pings
  Future<void> updateOrientation(String newOrientation) async {
    if (state.orientation == newOrientation) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('orientation', newOrientation);
    state = state.copyWith(orientation: newOrientation);
  }

  /// Update screen layout dynamically from central CMS sync pings
  Future<void> updateLayout(String newLayout, {
    String? sidebarUrl, 
    String? centerUrl, 
    String? rightUrl,
    String? topRightUrl,
    String? bottomLeftUrl,
    String? bottomRightUrl,
  }) async {
    final cleanLayout = _normalizeLayout(newLayout);
    if (state.layout == cleanLayout && 
        state.sidebarUrl == sidebarUrl && 
        state.centerUrl == centerUrl && 
        state.rightUrl == rightUrl &&
        state.topRightUrl == topRightUrl &&
        state.bottomLeftUrl == bottomLeftUrl &&
        state.bottomRightUrl == bottomRightUrl) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('screen_layout', cleanLayout);
    
    if (sidebarUrl != null) await prefs.setString('sidebar_url', sidebarUrl); else await prefs.remove('sidebar_url');
    if (centerUrl != null) await prefs.setString('center_url', centerUrl); else await prefs.remove('center_url');
    if (rightUrl != null) await prefs.setString('right_url', rightUrl); else await prefs.remove('right_url');
    if (topRightUrl != null) await prefs.setString('top_right_url', topRightUrl); else await prefs.remove('top_right_url');
    if (bottomLeftUrl != null) await prefs.setString('bottom_left_url', bottomLeftUrl); else await prefs.remove('bottom_left_url');
    if (bottomRightUrl != null) await prefs.setString('bottom_right_url', bottomRightUrl); else await prefs.remove('bottom_right_url');

    state = state.copyWith(
      layout: cleanLayout, 
      sidebarUrl: sidebarUrl, 
      centerUrl: centerUrl, 
      rightUrl: rightUrl,
      topRightUrl: topRightUrl,
      bottomLeftUrl: bottomLeftUrl,
      bottomRightUrl: bottomRightUrl,
    );
  }

  /// Refreshes the activation details from the server using the saved device/pairing code.
  Future<bool> refreshActivationDetails() async {
    if (state.deviceCode == '------' || state.deviceCode.isEmpty) return false;
    if (kIsWeb) return true;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return true;
    }

    try {
      final url = Uri.parse('https://cms.thelocads.com/api/player/login');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'device_id': state.deviceCode}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['status'] == 'authorized') {
          final screenId = data['screen_id']?.toString() ?? '';
          final companyId = data['company_id']?.toString() ?? '';
          final orientation = data['orientation']?.toString() ?? 'landscape';
          final syncIntervalStr = data['sync_interval']?.toString() ?? '10';
          final syncInterval = int.tryParse(syncIntervalStr) ?? 10;
          final layout = _normalizeLayout(data['layout_type']?.toString() ?? data['layout']?.toString());

          await activateDevice(
            screenId: screenId,
            companyId: companyId,
            orientation: orientation,
            syncInterval: syncInterval,
            layout: layout,
          );
          return true;
        } else {
          print('Device status is not authorized: ${data['status']}. Deactivating screen.');
          await _deactivateDevice();
          return false;
        }
      } else if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404 || response.statusCode == 422) {
        print('Login API returned error status: ${response.statusCode}. Deactivating screen.');
        await _deactivateDevice();
        return false;
      }
    } catch (e) {
      print('Failed to refresh activation details: $e');
    }
    return false;
  }

  Future<void> _deactivateDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_activated', false);
    await prefs.remove('screen_layout');
    
    // Wipe cached playlists and local files
    await DatabaseHelper.instance.clearPlaylist();
    await FileManager.instance.clearAllCachedMedia();

    // Clear preloaded video controllers
    VideoPreloadManager.instance.clearAll();

    state = state.copyWith(
      isActivated: false,
      screenId: '',
      companyId: '',
      layout: 'fullscreen',
    );
  }

  /// Disconnects screen link, wipes SharedPreferences database, and returns to ActivationScreen
  Future<void> disconnect() async {
    state = state.copyWith(isLoading: true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_activated');
    await prefs.remove('activation_code');
    await prefs.remove('screen_id');
    await prefs.remove('company_id');
    await prefs.remove('orientation');
    await prefs.remove('sync_interval');
    await prefs.remove('screen_layout');
    await prefs.remove('top_right_url');
    await prefs.remove('bottom_left_url');
    await prefs.remove('bottom_right_url');

    // Wipe cached playlists and local files
    await DatabaseHelper.instance.clearPlaylist();
    await FileManager.instance.clearAllCachedMedia();

    // Clear preloaded video controllers
    VideoPreloadManager.instance.clearAll();

    state = ActivationState(
      isActivated: false,
      deviceCode: '------',
      screenId: '',
      companyId: '',
      orientation: 'landscape',
      syncInterval: 10,
      layout: 'fullscreen',
      isLoading: false,
    );
  }
}

final activationProvider = StateNotifierProvider<ActivationNotifier, ActivationState>((ref) {
  return ActivationNotifier();
});

// --- Playlist Playback State Model & Notifier ---

class PlaylistState {
  final List<MediaItem> items;
  final int currentIndex;
  final bool isLoading;
  final String? errorMessage;
  final bool hasInitialized;
  final bool isOnline;
  final double downloadProgress;

  PlaylistState({
    required this.items,
    this.currentIndex = 0,
    this.isLoading = false,
    this.errorMessage,
    this.hasInitialized = false,
    this.isOnline = true,
    this.downloadProgress = 0.0,
  });

  PlaylistState copyWith({
    List<MediaItem>? items,
    int? currentIndex,
    bool? isLoading,
    String? errorMessage,
    bool? hasInitialized,
    bool? isOnline,
    double? downloadProgress,
  }) {
    return PlaylistState(
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      hasInitialized: hasInitialized ?? this.hasInitialized,
      isOnline: isOnline ?? this.isOnline,
      downloadProgress: downloadProgress ?? this.downloadProgress,
    );
  }
}

class PlaylistNotifier extends StateNotifier<PlaylistState> {
  bool _isDownloading = false;
  final Set<int> _failedDownloads = {};
  final Map<int, double> _downloadProgresses = {};

  PlaylistNotifier() : super(PlaylistState(items: [], hasInitialized: false, isOnline: true)) {
    loadCachedPlaylist().then((_) {
      if (kIsWeb && state.items.isEmpty) {
        final now = DateTime.now();
        final mockItems = [
          MediaItem(
            id: 991,
            url: 'https://cms.thelocads.com/assets/images/logo.png',
            type: 'image',
            duration: 10,
            order: 1,
            schedule: ScheduleConfig(
              startDatetime: now.subtract(const Duration(minutes: 5)),
              endDatetime: now.add(const Duration(seconds: 15)), // Expire in 15 seconds
              type: 'broadcast',
              priority: 1,
            ),
          ),
          MediaItem(
            id: 992,
            url: 'https://cms.thelocads.com/assets/images/logo.png',
            type: 'image',
            duration: 10,
            order: 2,
            schedule: ScheduleConfig(
              startDatetime: now.subtract(const Duration(minutes: 5)),
              endDatetime: now.subtract(const Duration(seconds: 5)), // Already expired
              type: 'broadcast',
              priority: 1,
            ),
          ),
        ];
        updatePlaylist(mockItems);
      }
    });
    _checkInitialConnectivity();
  }

  Future<void> _checkInitialConnectivity() async {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      state = state.copyWith(isOnline: true);
      return;
    }
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      if (!mounted) return;
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      state = state.copyWith(isOnline: online);
      if (!online) {
        // Fallback: immediately play cached files on startup only if there is no internet
        markInitialized();
      }
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isOnline: false);
      // Fallback: immediately play cached files on startup only if there is no internet
      markInitialized();
    }
  }

  /// Sets whether the app is currently online or offline.
  void setOnlineStatus(bool online) {
    if (state.isOnline != online) {
      state = state.copyWith(isOnline: online);
      // Re-evaluate current index based on new connectivity status, preserving if still valid
      final now = DateTime.now();
      if (state.items.isNotEmpty && state.currentIndex >= 0 && state.currentIndex < state.items.length) {
        final currentItem = state.items[state.currentIndex];
        if (currentItem.isValidNow(now, isOnline: online)) {
          _preloadNextItem();
          return;
        }
      }
      final validIdx = _findFirstValidIndex(state.items);
      state = state.copyWith(currentIndex: validIdx);
      _preloadNextItem();
    }
  }

  /// Programmatically sets the active playlist item index.
  void setCurrentIndex(int index) {
    if (index >= 0 && index < state.items.length) {
      state = state.copyWith(currentIndex: index);
      _preloadNextItem();
    }
  }

  /// Load cached items from DB on startup
  Future<void> loadCachedPlaylist() async {
    state = state.copyWith(isLoading: true);
    try {
      final items = await DatabaseHelper.instance.getPlaylist();
      state = PlaylistState(
        items: items,
        currentIndex: _findFirstValidIndex(items),
        isLoading: false,
        hasInitialized: state.hasInitialized, // Preserve initialized state from connectivity checks
        isOnline: state.isOnline,
        downloadProgress: state.downloadProgress,
      );

      if (items.isNotEmpty) {
        _logPlaylist(items);
        // Resolve orientations in the background and update state when done
        _resolveOrientations(items).then((resolved) {
          state = state.copyWith(items: resolved);
          _preloadNextItem();

          // Verify and download any missing media files sequentially
          _startBackgroundDownload(resolved);
        });
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load cached playlist: $e',
      );
    }
  }

  /// Mark that initial sync/check has completed
  void markInitialized() {
    if (!state.hasInitialized) {
      state = state.copyWith(hasInitialized: true);
    }
  }

  /// Clears local path of a corrupt item, saves to DB, deletes physical file, and restarts background downloader to heal it
  Future<void> handleCorruptVideo(int itemId) async {
    // 1. Delete corrupt file physically from disk
    final match = state.items.where((it) => it.id == itemId).toList();
    if (match.isNotEmpty) {
      final item = match.first;
      if (item.localPath != null && !kIsWeb) {
        try {
          final file = File(item.localPath!);
          if (file.existsSync()) {
            file.deleteSync();
            print('[PlaylistNotifier] Deleted corrupt video file at: ${item.localPath}');
          }
        } catch (e) {
          print('[PlaylistNotifier] Failed to delete corrupt video file physically: $e');
        }
      }
    }

    // 2. Clear localPath in memory state
    final updatedItems = state.items.map((it) {
      if (it.id == itemId) {
        return it.copyWith(localPath: null);
      }
      return it;
    }).toList();

    state = state.copyWith(items: updatedItems);

    // 3. Clear localPath in SQLite database
    await DatabaseHelper.instance.updateLocalPath(itemId, null);

    // 4. Restart sequential background downloader session to heal the item
    _startBackgroundDownload(updatedItems);
  }

  /// Replaces the playlist schedule with new server schema, caches media files,
  /// and updates SQLite database.
  Future<void> updatePlaylist(List<MediaItem> newItems) async {
    state = state.copyWith(isLoading: true);
    try {
      // 1. Retrieve existing local cache mappings from current database items
      final oldItems = await DatabaseHelper.instance.getPlaylist();

      // Map the local cache paths back into our new media list, ensuring both ID and URL match to avoid stale bleed
      final List<MediaItem> itemsToUse = newItems.map((item) {
        final matches = oldItems.where((o) => o.id == item.id && o.url == item.url).toList();
        if (matches.isNotEmpty) {
          final matchingOldItem = matches.first;
          if (matchingOldItem.localPath != null &&
              (kIsWeb || File(matchingOldItem.localPath!).existsSync())) {
            return item.copyWith(localPath: matchingOldItem.localPath);
          }
        }
        return item;
      }).toList();

      // 2. Save items to Database immediately so database is consistent with UI state
      await DatabaseHelper.instance.savePlaylist(itemsToUse);

      // Pre-resolve orientations in background before updating UI state
      final resolvedItems = await _resolveOrientations(itemsToUse);

      // Determine the next index to use, preserving the currently playing item if possible
      int targetIndex = 0;
      if (state.items.isNotEmpty && state.currentIndex >= 0 && state.currentIndex < state.items.length) {
        final currentItem = state.items[state.currentIndex];
        final matchIdx = resolvedItems.indexWhere((it) => it.id == currentItem.id && it.url == currentItem.url);
        if (matchIdx != -1) {
          targetIndex = matchIdx;
        } else {
          targetIndex = _findFirstValidIndex(resolvedItems);
        }
      } else {
        targetIndex = _findFirstValidIndex(resolvedItems);
      }

      // 3. Update memory state immediately to allow direct, immediate playout!
      state = PlaylistState(
        items: resolvedItems,
        currentIndex: targetIndex,
        isLoading: false,
        hasInitialized: true,
        isOnline: state.isOnline,
        downloadProgress: 0.0,
      );
      _logPlaylist(resolvedItems);
      _preloadNextItem();

      // 4. Start sequential background downloader prioritising the active item
      _startBackgroundDownload(resolvedItems);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to update playlist: $e',
      );
    }
  }

  /// Asynchronously downloads missing media items sequentially in the background.
  Future<void> _startBackgroundDownload(List<MediaItem> items) async {
    // Update progress tracker keys based on currently uncached items
    final itemsToDownload = items.where((item) => !item.isLocallyAvailable()).toList();
    _downloadProgresses.removeWhere((id, _) => !itemsToDownload.any((it) => it.id == id));
    for (var item in itemsToDownload) {
      _downloadProgresses.putIfAbsent(item.id, () => 0.0);
    }

    if (_isDownloading) {
      return; // A loop is already running and will automatically pick up updated state.items
    }

    _isDownloading = true;

    try {
      if (kIsWeb) {
        state = state.copyWith(downloadProgress: 0.01);
        while (mounted) {
          final pending = state.items
              .where((item) => !item.isLocallyAvailable() && !_failedDownloads.contains(item.id))
              .toList();
          if (pending.isEmpty) break;

          final item = pending.first;
          for (int p = 10; p <= 100; p += 10) {
            await Future.delayed(const Duration(milliseconds: 100));
            if (!mounted) return;
            if (!state.items.any((it) => it.id == item.id)) break;

            _downloadProgresses[item.id] = p / 100.0;
            final total = _downloadProgresses.length;
            if (total > 0) {
              final sum = _downloadProgresses.values.fold(0.0, (a, b) => a + b);
              state = state.copyWith(downloadProgress: sum / total);
            }
          }

          if (!mounted) return;
          if (state.items.any((it) => it.id == item.id)) {
            final updatedItems = state.items.map((it) {
              if (it.id == item.id) {
                return it.copyWith(localPath: 'web_cached_${it.id}');
              }
              return it;
            }).toList();
            state = state.copyWith(items: updatedItems);
            _preloadNextItem();
          }
        }
        if (mounted) {
          state = state.copyWith(downloadProgress: 0.0);
        }
        return;
      }

      // Initialize progress state
      state = state.copyWith(downloadProgress: 0.01);

      while (mounted) {
        final pending = state.items
            .where((item) => !item.isLocallyAvailable() && !_failedDownloads.contains(item.id))
            .toList();
        if (pending.isEmpty) break;

        final item = pending.first;

        final localPath = await FileManager.instance.downloadFile(
          item.url,
          item.id,
          itemType: item.type,
          onProgress: (progress) {
            if (!mounted) return;
            if (!state.items.any((it) => it.id == item.id)) return;

            _downloadProgresses[item.id] = progress;
            final total = _downloadProgresses.length;
            if (total > 0) {
              final sum = _downloadProgresses.values.fold(0.0, (a, b) => a + b);
              state = state.copyWith(downloadProgress: sum / total);
            }
          },
          isCancelled: () => !mounted || !state.items.any((it) => it.id == item.id),
        );

        if (!mounted) return;

        // Verify that the item was not removed from the active playlist during download
        if (!state.items.any((it) => it.id == item.id)) {
          continue;
        }

        if (localPath != null) {
          // Map downloaded local path to items in the memory state
          final updatedItems = state.items.map((it) {
            if (it.id == item.id) {
              return it.copyWith(localPath: localPath);
            }
            return it;
          }).toList();

          // Persist local path mapping in SQLite
          await DatabaseHelper.instance.savePlaylist(updatedItems);

          if (!mounted) return;
          state = state.copyWith(items: updatedItems);
          _preloadNextItem();
        } else {
          // Failed to download: add to failed downloads list to avoid looping endlessly
          _failedDownloads.add(item.id);
        }
      }

      // Clean up orphaned cache files once everything is fully cached
      if (mounted) {
        state = state.copyWith(downloadProgress: 0.0);
        await FileManager.instance.cleanUnusedFiles(state.items);
      }
    } finally {
      _isDownloading = false;
      _downloadProgresses.clear();
    }
  }

  bool _hasAnyValidScheduledItem(List<MediaItem> list, DateTime now, {required bool isOnline}) {
    final scheduledItems = list.where((item) => item.schedule != null);
    if (scheduledItems.isEmpty) {
      return list.any((item) => item.isValidNow(now, isOnline: isOnline, ignoreSchedule: false));
    }
    return scheduledItems.any((item) => item.isValidNow(now, isOnline: isOnline, ignoreSchedule: false));
  }

  /// Increments sequence pointer to select the next valid scheduled item.
  void nextItem() {
    if (state.items.isEmpty) return;

    final startIdx = state.currentIndex;
    int nextIdx = (startIdx + 1) % state.items.length;
    final now = DateTime.now();
    final ignoreSchedule = !_hasAnyValidScheduledItem(state.items, now, isOnline: state.isOnline);

    // Loop through checklist to find the next active item
    while (nextIdx != startIdx) {
      if (state.items[nextIdx].isValidNow(now, isOnline: state.isOnline, ignoreSchedule: ignoreSchedule)) {
        state = state.copyWith(currentIndex: nextIdx);
        _preloadNextItem();
        return;
      }
      nextIdx = (nextIdx + 1) % state.items.length;
    }

    // Check if startIdx itself is valid
    if (state.items[startIdx].isValidNow(now, isOnline: state.isOnline, ignoreSchedule: ignoreSchedule)) {
      return;
    }
  }

  /// Helper to locate first valid index according to scheduling rules
  int _findFirstValidIndex(List<MediaItem> list) {
    if (list.isEmpty) return 0;
    final now = DateTime.now();
    final ignoreSchedule = !_hasAnyValidScheduledItem(list, now, isOnline: state.isOnline);
    for (int i = 0; i < list.length; i++) {
      if (list[i].isValidNow(now, isOnline: state.isOnline, ignoreSchedule: ignoreSchedule)) {
        return i;
      }
    }
    return 0;
  }

  /// Pre-resolves the orientation (landscape/portrait) for all items in the playlist.
  Future<List<MediaItem>> _resolveOrientations(List<MediaItem> items) async {
    // Return items directly. Resolving orientation of all media items by initializing
    // network players/downloading image streams is extremely expensive and causes
    // severe network stuttering/pauses during video playback.
    return items;
  }

  /// Finds the next valid index starting after the current index.
  int getNextValidIndex() {
    if (state.items.isEmpty) return -1;
    final startIdx = state.currentIndex;
    int nextIdx = (startIdx + 1) % state.items.length;
    final now = DateTime.now();
    final ignoreSchedule = !_hasAnyValidScheduledItem(state.items, now, isOnline: state.isOnline);

    while (nextIdx != startIdx) {
      if (state.items[nextIdx].isValidNow(now, isOnline: state.isOnline, ignoreSchedule: ignoreSchedule)) {
        return nextIdx;
      }
      nextIdx = (nextIdx + 1) % state.items.length;
    }
    
    // Check if startIdx itself is valid when wrapping around
    if (state.items[startIdx].isValidNow(now, isOnline: state.isOnline, ignoreSchedule: ignoreSchedule)) {
      return startIdx;
    }
    return -1;
  }

  /// Triggers background preloading for the next video item.
  void _preloadNextItem() {
    final nextIdx = getNextValidIndex();
    if (nextIdx != -1) {
      final nextItem = state.items[nextIdx];
      if (nextItem.type == 'video') {
        VideoPreloadManager.instance.preload(nextItem).then((success) {
          if (!success && mounted) {
            handleCorruptVideo(nextItem.id);
          }
        });
      }
      // Keep only the current item and the next item controllers
      final currentItem = state.items[state.currentIndex];
      VideoPreloadManager.instance.keepOnly([currentItem.id, nextItem.id]);
    }
  }

  /// Logs all items in the playlist with their scheduling and cached state.
  void _logPlaylist(List<MediaItem> items) {
    print('[PlaylistNotifier] --- Active Playlist Items Check ---');
    final now = DateTime.now();
    for (var item in items) {
      final isCached = item.isLocallyAvailable();
      final isValid = item.isValidNow(now, isOnline: state.isOnline);
      print('  ID: ${item.id} | Type: ${item.type} | Cached: $isCached | ValidNow: $isValid | URL: ${item.url}');
      if (item.schedule != null) {
        print('    Schedule: Type: ${item.schedule!.type} | Start: ${item.schedule!.startDatetime} | End: ${item.schedule!.endDatetime} | Days: ${item.schedule!.daysOfWeek}');
      } else {
        print('    Schedule: Persistent (Runs fallback forever)');
      }
    }
    print('[PlaylistNotifier] -------------------------------------');
  }
}

final playlistProvider = StateNotifierProvider<PlaylistNotifier, PlaylistState>((ref) {
  return PlaylistNotifier();
});

class TickersNotifier extends StateNotifier<List<TickerItem>> {
  TickersNotifier() : super([]) {
    loadTickersFromPrefs();
  }

  Future<void> loadTickersFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cached_tickers_json');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          state = decoded.map((item) => TickerItem.fromJson(item as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      print('Failed to load cached tickers: $e');
    }
  }

  Future<void> updateTickers(List<TickerItem> newTickers) async {
    state = newTickers;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(newTickers.map((item) => item.toJson()).toList());
      await prefs.setString('cached_tickers_json', jsonStr);
    } catch (e) {
      print('Failed to save tickers to prefs: $e');
    }
  }
}

final tickersProvider = StateNotifierProvider<TickersNotifier, List<TickerItem>>((ref) {
  return TickersNotifier();
});
