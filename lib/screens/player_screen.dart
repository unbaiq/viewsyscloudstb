import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../models/media_item.dart';
import '../providers/player_provider.dart';
import '../services/heartbeat_service.dart';
import '../services/sync_service.dart';
import '../services/screenshot_service.dart';
import '../activation_screen.dart';
import '../services/video_preload_manager.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  Timer? _imageTimer;
  Timer? _validityTimer;
  int? _scheduledItemId;

  // Seamless fade transition states
  int? _lastProcessedItemId;
  MediaItem? _prevItem;
  MediaItem? _currItem;
  bool _isCurrentItemReady = false;

  @override
  void initState() {
    super.initState();
    // Start background syncing and telemetry loops
    SyncService.instance.start(ref);
    HeartbeatService.instance.start(ref);

    _startValidityTimer();

    // Lock initial orientation after the first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _applyOrientation(ref.read(activationProvider).orientation);
      }
    });
  }

  void _startValidityTimer() {
    _validityTimer?.cancel();
    _validityTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final playlistState = ref.read(playlistProvider);
      if (playlistState.items.isEmpty) return;

      final now = DateTime.now();
      final currentItem = playlistState.items[playlistState.currentIndex];

      // Rebuild if the current item has expired/is no longer valid
      if (!currentItem.isValidNow(now, isOnline: playlistState.isOnline)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    _validityTimer?.cancel();
    SyncService.instance.stop();
    HeartbeatService.instance.stop();
    // Reset orientations when navigating back to setup/auth screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  /// Never fight the TV OS — allow all orientations and let RotatedBox do the work.
  void _applyOrientation(String orientation) {
    if (kIsWeb) return;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  /// Computes rotation needed so CMS-desired orientation fills the physical screen correctly.
  int _getQuarterTurns(String orientation, BuildContext context) {
    final size = MediaQuery.of(context).size;
    final physicallyLandscape = size.width > size.height;

    final clean = orientation.trim().toLowerCase();
    final wantsLandscape = (clean == 'landscape' || clean == '90' || clean == '270');
    final wantsPortrait = !wantsLandscape;

    if (physicallyLandscape && wantsPortrait) return 1;  // TV landscape → rotate to portrait
    if (!physicallyLandscape && wantsLandscape) return 1; // Panel portrait → rotate to landscape
    return 0; // Physical and desired match → no rotation needed
  }

  /// Sets up displaying a static image for a specified duration before advancing.
  void _scheduleImageTimer(MediaItem item) {
    if (_scheduledItemId == item.id && _imageTimer != null && _imageTimer!.isActive) {
      return;
    }
    _imageTimer?.cancel();
    _scheduledItemId = item.id;
    _imageTimer = Timer(Duration(seconds: item.duration), () {
      if (mounted) {
        ref.read(playlistProvider.notifier).nextItem();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final actState = ref.watch(activationProvider);
    final playlistState = ref.watch(playlistProvider);

    // Dynamic orientation changes listener to prevent build-phase side effects
    ref.listen<ActivationState>(activationProvider, (previous, next) {
      if (previous?.orientation != next.orientation) {
        _applyOrientation(next.orientation); // context no longer needed here
      }
    });

    // 1. Guard against initial loading of preferences
    if (actState.isLoading) {
      return _buildPremiumLoadingView();
    }

    // Redirect unactivated device to ActivationScreen
    if (!actState.isActivated && actState.deviceCode != '------') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const ActivationScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.05, end: 1.0).animate(animation),
                    child: child,
                  ),
                );
              },
              transitionDuration: const Duration(milliseconds: 600),
            ),
          );
        }
      });
      // Return a blank scaffold to stop execution and prevent empty/uninitialized errors
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }

    Widget playerBody;

    final now = DateTime.now();
    final hasValidItems = playlistState.items.any((item) => item.isValidNow(now, isOnline: playlistState.isOnline));

    if (playlistState.items.isEmpty || !hasValidItems) {
      if (!playlistState.hasInitialized || playlistState.isLoading) {
        playerBody = _buildPremiumLoadingView();
      } else {
        playerBody = _buildEmptyPlaceholder();
      }
    } else {
      var currentItem = playlistState.items[playlistState.currentIndex];

      if (!currentItem.isValidNow(now, isOnline: playlistState.isOnline)) {
        // Find the next valid item index
        int nextIdx = (playlistState.currentIndex + 1) % playlistState.items.length;
        while (nextIdx != playlistState.currentIndex) {
          if (playlistState.items[nextIdx].isValidNow(now, isOnline: playlistState.isOnline)) {
            break;
          }
          nextIdx = (nextIdx + 1) % playlistState.items.length;
        }

        final targetIndex = nextIdx;
        currentItem = playlistState.items[targetIndex];

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(playlistProvider.notifier).setCurrentIndex(targetIndex);
          }
        });
      }

      final isImageLocalPathChange = currentItem.type == 'image' && _currItem?.localPath != currentItem.localPath;
      if (_lastProcessedItemId != currentItem.id || isImageLocalPathChange) {
        _prevItem = _currItem;
        _currItem = currentItem;
        _lastProcessedItemId = currentItem.id;
        _isCurrentItemReady = false; // Always false initially, wait for load/initialize frame
      }

      final bool isOpacityOne = (_prevItem == null) || _isCurrentItemReady;
      final double prevOpacity = _isCurrentItemReady ? 0.0 : 1.0;

      List<Widget> stackChildren = [];

      if (_prevItem != null) {
        stackChildren.add(
          Positioned.fill(
            key: ValueKey('media_${_prevItem!.id}_${_prevItem!.localPath}'),
            child: AnimatedOpacity(
              opacity: prevOpacity,
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              child: _buildMediaView(_prevItem!),
            ),
          ),
        );
      }

      if (_currItem != null) {
        stackChildren.add(
          Positioned.fill(
            key: ValueKey('media_${_currItem!.id}_${_currItem!.localPath}'),
            child: AnimatedOpacity(
              opacity: isOpacityOne ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              onEnd: () {
                if (_isCurrentItemReady && mounted) {
                  setState(() {
                    _prevItem = null;
                  });
                }
              },
              child: _buildMediaView(
                _currItem!,
                onReady: () {
                  if (!_isCurrentItemReady && mounted) {
                    setState(() {
                      _isCurrentItemReady = true;
                    });
                  }
                },
              ),
            ),
          ),
        );
      }

      playerBody = Stack(
        children: stackChildren,
      );
    }

    final quarterTurns = _getQuarterTurns(actState.orientation, context);

    return Screenshot(
      controller: ScreenshotService.screenshotController,
      child: Stack(
        children: [
          RotatedBox(
            quarterTurns: quarterTurns,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: playerBody,
            ),
          ),
          // Gear icon is now outside rotation — always physically top-right
          Positioned(
            top: 16,
            right: 16,
            child: Opacity(
              opacity: 0.15,
              child: IconButton(
                icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 24),
                onPressed: () => _showAdminDialog(context, actState),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  shape: const CircleBorder(),
                ),
              ),
            ),
          ),
          // Caching progress indicator card
          if (playlistState.downloadProgress > 0.0 && playlistState.downloadProgress < 1.0)
            Positioned(
              bottom: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        value: playlistState.downloadProgress,
                        strokeWidth: 2.5,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                        backgroundColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Caching media... ${(playlistState.downloadProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Roboto',
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPremiumLoadingView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A), // Deep Slate
            Color(0xFF1E293B), // Medium Slate
            Color(0xFF0F172A), // Deep Slate
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    color: Colors.blueAccent,
                    strokeWidth: 3.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              'Initializing Screen Player',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Downloading scheduled media & caching locally...',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPlaceholder() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dashboard_customize_rounded, color: Colors.blueAccent, size: 64),
            const SizedBox(height: 24),
            const Text(
              'No Content Scheduled',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add slides or media schedules to this screen profile inside the central CMS dashboard.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageView(MediaItem item, {VoidCallback? onImageLoaded}) {
    final fileExists = item.localPath != null &&
        item.localPath!.isNotEmpty &&
        !kIsWeb &&
        File(item.localPath!).existsSync() &&
        File(item.localPath!).lengthSync() > 0;

    if (!fileExists) {
      return Image.network(
        item.url,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null && onImageLoaded != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onImageLoaded());
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) =>
            _buildErrorPlaceholder('Image failed to stream'),
      );
    }

    return Image.file(
      File(item.localPath!),
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null && onImageLoaded != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onImageLoaded());
        }
        return child;
      },
      errorBuilder: (context, error, stackTrace) =>
          _buildErrorPlaceholder('Cached image failed to read'),
    );
  }

  Widget _buildMediaView(MediaItem item, {VoidCallback? onReady}) {
    if (item.type == 'video') {
      return VideoPlayerWidget(
        key: ValueKey(item.id),
        item: item,
        onInitialized: onReady,
        onComplete: () {
          ref.read(playlistProvider.notifier).nextItem();
        },
      );
    } else {
      if (item.id == _currItem?.id) {
        _scheduleImageTimer(item);
      }
      return _buildImageView(item, onImageLoaded: onReady);
    }
  }

  Widget _buildErrorPlaceholder(String error) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(
              error,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdminDialog(BuildContext outerContext, ActivationState state) {
    showDialog(
      context: outerContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.settings_display_rounded, color: Colors.blueAccent),
              SizedBox(width: 10),
              Text(
                'Screen Diagnostics',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDiagText('Pairing Code', state.deviceCode),
              _buildDiagText('Screen ID', state.screenId),
              _buildDiagText('Company ID', state.companyId),
              _buildDiagText('Orientation', state.orientation.toUpperCase()),
              _buildDiagText('Sync Interval', '${state.syncInterval} seconds'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ref.read(activationProvider.notifier).disconnect();
                if (outerContext.mounted) {
                  Phoenix.rebirth(outerContext);
                }
              },
              icon: const Icon(Icons.link_off_rounded, color: Colors.white, size: 16),
              label: const Text('Disconnect Screen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDiagText(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value, style: const TextStyle(fontFamily: 'monospace', color: Colors.blueAccent)),
          ],
        ),
      ),
    );
  }
}

/// A wrapper widget to manage the lifecycle of a video controller safely.
class VideoPlayerWidget extends ConsumerStatefulWidget {
  final MediaItem item;
  final VoidCallback onComplete;
  final VoidCallback? onInitialized;

  const VideoPlayerWidget({
    super.key,
    required this.item,
    required this.onComplete,
    this.onInitialized,
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
    _initVideo();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateLoopingState();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  void _updateLoopingState() {
    if (_controller == null || !_initialized) return;
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
          _controller = VideoPlayerController.networkUrl(Uri.parse(widget.item.url));
        } else {
          if (kIsWeb) {
            _controller = VideoPlayerController.networkUrl(Uri.parse(widget.item.url));
          } else {
            _controller = VideoPlayerController.file(File(widget.item.localPath!));
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
        _controller!.value.position >= _controller!.value.duration) {
      _controller!.removeListener(_videoListener);
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
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

    // FittedBox correctly fills any rotated space while preserving aspect ratio
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
  }
}
