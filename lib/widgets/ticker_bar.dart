import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ticker_item.dart';
import 'shimmer_placeholder.dart';

enum TickerBarPosition { top, bottom }

class TickerBar extends StatefulWidget {
  final List<TickerItem> items;
  final TickerBarPosition position;

  const TickerBar({
    super.key,
    required this.items,
    required this.position,
  });

  @override
  State<TickerBar> createState() => _TickerBarState();
}

class _TickerBarState extends State<TickerBar> with TickerProviderStateMixin {
  AnimationController? _animationController;
  double _textRowWidth = 0.0;
  final GlobalKey _textRowKey = GlobalKey();

  bool _isMeasuring = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(TickerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items) {
      _updateAnimation();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _animationController?.dispose();
    super.dispose();
  }

  void _updateAnimation() {
    if (_isMeasuring) return;
    _isMeasuring = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isMeasuring = false;
      if (!mounted) return;
      final context = _textRowKey.currentContext;
      final renderBox = context?.findRenderObject() as RenderBox?;
      final newWidth = renderBox?.size.width ?? 0.0;

      if (newWidth > 0.0) {
        if (newWidth != _textRowWidth) {
          _textRowWidth = newWidth;
          _recreateAnimationController();
        }
      } else {
        // Layout or context not ready, retry in 100ms
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(milliseconds: 100), () {
          if (mounted) {
            _updateAnimation();
          }
        });
      }
    });
  }

  void _recreateAnimationController() {
    _animationController?.dispose();
    
    if (widget.items.isEmpty) return;

    final totalText = widget.items.map((item) => item.text).join('   •••   ');
    // Slowed down scroll speed: 250ms per character for better readability.
    final durationMs = (totalText.length * 250).clamp(5000, 1000000);
    
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    _animationController!.repeat();
    setState(() {});
  }

  Color _parseColor(String? hexStr, Color defaultColor) {
    if (hexStr == null || hexStr.isEmpty) return defaultColor;
    try {
      String cleanHex = hexStr.replaceAll('#', '').trim();
      if (cleanHex.length == 6) {
        cleanHex = 'FF$cleanHex';
      }
      return Color(int.parse(cleanHex, radix: 16));
    } catch (e) {
      return defaultColor;
    }
  }

  List<Widget> _buildTickerSegments() {
    final List<Widget> segments = [];
    for (int i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      final bg = _parseColor(item.bgColor, Colors.white);
      final fg = _parseColor(item.textColor, Colors.black);
      segments.add(
        Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            item.text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.2,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      );

      if (i < widget.items.length - 1) {
        segments.add(
          Container(
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '   •••   ',
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1.2,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        );
      }
    }
    return segments;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Container(
        color: Colors.white,
        alignment: Alignment.center,
        child: const ShimmerPlaceholder(),
      );
    }

    final barBg = _parseColor(widget.items.first.bgColor, Colors.white);

    return Container(
      color: barBg,
      // Removed alignment to force child to expand to full width
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scrollingAreaWidth = constraints.maxWidth;
            if (_animationController == null || _textRowWidth == 0.0) {
              return Opacity(
                opacity: 0.0,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    key: _textRowKey,
                    children: _buildTickerSegments(),
                  ),
                ),
              );
            }

            return Stack(
              clipBehavior: Clip.hardEdge,
              fit: StackFit.expand, // Ensures the stack takes full width
              children: [
                AnimatedBuilder(
                  animation: _animationController!,
                  builder: (context, child) {
                    final double val = _animationController!.value;
                    final double x = scrollingAreaWidth - (scrollingAreaWidth + _textRowWidth) * val;
                    return Positioned(
                      left: x,
                      top: 0,
                      bottom: 0,
                      child: child!,
                    );
                  },
                  child: Row(
                    key: _textRowKey,
                    children: _buildTickerSegments(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
