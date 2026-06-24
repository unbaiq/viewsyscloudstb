import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/media_item.dart';
import '../../providers/zone_content_provider.dart';
import '../../services/zone_content_service.dart';
import '../../widgets/video_player_widget.dart';
import '../../widgets/shimmer_placeholder.dart';
import '../../widgets/cms_webview_panel.dart';

class TripleLayout extends ConsumerStatefulWidget {
  final Widget baseMediaSurface;
  final String? centerUrl;
  final String? rightUrl;

  const TripleLayout({
    super.key,
    required this.baseMediaSurface,
    this.centerUrl,
    this.rightUrl,
  });

  @override
  ConsumerState<TripleLayout> createState() => _TripleLayoutState();
}

class _TripleLayoutState extends ConsumerState<TripleLayout> {
  @override
  void initState() {
    super.initState();
    ZoneContentService.instance.start(ref);
  }

  @override
  void dispose() {
    ZoneContentService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final centerState = ref.watch(centerZoneProvider);
    final rightState = ref.watch(rightZoneProvider);

    return Row(
      children: [
        // LEFT ZONE (1/3): Existing base media surface
        Expanded(
          flex: 1,
          child: widget.baseMediaSurface,
        ),
        
        // Divider
        Container(
          width: 2,
          color: Colors.white.withValues(alpha: 0.1),
        ),

        // CENTER ZONE (1/3): Schedule API Content with fallback
        Expanded(
          flex: 1,
          child: Container(
            color: Colors.black,
            child: _buildZoneContent(centerState, widget.centerUrl),
          ),
        ),

        // Divider
        Container(
          width: 2,
          color: Colors.white.withValues(alpha: 0.1),
        ),

        // RIGHT ZONE (1/3): Schedule API Content with fallback
        Expanded(
          flex: 1,
          child: Container(
            color: Colors.black,
            child: _buildZoneContent(rightState, widget.rightUrl),
          ),
        ),
      ],
    );
  }

  Widget _buildZoneContent(ZoneContentState state, String? fallbackUrl) {
    if (state.isLoading) {
      return const Center(child: ShimmerPlaceholder());
    }

    if (state.errorMessage != null || state.item == null) {
      if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
        return CmsWebviewPanel(url: fallbackUrl);
      }
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_outlined, color: Colors.white24, size: 40),
            SizedBox(height: 12),
            Text(
              'No content configured',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return _buildMediaView(state.item!, fallbackUrl);
  }

  Widget _buildMediaView(MediaItem item, String? fallbackUrl) {
    if (item.type == 'video') {
      return VideoPlayerWidget(
        key: ValueKey('zone_video_${item.id}'),
        item: item,
        forceLoop: true,
        onComplete: () {},
      );
    } else {
      return _buildImageView(item, fallbackUrl);
    }
  }

  Widget _buildImageView(MediaItem item, String? fallbackUrl) {
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
            _buildErrorPlaceholder('Image failed to stream', fallbackUrl),
      );
    }

    return Image.file(
      File(item.localPath!),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) =>
          _buildErrorPlaceholder('Cached image failed to read', fallbackUrl),
    );
  }

  Widget _buildErrorPlaceholder(String error, String? fallbackUrl) {
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      return CmsWebviewPanel(url: fallbackUrl);
    }
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
