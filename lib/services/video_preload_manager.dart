import 'dart:async';
import '../models/media_item.dart';

class VideoPreloadManager {
  VideoPreloadManager._();
  static final VideoPreloadManager instance = VideoPreloadManager._();

  Future<bool> preload(MediaItem item) async {
    return true; // Native ExoPlayer handles its own caching natively.
  }

  dynamic getAndRemove(int itemId) {
    return null;
  }

  void keepOnly(List<int> itemIdsToKeep) {}
  void clearAll() {}
}
