import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/player_provider.dart';
import 'screens/player_screen.dart';

class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> with SingleTickerProviderStateMixin {
  String _activationCode = '------';
  Timer? _checkerTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isActivating = false;

  @override
  void initState() {
    super.initState();
    _initActivationCode();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 4.0, end: 16.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _checkerTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initActivationCode() async {
    final prefs = await SharedPreferences.getInstance();
    String? code = prefs.getString('activation_code');
    if (code == null || code.isEmpty || code.length != 6) {
      final random = Random();
      final number = random.nextInt(900000) + 100000;
      code = number.toString();
      await prefs.setString('activation_code', code);
    }
    if (mounted) {
      setState(() {
        _activationCode = code!;
      });
      _startActivationChecker();
    }
  }

  Future<void> _generateNewCode() async {
    final prefs = await SharedPreferences.getInstance();
    final random = Random();
    final number = random.nextInt(900000) + 100000;
    final code = number.toString();
    
    await prefs.setString('activation_code', code);
    await prefs.setBool('is_activated', false);

    if (mounted) {
      setState(() {
        _activationCode = code;
      });
      _checkerTimer?.cancel();
      _startActivationChecker();
    }
  }

  void _startActivationChecker() {
    if (_activationCode == '------') return;
    _checkActivationRecursive();
  }

  void _checkActivationRecursive() async {
    if (!mounted || _isActivating) return;

    bool isApiAuthorized = false;
    String screenId = '';
    String companyId = '';
    String orientation = 'landscape';
    String syncInterval = '10';

    try {
      final url = Uri.parse('https://viewsys.co.in/api/player/login');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'device_id': _activationCode}),
      );

      debugPrint('CMS API check for $_activationCode: Status ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['status'] == 'authorized') {
          isApiAuthorized = true;
          screenId = data['screen_id']?.toString() ?? '';
          companyId = data['company_id']?.toString() ?? '';
          orientation = data['orientation']?.toString() ?? 'landscape';
          syncInterval = data['sync_interval']?.toString() ?? '3';
        }
      }
    } catch (e) {
      debugPrint('CMS API check error: $e');
    }

    if (!mounted || _isActivating) return;

    if (isApiAuthorized) {
      _isActivating = true;
      _checkerTimer?.cancel();
      _checkerTimer = null;

      await ref.read(activationProvider.notifier).activateDevice(
        screenId: screenId,
        companyId: companyId,
        orientation: orientation,
        syncInterval: int.tryParse(syncInterval) ?? 3,
      );

      _navigateToDashboard();
      return;
    }

    // Checking local mock/simulation states as secondary fallback
    final prefs = await SharedPreferences.getInstance();
    final isActivated = prefs.getBool('is_activated') ?? false;
    final code = prefs.getString('activation_code') ?? '';

    if (!mounted || _isActivating) return;

    if (isActivated && code == _activationCode) {
      _isActivating = true;
      _checkerTimer?.cancel();
      _checkerTimer = null;

      final sId = prefs.getString('screen_id') ?? '5';
      final cId = prefs.getString('company_id') ?? '1';
      final orient = prefs.getString('orientation') ?? 'landscape';
      final syncInt = prefs.getString('sync_interval') ?? '3';
      
      await ref.read(activationProvider.notifier).activateDevice(
        screenId: sId,
        companyId: cId,
        orientation: orient,
        syncInterval: int.tryParse(syncInt) ?? 3,
      );
      _navigateToDashboard();
    } else {
      // Polling: call recursively after 2 seconds
      _checkerTimer = Timer(const Duration(seconds: 2), _checkActivationRecursive);
    }
  }

  void _navigateToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const PlayerScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  // Automatic code expiration removed as requested by the user.

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _activationCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Text(
              'Code $_activationCode copied to clipboard!',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _simulateSuccessfulActivation() async {
    _isActivating = true;
    _checkerTimer?.cancel();
    _checkerTimer = null;

    if (!mounted) return;

    // Show a beautiful loading overlay first to simulate network pairing
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    color: Colors.blueAccent,
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Verifying Activation Code...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pairing this screen with your merchant account.',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );

    // After 2.5 seconds, navigate to home screen. The dialogue is popped, and
    // SharedPreferences is updated cleanly to prevent race conditions.
    Timer(const Duration(milliseconds: 2500), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_activated', true);
      await prefs.setString('activation_code', _activationCode);
      await prefs.setString('screen_id', '5');
      await prefs.setString('company_id', '1');
      await prefs.setString('orientation', 'landscape');
      await prefs.setString('sync_interval', '10');

      if (!mounted) return;
      Navigator.of(context).pop(); // pop dialogue
      
      await ref.read(activationProvider.notifier).activateDevice(
        screenId: '5',
        companyId: '1',
        orientation: 'landscape',
        syncInterval: 10,
      );
      _navigateToDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate blue
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                  child: SizedBox(
                    width: 600,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // App Logo Header
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
                            height: 36,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 48),

                        // Title
                        const Text(
                          'Link Your Screen',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Display merchant content on this device.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey.shade400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 36),

                        // Steps Instructions
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStepRow(
                                stepNumber: '1',
                                instruction: 'Go to ',
                                highlight: 'thelocals.com/activate',
                                instructionSuffix: ' on your phone or computer.',
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(color: Colors.white10, height: 1),
                              ),
                              _buildStepRow(
                                stepNumber: '2',
                                instruction: 'Login and click on ',
                                highlight: 'Add New Screen',
                                instructionSuffix: '.',
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(color: Colors.white10, height: 1),
                              ),
                              _buildStepRow(
                                stepNumber: '3',
                                instruction: 'Enter the 6-digit code shown below.',
                                highlight: '',
                                instructionSuffix: '',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Animated Activation Code Container
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blueAccent.withOpacity(0.15),
                                    blurRadius: _pulseAnimation.value,
                                    spreadRadius: _pulseAnimation.value * 0.2,
                                  ),
                                ],
                              ),
                              child: child,
                            );
                          },
                          child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.blueAccent.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Code display
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildCodeGroup(_activationCode.substring(0, 3)),
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade500,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildCodeGroup(_activationCode.substring(3, 6)),
                      ],
                    ),            
                                
                                const SizedBox(height: 20),

                                // Status indicator (recursive checking indicator)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Checking screen pairing status...',
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Action Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: _copyToClipboard,
                              icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.blueAccent),
                              label: const Text(
                                'Copy Code',
                                style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            TextButton.icon(
                              onPressed: _generateNewCode,
                              icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.blueAccent),
                              label: const Text(
                                'Refresh Code',
                                style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 48),

                        // Simulation button
                        ElevatedButton.icon(
                          onPressed: _simulateSuccessfulActivation,
                          icon: const Icon(Icons.check_circle_rounded, size: 20),
                          label: const Text(
                            'Simulate Activation Pairing',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 8,
                            shadowColor: Colors.blueAccent.withOpacity(0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow({
    required String stepNumber,
    required String instruction,
    required String highlight,
    required String instructionSuffix,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
          ),
          child: Center(
            child: Text(
              stepNumber,
              style: const TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade300,
                height: 1.4,
              ),
              children: [
                TextSpan(text: instruction),
                if (highlight.isNotEmpty)
                  TextSpan(
                    text: highlight,
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                TextSpan(text: instructionSuffix),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeGroup(String digits) {
    return Row(
      children: digits.split('').map((char) {
        return Container(
          width: 36,
          height: 50,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Center(
            child: Text(
              char,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
