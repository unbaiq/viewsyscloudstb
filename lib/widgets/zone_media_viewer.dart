import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
// NativeVideoPlayer removed as VideoPlayerWidget now exclusively wraps it
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/media_item.dart';
import '../providers/zone_content_provider.dart';
import 'video_player_widget.dart';
import 'shimmer_placeholder.dart';
import 'cms_webview_panel.dart';

class ZoneMediaViewer extends ConsumerStatefulWidget {
  final StateNotifierProvider<ZoneContentNotifier, ZoneContentState> provider;
  final String? fallbackUrl;

  const ZoneMediaViewer({
    super.key,
    required this.provider,
    this.fallbackUrl,
  });

  @override
  ConsumerState<ZoneMediaViewer> createState() => _ZoneMediaViewerState();
}

class _ZoneMediaViewerState extends ConsumerState<ZoneMediaViewer> {
  Timer? _imageTimer;

  @override
  void dispose() {
    _imageTimer?.cancel();
    super.dispose();
  }

  void _scheduleNextItem(int durationSeconds) {
    _imageTimer?.cancel();
    if (durationSeconds <= 0) return;
    
    _imageTimer = Timer(Duration(seconds: durationSeconds), () {
      if (mounted) {
        ref.read(widget.provider.notifier).nextItem();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);

    if (state.isLoading) {
      return const Center(child: ShimmerPlaceholder());
    }

    if (state.errorMessage != null) {
      if (widget.fallbackUrl != null && widget.fallbackUrl!.isNotEmpty) {
        return CmsWebviewPanel(url: widget.fallbackUrl);
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Failed to load zone content',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final item = state.item;
    if (item == null) {
      if (widget.fallbackUrl != null && widget.fallbackUrl!.isNotEmpty) {
        return CmsWebviewPanel(url: widget.fallbackUrl);
      }
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported_outlined, color: Colors.white24, size: 40),
            const SizedBox(height: 12),
            const Text(
              'No content configured',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return _buildMediaView(item, state.items.length);
  }

  Widget _buildMediaView(MediaItem item, int totalItems) {
    if (item.type == 'video') {
      _imageTimer?.cancel();

      return VideoPlayerWidget(
        key: ValueKey('zone_video_${item.id}_${item.localPath ?? item.url}'),
        item: item,
        forceLoop: totalItems <= 1,
        onComplete: () {
          if (mounted && totalItems > 1) {
            ref.read(widget.provider.notifier).nextItem();
          }
        },
      );
    } else {
      if (totalItems > 1) {
         _scheduleNextItem(item.duration);
      }
      return _buildImageView(item);
    }
  }

  Widget _buildImageView(MediaItem item) {
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
        errorBuilder: (context, error, stackTrace) =>
            _buildErrorPlaceholder('Image failed to stream'),
      );
    }

    return Image.file(
      File(item.localPath!),
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) =>
          _buildErrorPlaceholder('Cached image failed to read'),
    );
  }

  Widget _buildErrorPlaceholder(String error) {
    if (widget.fallbackUrl != null && widget.fallbackUrl!.isNotEmpty) {
      return CmsWebviewPanel(url: widget.fallbackUrl!);
    }
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 30),
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
