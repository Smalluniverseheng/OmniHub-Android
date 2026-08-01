/// OmniHub 开屏动画（移植自网页版 index.html #splash）
///
/// 网页版规格：
/// - 背景 #0D0E13，.logo 88px 圆角 22px，靛→紫渐变光晕
/// - 标语「纵横四海·引领无限」，间隔点 #6366F1
/// - 品牌「OMNIHUB」大写字距 3px
/// - 入场 scale(.92)+translateY(14px) → 正常，0.7s
/// - 停留后 0.6s 淡出移除
library omni_splash;

import 'package:flutter/material.dart';

import 'package:venera/foundation/appdata.dart';

class OmniSplashScreen extends StatefulWidget {
  const OmniSplashScreen({required this.child, super.key});

  final Widget child;

  @override
  State<OmniSplashScreen> createState() => _OmniSplashScreenState();
}

class _OmniSplashScreenState extends State<OmniSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in;
  bool _fadeOut = false;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    // 停留约 1.4s 后开始 0.6s 淡出（网页版为加载完成或 3s 兜底）
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _fadeOut = true);
    });
    Future.delayed(const Duration(milliseconds: 2100), () {
      if (mounted) setState(() => _removed = true);
    });
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_removed) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _fadeOut,
            child: AnimatedOpacity(
              opacity: _fadeOut ? 0 : 1,
              duration: const Duration(milliseconds: 600),
              curve: const Cubic(.22, .8, .32, 1),
              child: const _SplashBody(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody();

  bool get _isLight {
    final mode = appdata.settings['theme_mode'];
    if (mode == 'light') return true;
    if (mode == 'dark') return false;
    // system：跟随平台亮度
    return WidgetsBinding
            .instance.platformDispatcher.platformBrightness ==
        Brightness.light;
  }

  @override
  Widget build(BuildContext context) {
    final light = _isLight;
    return Container(
      color: light ? Colors.white : const Color(0xFF0D0E13),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: const Cubic(.22, .8, .32, 1),
          builder: (context, v, child) {
            return Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - v)),
                child: Transform.scale(
                  scale: .92 + .08 * v,
                  child: child,
                ),
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x596366F1),
                      blurRadius: 32,
                      offset: Offset(0, 8),
                    ),
                  ],
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '纵横四海'),
                    TextSpan(
                      text: '·',
                      style: TextStyle(
                        color: Color(0xFF6366F1),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(text: '引领无限'),
                  ],
                ),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: light
                      ? const Color(0xFF4A5061)
                      : const Color(0xFFA6ADC0),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'OMNIHUB',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: light
                      ? const Color(0xFF9AA0AE)
                      : const Color(0xFF646C7E),
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
