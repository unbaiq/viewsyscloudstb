import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeVideoPlayer extends StatefulWidget {
  final String url;
  final bool loop;
  final double volume;
  final bool muted;
  final VoidCallback? onComplete;
  final VoidCallback? onReady;
  final Function(String)? onError;

  const NativeVideoPlayer({
    super.key,
    required this.url,
    this.loop = true,
    this.volume = 1.0,
    this.muted = false,
    this.onComplete,
    this.onReady,
    this.onError,
  });

  @override
  NativeVideoPlayerState createState() => NativeVideoPlayerState();
}

class NativeVideoPlayerState extends State<NativeVideoPlayer> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(NativeVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loop != widget.loop) {
      setLoop(widget.loop);
    }
    if (oldWidget.muted != widget.muted || oldWidget.volume != widget.volume) {
      setMuted(widget.muted);
    }
    if (oldWidget.url != widget.url) {
      play(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Container(color: Colors.black);
    }

    return AndroidView(
      viewType: 'native_video_player',
      creationParams: <String, dynamic>{
        'url': widget.url,
        'loop': widget.loop,
        'volume': widget.muted ? 0.0 : widget.volume,
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('native_video_player_$id');
    _channel?.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onVideoReady':
          widget.onReady?.call();
          break;
        case 'onVideoEnded':
          widget.onComplete?.call();
          break;
        case 'onVideoError':
          widget.onError?.call(call.arguments as String? ?? 'Unknown error');
          break;
      }
    });
  }

  void play(String url) {
    _channel?.invokeMethod('play', {'url': url});
  }

  void pause() {
    _channel?.invokeMethod('pause');
  }

  void resume() {
    _channel?.invokeMethod('resume');
  }

  void stop() {
    _channel?.invokeMethod('stop');
  }

  void setVolume(double volume) {
    _channel?.invokeMethod('setVolume', {'volume': volume});
  }

  void setMuted(bool muted) {
    _channel?.invokeMethod('setVolume', {'volume': muted ? 0.0 : widget.volume});
  }

  void setLoop(bool loop) {
    _channel?.invokeMethod('setLoop', {'loop': loop});
  }

  @override
  void dispose() {
    _channel?.invokeMethod('release');
    _channel = null;
    super.dispose();
  }
}
