import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../services/app_lock_service.dart';
import '../theme/app_theme.dart';

/// Full-screen PIN entry with a glassy neon number pad.
///
/// [setupMode] = true → enter a PIN, then confirm it (used to enable / change
/// the lock). [setupMode] = false → unlock verification. When used for
/// unlocking, a successful entry calls [AppLockService.unlock()].
class AppLockScreen extends StatefulWidget {
  final bool setupMode;
  final VoidCallback? onUnlocked;

  const AppLockScreen({super.key, this.setupMode = false, this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen>
    with TickerProviderStateMixin {
  static const int _pinLength = 6;

  final List<int> _digits = [];
  String? _firstPin;
  bool _confirming = false;
  bool _isError = false;
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    if (!widget.setupMode) {
      _tryBiometricUnlock();
    }
  }

  /// If the user enabled fingerprint/face unlock, offer it immediately.
  Future<void> _tryBiometricUnlock() async {
    try {
      if (!await AppLockService.isBiometricsEnabled()) return;
      final auth = LocalAuthentication();
      final canCheck = await auth.canCheckBiometrics;
      final isDeviceSupported = await auth.isDeviceSupported();
      if (!canCheck || !isDeviceSupported || !mounted) return;
      final success = await auth.authenticate(
        localizedReason: 'Unlock AAA Private Agent',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (success && mounted) {
        AppLockService.unlock();
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(true);
        widget.onUnlocked?.call();
      }
    } catch (_) {
      // Fall through to the PIN pad.
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  String get _title {
    if (_isError) return 'Wrong PIN';
    if (widget.setupMode) {
      return _confirming ? 'Confirm your PIN' : 'Set a $_pinLength-digit PIN';
    }
    return 'Enter PIN';
  }

  Future<void> _onDigit(int digit) async {
    if (_isError) return;
    HapticFeedback.lightImpact();
    setState(() => _digits.add(digit));
    if (_digits.length < _pinLength) return;

    final pin = _digits.join();

    if (widget.setupMode) {
      if (!_confirming) {
        _firstPin = pin;
        setState(() {
          _confirming = true;
          _digits.clear();
        });
        return;
      }
      if (pin == _firstPin) {
        await AppLockService.setPin(pin);
        if (mounted) {
          Navigator.of(context).pop(true);
          widget.onUnlocked?.call();
        }
      } else {
        await _fail();
      }
      return;
    }

    final ok = await AppLockService.verifyPin(pin);
    if (ok) {
      AppLockService.unlock();
      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onUnlocked?.call();
      }
    } else {
      await _fail();
    }
  }

  Future<void> _fail() async {
    HapticFeedback.vibrate();
    setState(() => _isError = true);
    _shake.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() {
      _digits.clear();
      _isError = false;
    });
  }

  void _onBackspace() {
    if (_isError || _digits.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _digits.removeLast());
  }

  Widget _key(String label, {VoidCallback? onTap, Widget? child}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(
              child: child ??
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B0A1A), Color(0xFF1A1440), Color(0xFF0B0A1A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppGradients.brand,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.indigo.withValues(alpha: 0.45),
                      blurRadius: 28,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  _title,
                  key: ValueKey('$_confirming-$_isError'),
                  style: TextStyle(
                    color: _isError ? AppColors.danger : Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.setupMode
                    ? 'Use a PIN you will remember.'
                    : 'PrivateAgent is locked.',
                style: const TextStyle(
                  color: Color(0xFF9AA3BF),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 28),
              // PIN dots
              AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final offset = (_shake.value * 18).roundToDouble();
                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_pinLength, (i) {
                    final filled = i < _digits.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? (_isError ? AppColors.danger : AppColors.cyan)
                            : Colors.white.withValues(alpha: 0.18),
                        border: Border.all(
                          color: filled
                              ? Colors.transparent
                              : Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const Spacer(flex: 2),

              // Number pad
              _buildPad(),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPad() {
    Widget numberKey(int n) => _key(
          '$n',
          onTap: () => _onDigit(n),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            numberKey(1),
            numberKey(2),
            numberKey(3),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            numberKey(4),
            numberKey(5),
            numberKey(6),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            numberKey(7),
            numberKey(8),
            numberKey(9),
          ]),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _key('', child: const SizedBox()),
              numberKey(0),
              _key(
                '',
                onTap: _onBackspace,
                child: const Icon(
                  Icons.backspace_outlined,
                  color: Colors.white70,
                  size: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
