import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui' as ui;

import '../models/media_item.dart';
import '../providers/player_provider.dart';
import 'native_video_player.dart';

/// Tracks the number of actively rendering video widgets on screen
class ActiveVideoCountNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
  void decrement() => state--;
}

final activeVideoCountProvider =
    NotifierProvider<ActiveVideoCountNotifier, int>(() {
      return ActiveVideoCountNotifier();
    });

/// A wrapper widget to manage the lifecycle of a native video controller safely.
class VideoPlayerWidget extends ConsumerStatefulWidget {
  final MediaItem item;
  final VoidCallback onComplete;
  final VoidCallback? onInitialized;
  final bool forceLoop;

  const VideoPlayerWidget({
    super.key,
    required this.item,
    required this.onComplete,
    this.onInitialized,
    this.forceLoop = false,
  });

  @override
  ConsumerState<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends ConsumerState<VideoPlayerWidget> {
  bool _notifiedReady = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(activeVideoCountProvider.notifier).increment();
      }
    });
  }

  @override
  void dispose() {
    Future.microtask(() {
      try {
        ref.read(activeVideoCountProvider.notifier).decrement();
      } catch (_) {}
    });
    super.dispose();
  }

  bool _shouldLoop() {
    if (widget.forceLoop) return true;
    final playlistState = ref.read(playlistProvider);
    final items = playlistState.items;
    final now = DateTime.now();
    final validCount = items
        .where((item) => item.isValidNow(now, isOnline: playlistState.isOnline))
        .length;
    return validCount <= 1;
  }

  @override
  Widget build(BuildContext context) {
    final activeVideoCount = ref.watch(activeVideoCountProvider);
    final layout = ref.watch(activationProvider).layout;
    final singleZoneLayouts = const ['fullscreen', 'ticker', 'header'];
    final isMuted = singleZoneLayouts.contains(layout) ? false : activeVideoCount > 1;

    final fileExists = widget.item.localPath != null &&
        widget.item.localPath!.isNotEmpty &&
        File(widget.item.localPath!).existsSync() &&
        File(widget.item.localPath!).lengthSync() > 0;

    return NativeVideoPlayer(
      key: ValueKey('native_${widget.item.id}'),
      url: fileExists ? widget.item.localPath! : widget.item.url,
      loop: _shouldLoop(),
      muted: isMuted,
      volume: 1.0,
      onReady: () {
        if (!_notifiedReady) {
          widget.onInitialized?.call();
          _notifiedReady = true;
        }
      },
      onComplete: () {
        widget.onComplete();
      },
      onError: (error) {
        print('Native player error: $error');
        final playlistState = ref.read(playlistProvider);
        if (playlistState.items.any((item) => item.id == widget.item.id)) {
          ref.read(playlistProvider.notifier).handleCorruptVideo(widget.item.id);
        }
        widget.onComplete();
      },
    );
  }
}

// Kept empty to satisfy screenshot_service.dart dependencies without breaking it
class VideoFrameRegistry {
  VideoFrameRegistry._();
  static final VideoFrameRegistry instance = VideoFrameRegistry._();
  
  void register(int itemId, GlobalKey key) {}
  void unregister(int itemId) {}
  GlobalKey? keyFor(int itemId) => null;
  
  Future<Map<int, ui.Image>> captureAllFrames() async {
    return {};
  }
}
