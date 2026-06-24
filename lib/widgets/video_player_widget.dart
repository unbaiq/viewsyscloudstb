import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
import '../providers/player_provider.dart';
import '../services/video_preload_manager.dart';

/// Tracks the number of actively rendering video widgets on screen
class ActiveVideoCountNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
  void decrement() => state--;
}

final activeVideoCountProvider = NotifierProvider<ActiveVideoCountNotifier, int>(() {
  return ActiveVideoCountNotifier();
});

/// A wrapper widget to manage the lifecycle of a video controller safely.
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
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  Timer? _fallbackTimer;
  bool _notifiedReady = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(activeVideoCountProvider.notifier).increment();
      }
    });
    _initVideo();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateLoopingState();
  }

  @override
  void dispose() {
    Future.microtask(() {
      try {
        ref.read(activeVideoCountProvider.notifier).decrement();
      } catch (_) {}
    });
    _fallbackTimer?.cancel();
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  void _updateLoopingState() {
    if (_controller == null || !_initialized) return;
    
    if (widget.forceLoop) {
      if (!_controller!.value.isLooping) {
        _controller!.setLooping(true);
        print('[VideoPlayerWidget] Dynamic looping updated to: true (forceLoop)');
      }
      return;
    }

    final playlistState = ref.read(playlistProvider);
    final items = playlistState.items;
    final now = DateTime.now();
    final validCount = items.where((item) => item.isValidNow(now, isOnline: playlistState.isOnline)).length;
    final shouldLoop = validCount <= 1;
    if (_controller!.value.isLooping != shouldLoop) {
      _controller!.setLooping(shouldLoop);
      print('[VideoPlayerWidget] Dynamic looping updated to: $shouldLoop');
    }
  }

  Future<void> _initVideo() async {
    try {
      final preloaded = VideoPreloadManager.instance.getAndRemove(widget.item.id);

      if (preloaded != null) {
        _controller = preloaded;
        _controller!.addListener(_videoListener);

        if (mounted) {
          setState(() {
            _initialized = _controller!.value.isInitialized;
          });

          if (!_controller!.value.isInitialized) {
            await _controller!.initialize();
            if (mounted) {
              setState(() {
                _initialized = true;
              });
            }
          }

          _updateLoopingState();
          _controller!.play();
        }
      } else {
        final fileExists = widget.item.localPath != null &&
            widget.item.localPath!.isNotEmpty &&
            !kIsWeb &&
            File(widget.item.localPath!).existsSync() &&
            File(widget.item.localPath!).lengthSync() > 0;

        final playlistState = ref.read(playlistProvider);

        if (!fileExists && !kIsWeb) {
          if (!playlistState.isOnline) {
            if (mounted) {
              setState(() {
                _hasError = true;
              });
            }
            return;
          }

          print('[VideoPlayerWidget] File not cached yet. Streaming from network: ${widget.item.url}');
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(widget.item.url),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          );
        } else {
          if (kIsWeb) {
            _controller = VideoPlayerController.networkUrl(
              Uri.parse(widget.item.url),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );
          } else {
            _controller = VideoPlayerController.file(
              File(widget.item.localPath!),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );
          }
        }

        _controller!.addListener(_videoListener);
        await _controller!.initialize();

        if (mounted) {
          setState(() {
            _initialized = true;
          });

          _updateLoopingState();
          _controller!.play();
        }
      }
    } catch (e) {
      print('Video controller initialization failure: $e');
      ref.read(playlistProvider.notifier).handleCorruptVideo(widget.item.id);

      if (mounted) {
        setState(() {
          _hasError = true;
        });
        // Sched fallback to automatically advance in 4 seconds if initialization fails
        _fallbackTimer = Timer(const Duration(seconds: 4), () {
          widget.onComplete();
        });
      }
    }
  }

  void _videoListener() {
    if (_controller == null || !mounted) return;

    if (_controller!.value.hasError) {
      print('Video playback error: ${_controller!.value.errorDescription}');
      ref.read(playlistProvider.notifier).handleCorruptVideo(widget.item.id);

      _controller!.removeListener(_videoListener);
      widget.onComplete();
      return;
    }

    // Trigger parent ready callback only after video starts rendering/playing frames
    if (!_notifiedReady &&
        _controller!.value.isInitialized &&
        _controller!.value.isPlaying &&
        _controller!.value.position.inMilliseconds > 0) {
      _notifiedReady = true;
      widget.onInitialized?.call();
    }

    // Advance index once video playout finishes (only if it is not looping)
    if (!_controller!.value.isLooping &&
        _controller!.value.isInitialized &&
        _controller!.value.isCompleted) {
      _controller!.removeListener(_videoListener);
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic audio muting: if more than 1 video is rendering, mute all.
    ref.listen<int>(activeVideoCountProvider, (previous, next) {
      if (_controller != null && _controller!.value.isInitialized) {
        final shouldMute = next > 1;
        if ((_controller!.value.volume == 0.0) != shouldMute) {
          _controller!.setVolume(shouldMute ? 0.0 : 1.0);
          print('[VideoPlayerWidget] Mute state updated: $shouldMute (Active videos: $next)');
        }
      }
    });

    final activeVideoCount = ref.watch(activeVideoCountProvider);
    final isMuted = activeVideoCount > 1;
    
    if (_controller != null && _controller!.value.isInitialized && (_controller!.value.volume == 0.0) != isMuted) {
      _controller!.setVolume(isMuted ? 0.0 : 1.0);
    }

    if (_hasError) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_off_rounded, color: Colors.redAccent, size: 40),
              SizedBox(height: 12),
              Text('Video playout failed',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    if (!_initialized) {
      return const SizedBox.shrink();
    }

    // FittedBox correctly fills any rotated space while preserving aspect ratio.
    // LayoutBuilder forces the widget tree to respond live to constraints/orientation changes.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        );
      },
    );
  }
}
