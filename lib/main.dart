import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'screens/splash_screen.dart';
import 'screens/activation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    Phoenix(
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return const ProviderScope(
      child: MaterialApp(
        title: 'TheLocads Screen Player',
        debugShowCheckedModeBanner: false,
        theme: null, // ThemeData seed can be placed below if needed
        home: SplashScreen(
          nextScreen: ActivationScreen(),
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  final String? deviceCode;
  final String? screenId;
  final String? companyId;
  final String? orientation;
  final String? syncInterval;

  const MyHomePage({
    super.key,
    required this.title,
    this.deviceCode,
    this.screenId,
    this.companyId,
    this.orientation,
    this.syncInterval,
  });

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Future<void> _disconnectDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_activated');
    await prefs.remove('activation_code');

    if (!mounted) return;
    Phoenix.rebirth(context);
  }

  String _formatDeviceCode(String? code) {
    if (code == null || code.length < 6) return 'Not Linked';
    if (code.length == 16) return code;
    return '${code.substring(0, 3)}-${code.substring(3, 6)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium Dark Theme matching ActivationScreen
      body: Container(
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.all(36),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand Logo
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.1),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Active screen illustration/icon with pulse
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const Icon(
                          Icons.monitor_rounded,
                          size: 36,
                          color: Colors.greenAccent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Title
                    const Text(
                      'Screen Status: Active',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Connection status details
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Broadcasting local market feed',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),

                    // Linked details card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow('DEVICE PAIRING CODE', _formatDeviceCode(widget.deviceCode)),
                          if (widget.screenId != null && widget.screenId!.isNotEmpty) ...[
                            const Divider(color: Colors.white10, height: 20),
                            _buildDetailRow('CMS SCREEN ID', widget.screenId!),
                          ],
                          if (widget.companyId != null && widget.companyId!.isNotEmpty) ...[
                            const Divider(color: Colors.white10, height: 20),
                            _buildDetailRow('CMS COMPANY ID', widget.companyId!),
                          ],
                          if (widget.orientation != null && widget.orientation!.isNotEmpty) ...[
                            const Divider(color: Colors.white10, height: 20),
                            _buildDetailRow('ORIENTATION', widget.orientation!.toUpperCase()),
                          ],
                          if (widget.syncInterval != null && widget.syncInterval!.isNotEmpty) ...[
                            const Divider(color: Colors.white10, height: 20),
                            _buildDetailRow('SYNC INTERVAL', '${widget.syncInterval}s'),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Unlink button
                    OutlinedButton.icon(
                      onPressed: _disconnectDevice,
                      icon: const Icon(Icons.link_off_rounded, color: Colors.redAccent, size: 18),
                      label: const Text(
                        'Disconnect Screen Pairing',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
