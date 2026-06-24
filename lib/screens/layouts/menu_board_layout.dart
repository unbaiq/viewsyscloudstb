import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/zone_content_provider.dart';
import '../../services/zone_content_service.dart';
import '../../widgets/zone_media_viewer.dart';

const int _flexLeft = 3;
const int _flexRight = 7;

class MenuBoardLayout extends ConsumerStatefulWidget {
  final Widget baseMediaSurface;
  final String? webviewUrl;

  const MenuBoardLayout({
    super.key,
    required this.baseMediaSurface,
    this.webviewUrl,
  });

  @override
  ConsumerState<MenuBoardLayout> createState() => _MenuBoardLayoutState();
}

class _MenuBoardLayoutState extends ConsumerState<MenuBoardLayout> {
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
    final zoneState = ref.watch(leftZoneProvider);

    return Row(
      children: [
        // LEFT ZONE (~30%): Independent API Media
        Expanded(
          flex: _flexLeft,
          child: Container(
            color: Colors.black,
            child: ZoneMediaViewer(state: zoneState),
          ),
        ),

        // Divider
        Container(
          width: 2,
          color: Colors.white.withValues(alpha: 0.1),
        ),

        // RIGHT ZONE (~70%): Existing base media surface
        Expanded(
          flex: _flexRight,
          child: widget.baseMediaSurface,
        ),
      ],
    );
  }
}
