import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'shimmer_placeholder.dart';

class CmsWebviewPanel extends StatefulWidget {
  final String? url;

  const CmsWebviewPanel({super.key, required this.url});

  @override
  State<CmsWebviewPanel> createState() => _CmsWebviewPanelState();
}

class _CmsWebviewPanelState extends State<CmsWebviewPanel> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = 'Content Unavailable';
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void didUpdateWidget(CmsWebviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _loadUrl();
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _retryTimer?.cancel();
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView resource error: ${error.description}');
            _handleError();
          },
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      );
    _loadUrl();
  }

  void _loadUrl() {
    _retryTimer?.cancel();
    if (widget.url == null || widget.url!.isEmpty) {
      if (mounted) {
        setState(() {
          _hasError = false;
          _isLoading = true;
        });
      }
      // If we don't have a URL, we retry later in case it arrives in a future sync
      _retryTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) {
          _loadUrl();
        }
      });
      return;
    }

    try {
      final uri = Uri.parse(widget.url!);
      _controller.loadRequest(uri);
    } catch (e) {
      print('Invalid WebView URL: ${widget.url}');
      _handleError('Invalid URL format');
    }
  }

  void _handleError([String? customMessage]) {
    if (mounted) {
      setState(() {
        _hasError = true;
        _errorMessage = customMessage ?? 'Failed to load webpage';
        _isLoading = false;
      });
    }
    // Unattended kiosk behavior: retry automatically
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        _loadUrl();
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.white54),
            ),
            if (widget.url != null && widget.url!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  widget.url!,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Positioned.fill(
            child: ShimmerPlaceholder(),
          ),
      ],
    );
  }
}
