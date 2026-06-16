import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import '../services/database_helper.dart';
import '../services/file_manager.dart';
import '../services/video_preload_manager.dart';

// --- Activation State Model & Notifier ---

class ActivationState {
  final bool isActivated;
  final String deviceCode;
  final String screenId;
  final String companyId;
  final String orientation;
  final int syncInterval;
  final bool isLoading;

  ActivationState({
    required this.isActivated,
    required this.deviceCode,
    required this.screenId,
    required this.companyId,
    required this.orientation,
    required this.syncInterval,
    this.isLoading = false,
  });

  ActivationState copyWith({
    bool? isActivated,
    String? deviceCode,
    String? screenId,
    String? companyId,
    String? orientation,
    int? syncInterval,
    bool? isLoading,
  }) {
    return ActivationState(
      isActivated: isActivated ?? this.isActivated,
      deviceCode: deviceCode ?? this.deviceCode,
      screenId: screenId ?? this.screenId,
      companyId: companyId ?? this.companyId,
      orientation: orientation ?? this.orientation,
      syncInterval: syncInterval ?? this.syncInterval,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ActivationNotifier extends StateNotifier<ActivationState> {
  ActivationNotifier()
      : super(ActivationState(
          isActivated: false,
          deviceCode: '------',
          screenId: '',
          companyId: '',
          orientation: 'landscape',
          syncInterval: 10,
          isLoading: true, // Initial loading is true
        )) {
    loadActivationFromPrefs();
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

    state = ActivationState(
      isActivated: isActivated && deviceCode != '------' && screenId.isNotEmpty,
      deviceCode: deviceCode,
      screenId: screenId,
      companyId: companyId,
      orientation: orientation,
      syncInterval: syncInterval,
      isLoading: false, // Finished loading
    );
  }

  /// Registers server authorization details
  Future<void> activateDevice({
    required String screenId,
    required String companyId,
    required String orientation,
    required int syncInterval,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_activated', true);
    await prefs.setString('screen_id', screenId);
    await prefs.setString('company_id', companyId);
    await prefs.setString('orientation', orientation);
    await prefs.setString('sync_interval', syncInterval.toString());

    state = state.copyWith(
      isActivated: true,
      screenId: screenId,
      companyId: companyId,
      orientation: orientation,
      syncInterval: syncInterval,
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

  /// Refreshes the activation details from the server using the saved device/pairing code.
  Future<bool> refreshActivationDetails() async {
    if (state.deviceCode == '------' || state.deviceCode.isEmpty) return false;
    if (kIsWeb) return true;

    try {
      final url = Uri.parse('https://viewsys.co.in/api/player/login');
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

          await activateDevice(
            screenId: screenId,
            companyId: companyId,
            orientation: orientation,
            syncInterval: syncInterval,
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
    
    // Wipe cached playlists and local files
    await DatabaseHelper.instance.clearPlaylist();
    await FileManager.instance.clearAllCachedMedia();

    // Clear preloaded video controllers
    VideoPreloadManager.instance.clearAll();

    state = state.copyWith(
      isActivated: false,
      screenId: '',
      companyId: '',
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
  int _currentDownloadSession = 0;

  PlaylistNotifier() : super(PlaylistState(items: [], hasInitialized: false, isOnline: true)) {
    loadCachedPlaylist().then((_) {
      if (kIsWeb && state.items.isEmpty) {
        final now = DateTime.now();
        final mockItems = [
          MediaItem(
            id: 991,
            url: 'https://viewsys.co.in/assets/images/logo.png',
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
            url: 'https://viewsys.co.in/assets/images/logo.png',
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
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      if (!mounted) return;
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      state = state.copyWith(isOnline: online);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isOnline: false);
    }
  }

  /// Sets whether the app is currently online or offline.
  void setOnlineStatus(bool online) {
    if (state.isOnline != online) {
      state = state.copyWith(isOnline: online);
      // Re-evaluate current index based on new connectivity status
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
        hasInitialized: items.isNotEmpty,
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
          _currentDownloadSession++;
          _startBackgroundDownload(resolved, _currentDownloadSession);
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

  /// Replaces the playlist schedule with new server schema, caches media files,
  /// and updates SQLite database.
  Future<void> updatePlaylist(List<MediaItem> newItems) async {
    state = state.copyWith(isLoading: true);
    try {
      // 1. Retrieve existing local cache mappings from current database items
      final oldItems = await DatabaseHelper.instance.getPlaylist();
      final Map<int, String?> localPathMap = {
        for (var item in oldItems)
          if (item.localPath != null && (kIsWeb || File(item.localPath!).existsSync()))
            item.id: item.localPath
      };

      // Map the local cache paths back into our new media list
      final List<MediaItem> itemsToUse = newItems.map((item) {
        if (localPathMap.containsKey(item.id)) {
          return item.copyWith(localPath: localPathMap[item.id]);
        }
        return item;
      }).toList();

      // 2. Save items to Database immediately so database is consistent with UI state
      await DatabaseHelper.instance.savePlaylist(itemsToUse);

      // Pre-resolve orientations in background before updating UI state
      final resolvedItems = await _resolveOrientations(itemsToUse);

      // 3. Update memory state immediately to allow direct, immediate playout!
      state = PlaylistState(
        items: resolvedItems,
        currentIndex: _findFirstValidIndex(resolvedItems),
        isLoading: false,
        hasInitialized: true,
        isOnline: state.isOnline,
        downloadProgress: 0.0,
      );
      _logPlaylist(resolvedItems);
      _preloadNextItem();

      // 4. Start sequential background downloader prioritising the active item
      _currentDownloadSession++;
      _startBackgroundDownload(resolvedItems, _currentDownloadSession);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to update playlist: $e',
      );
    }
  }

  /// Asynchronously downloads missing media items in parallel in the background.
  Future<void> _startBackgroundDownload(List<MediaItem> items, int session) async {
    if (items.isEmpty) return;

    final itemsToDownload = items.where((item) => !item.isLocallyAvailable()).toList();
    if (itemsToDownload.isEmpty) {
      if (session == _currentDownloadSession) {
        state = state.copyWith(downloadProgress: 0.0);
      }
      return;
    }

    final total = itemsToDownload.length;
    final Map<int, double> progresses = {for (var item in itemsToDownload) item.id: 0.0};

    void updateOverallProgress() {
      if (!mounted || session != _currentDownloadSession) return;
      final sum = progresses.values.fold(0.0, (a, b) => a + b);
      state = state.copyWith(downloadProgress: sum / total);
    }

    if (kIsWeb) {
      // Simulate parallel download progress on Web so the user can see it!
      state = state.copyWith(downloadProgress: 0.01);
      
      for (int p = 10; p <= 100; p += 10) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted || session != _currentDownloadSession) return;

        for (var item in itemsToDownload) {
          progresses[item.id] = p / 100.0;
        }
        updateOverallProgress();
      }

      if (!mounted || session != _currentDownloadSession) return;

      // Mark all items as cached locally in-memory for Web demo
      final updatedItems = state.items.map((it) {
        final matches = itemsToDownload.any((d) => d.id == it.id);
        if (matches) {
          return it.copyWith(localPath: 'web_cached_${it.id}');
        }
        return it;
      }).toList();

      state = state.copyWith(items: updatedItems, downloadProgress: 0.0);
      _preloadNextItem();
      return;
    }

    // Initialize progress state
    state = state.copyWith(downloadProgress: 0.01);

    // Start all downloads in parallel in background
    await Future.wait(
      itemsToDownload.map((item) async {
        if (!mounted || session != _currentDownloadSession) return;

        final localPath = await FileManager.instance.downloadFile(
          item.url,
          item.id,
          itemType: item.type,
          onProgress: (progress) {
            if (!mounted || session != _currentDownloadSession) return;
            progresses[item.id] = progress;
            updateOverallProgress();
          },
        );

        if (!mounted || session != _currentDownloadSession) return;

        if (localPath != null) {
          // Map downloaded local path to items
          final updatedItems = state.items.map((it) {
            if (it.id == item.id) {
              return it.copyWith(localPath: localPath);
            }
            return it;
          }).toList();

          // Persist local path mapping in SQLite
          await DatabaseHelper.instance.savePlaylist(updatedItems);

          // Update memory state to allow playout from disk
          if (!mounted || session != _currentDownloadSession) return;
          state = state.copyWith(items: updatedItems);
          _preloadNextItem();
        }
      }),
    );

    // Clean up orphaned cache files once everything is fully cached
    if (session == _currentDownloadSession) {
      state = state.copyWith(downloadProgress: 0.0);
      await FileManager.instance.cleanUnusedFiles(state.items);
    }
  }

  /// Increments sequence pointer to select the next valid scheduled item.
  void nextItem() {
    if (state.items.isEmpty) return;

    final startIdx = state.currentIndex;
    int nextIdx = (startIdx + 1) % state.items.length;
    final now = DateTime.now();

    // Loop through checklist to find the next active item
    while (nextIdx != startIdx) {
      if (state.items[nextIdx].isValidNow(now, isOnline: state.isOnline)) {
        state = state.copyWith(currentIndex: nextIdx);
        _preloadNextItem();
        return;
      }
      nextIdx = (nextIdx + 1) % state.items.length;
    }

    // Check if startIdx itself is valid
    if (state.items[startIdx].isValidNow(now, isOnline: state.isOnline)) {
      return;
    }
  }

  /// Helper to locate first valid index according to scheduling rules
  int _findFirstValidIndex(List<MediaItem> list) {
    if (list.isEmpty) return 0;
    final now = DateTime.now();
    for (int i = 0; i < list.length; i++) {
      if (list[i].isValidNow(now, isOnline: state.isOnline)) {
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

    while (nextIdx != startIdx) {
      if (state.items[nextIdx].isValidNow(now, isOnline: state.isOnline)) {
        return nextIdx;
      }
      nextIdx = (nextIdx + 1) % state.items.length;
    }
    
    // Check if startIdx itself is valid when wrapping around
    if (state.items[startIdx].isValidNow(now, isOnline: state.isOnline)) {
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
        VideoPreloadManager.instance.preload(nextItem);
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
