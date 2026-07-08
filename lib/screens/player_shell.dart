import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';

import '../models/media_item.dart';
import '../providers/player_provider.dart';
import '../services/heartbeat_service.dart';
import '../services/sync_service.dart';
import '../services/screenshot_service.dart';
import '../services/zone_content_service.dart';
import 'activation_screen.dart';

import '../widgets/video_player_widget.dart';
import '../widgets/ticker_bar.dart';
import 'layouts/half_split_layout.dart';
import 'layouts/sidebar_layout.dart';
import 'layouts/triple_layout.dart';
import 'layouts/menu_board_layout.dart';
import 'layouts/four_grid_layout.dart';
import '../widgets/cms_webview_panel.dart';

class PlayerShell extends ConsumerStatefulWidget {
  const PlayerShell({super.key});

  @override
  ConsumerState<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends ConsumerState<PlayerShell> {
  Timer? _imageTimer;
  Timer? _validityTimer;
  int? _scheduledItemId;

  int? _lastProcessedItemId;
  MediaItem? _prevItem;
  MediaItem? _currItem;
  bool _isCurrentItemReady = false;

  final GlobalKey _playerBodyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    SyncService.instance.start(ref);
    HeartbeatService.instance.start(ref);
    ZoneContentService.instance.start(ref);

    _startValidityTimer();

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

      final hasValid = playlistState.items.any((item) => item.isValidNow(now, isOnline: playlistState.isOnline));
      final ignoreSchedule = !hasValid && playlistState.items.isNotEmpty;
      if (!currentItem.isValidNow(now, isOnline: playlistState.isOnline, ignoreSchedule: ignoreSchedule)) {
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
    ZoneContentService.instance.stop();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _applyOrientation(String orientation) {
    if (kIsWeb) return;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  int _getQuarterTurns(String orientation, BuildContext context) {
    final size = MediaQuery.of(context).size;
    final physicallyLandscape = size.width > size.height;

    final clean = orientation.trim().toLowerCase();
    final wantsLandscape = (clean == 'landscape' || clean == '90' || clean == '270');
    final wantsPortrait = !wantsLandscape;

    if (physicallyLandscape && wantsPortrait) return 1;
    if (!physicallyLandscape && wantsLandscape) return 1;
    return 0;
  }

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
    final currentTickers = ref.watch(tickersProvider);

    ref.listen<ActivationState>(activationProvider, (previous, next) {
      if (previous?.orientation != next.orientation) {
        _applyOrientation(next.orientation);
      }
    });

    if (actState.isLoading) {
      return _buildPremiumLoadingView();
    }

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
      return Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          color: Colors.black,
          child: const SizedBox.shrink(),
        ),
      );
    }

    Widget playerBody;

    final now = DateTime.now();
    final scheduledItems = playlistState.items.where((item) => item.schedule != null);
    bool hasValidItems;
    if (scheduledItems.isEmpty) {
      hasValidItems = playlistState.items.any((item) => item.isValidNow(now, isOnline: playlistState.isOnline, ignoreSchedule: false));
    } else {
      hasValidItems = scheduledItems.any((item) => item.isValidNow(now, isOnline: playlistState.isOnline, ignoreSchedule: false));
    }

    bool ignoreSchedule = false;
    if (!hasValidItems && playlistState.items.isNotEmpty) {
      hasValidItems = playlistState.items.any((item) => item.isValidNow(now, isOnline: playlistState.isOnline, ignoreSchedule: true));
      if (hasValidItems) {
        ignoreSchedule = true;
      }
    }

    if (playlistState.items.isEmpty) {
      if (!playlistState.hasInitialized || playlistState.isLoading) {
        playerBody = _buildPremiumLoadingView();
      } else {
        playerBody = _buildEmptyPlaceholder();
      }
    } else if (!hasValidItems) {
      playerBody = _buildPremiumLoadingView();
    } else {
      var currentItem = playlistState.items[playlistState.currentIndex];

      if (!currentItem.isValidNow(now, isOnline: playlistState.isOnline, ignoreSchedule: ignoreSchedule)) {
        int nextIdx = (playlistState.currentIndex + 1) % playlistState.items.length;
        while (nextIdx != playlistState.currentIndex) {
          if (playlistState.items[nextIdx].isValidNow(now, isOnline: playlistState.isOnline, ignoreSchedule: ignoreSchedule)) {
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
        _isCurrentItemReady = false;
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

      playerBody = KeyedSubtree(
        key: _playerBodyKey,
        child: Stack(
          children: stackChildren,
        ),
      );
    }

    final quarterTurns = _getQuarterTurns(actState.orientation, context);
    final isHeaderLayout = actState.layout == 'header';
    final isTickerLayout = actState.layout == 'ticker';
    final isHalfSplitLayout = actState.layout == 'half_split';
    final isSidebarLayout = actState.layout == 'sidebar';
    final isTripleLayout = actState.layout == 'triple';
    final isMenuBoardLayout = actState.layout == 'menu_board';
    final isFourGridLayout = actState.layout == 'four_grid';

    Widget finalBody = AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      layoutBuilder: (currentChild, previousChildren) {
        // Custom layout builder to avoid multiple GlobalKeys in the tree during cross-fade
        return currentChild ?? const SizedBox.shrink();
      },
      child: isHalfSplitLayout
          ? HalfSplitLayout(
              key: const ValueKey('half_split'),
              baseMediaSurface: playerBody,
            )
          : isSidebarLayout
              ? SidebarLayout(
                  key: const ValueKey('sidebar'),
                  baseMediaSurface: playerBody,
                  sidebarUrl: actState.sidebarUrl,
                )
              : isTripleLayout
                  ? TripleLayout(
                      key: const ValueKey('triple'),
                      baseMediaSurface: playerBody,
                      centerUrl: actState.centerUrl,
                      rightUrl: actState.rightUrl,
                    )
                  : isMenuBoardLayout
                      ? MenuBoardLayout(
                          key: const ValueKey('menu_board'),
                          baseMediaSurface: playerBody,
                          webviewUrl: actState.sidebarUrl,
                        )
                      : isFourGridLayout
                          ? FourGridLayout(
                              key: const ValueKey('four_grid'),
                              baseMediaSurface: playerBody,
                              topRightUrl: actState.topRightUrl,
                              bottomLeftUrl: actState.bottomLeftUrl,
                              bottomRightUrl: actState.bottomRightUrl,
                            )
                          : Container(
                              key: const ValueKey('fullscreen'),
                              child: playerBody,
                            ),
    );

    return Screenshot(
      controller: ScreenshotService.screenshotController,
      child: RotatedBox(
        quarterTurns: quarterTurns,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              top: isHeaderLayout ? 50.0 : 0.0,
              bottom: isTickerLayout ? 50.0 : 0.0,
              left: 0,
              right: 0,
              child: Scaffold(
                backgroundColor: Colors.black,
                body: Container(
                  color: Colors.black,
                  child: finalBody,
                ),
              ),
            ),
          if (isHeaderLayout)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 50.0,
              child: TickerBar(
                items: currentTickers,
                position: TickerBarPosition.top,
              ),
            ),
          if (isTickerLayout)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 50.0,
              child: TickerBar(
                items: currentTickers,
                position: TickerBarPosition.bottom,
              ),
            ),
          Positioned(
            top: 16,
            right: 16,
            child: Opacity(
              opacity: 0.0,
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
                      'Downloading media... ${(playlistState.downloadProgress * 100).toStringAsFixed(0)}%',
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
      ),
    );
  }

  Widget _buildPremiumLoadingView() {
    return Container(
      color: Colors.black,
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
    final actState = ref.watch(activationProvider);
    final uid = actState.deviceCode.isNotEmpty && actState.deviceCode != '------' ? actState.deviceCode : actState.screenId;
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Image.asset('assets/images/logo.png', height: 36, errorBuilder: (c,e,s) => const Icon(Icons.monitor, color: Colors.amberAccent)),
      ),
      body: Container(
        color: Colors.black,
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape = constraints.maxWidth > constraints.maxHeight;

              if (isLandscape) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('UID', style: TextStyle(color: Colors.white70, fontSize: 16)),
                              Row(
                                children: [
                                  Text(uid, style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.copy, color: Colors.white70, size: 18),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          const Text('Setup Progress', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text('Complete the steps to start displaying your content', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 24),
                          _buildSetupTimeline(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48),
                    Expanded(
                      flex: 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildScreenGraphic(),
                          const SizedBox(height: 24),
                          const Text('Waiting for Content', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          const Text(
                            "You've scheduled this screen, but there is no\ncontent assigned yet.\nOnce content is scheduled, it will appear here.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          
                        ],
                      ),
                    ),
                  ],
                );
              }

              // Portrait layout
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('UID', style: TextStyle(color: Colors.white70, fontSize: 16)),
                      Row(
                        children: [
                          Text(uid, style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const SizedBox(width: 8),
                          const Icon(Icons.copy, color: Colors.white70, size: 18),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(flex: 1),
                  const Text('Setup Progress', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Complete the steps to start displaying your content', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 24),
                  _buildSetupTimeline(),
                  const Spacer(flex: 2),
                  Center(
                    child: Column(
                      children: [
                        _buildScreenGraphic(),
                        const SizedBox(height: 32),
                        const Text('Waiting for Content', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        const Text(
                          "You've scheduled this screen, but there is no\ncontent assigned yet.\nOnce content is scheduled, it will appear here.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                        ),

                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                ],
              );
            },
          ),
        ),
      ),
    ),);
  }

  Widget _buildSetupTimeline() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTimelineStep(Icons.check, 'Make Screen', true),
        _buildTimelineLine(true),
        _buildTimelineLine(false),
        _buildTimelineStep(Icons.access_time, 'Schedule Content', false),
      ],
    );
  }

  Widget _buildTimelineStep(IconData icon, String label, bool isCompleted) {
    return Expanded(
      flex: 3,
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? Colors.amberAccent : Colors.transparent,
              border: Border.all(color: Colors.amberAccent, width: 2),
            ),
            child: Icon(icon, size: 16, color: isCompleted ? Colors.black : Colors.amberAccent),
          ),
          const SizedBox(height: 8),
          Text(
            label, 
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isCompleted ? Colors.white : Colors.white54, 
              fontSize: 10, 
              fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal
            )
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineLine(bool isCompleted) {
    return Expanded(
      flex: 2,
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(top: 14),
        color: isCompleted ? Colors.amberAccent : Colors.white24,
      ),
    );
  }

  Widget _buildScreenGraphic() {
    return SizedBox(
      width: 200,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 180,
            height: 110,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white12, width: 1, style: BorderStyle.solid),
                ),
                child: Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white12,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.hourglass_empty, color: Colors.amberAccent, size: 24),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 60,
              height: 4,
              color: Colors.white24,
            ),
          ),
          Positioned(
            bottom: 4,
            child: Container(
              width: 16,
              height: 8,
              color: Colors.white24,
            ),
          ),
          const Positioned(
            right: 0,
            bottom: 10,
            child: Icon(Icons.spa, color: Colors.amberAccent, size: 24),
          ),
        ],
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
              _buildDiagText('Layout', state.layout.toUpperCase()),
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
