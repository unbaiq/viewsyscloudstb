import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../providers/zone_content_provider.dart';
import 'video_player_widget.dart';
import 'shimmer_placeholder.dart';

class ZoneMediaViewer extends StatelessWidget {
  final ZoneContentState state;

  const ZoneMediaViewer({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: ShimmerPlaceholder());
    }

    if (state.errorMessage != null) {
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

    if (state.item == null) {
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

    return _buildMediaView(state.item!);
  }

  Widget _buildMediaView(MediaItem item) {
    if (item.type == 'video') {
      return VideoPlayerWidget(
        key: ValueKey('zone_video_${item.id}'),
        item: item,
        forceLoop: true,
        onComplete: () {},
      );
    } else {
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
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) =>
            _buildErrorPlaceholder('Image failed to stream'),
      );
    }

    return Image.file(
      File(item.localPath!),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) =>
          _buildErrorPlaceholder('Cached image failed to read'),
    );
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
}
