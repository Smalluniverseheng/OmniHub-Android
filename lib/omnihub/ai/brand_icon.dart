/// OmniHub 厂商品牌图标
///
/// 与 aiBeta js/providers.js 的 providerIconHtml 对齐：
/// lobe 彩色/单色 PNG（npmmirror → unpkg 回退）→ simpleicons CDN → 首字母兜底。
library brand_icon;

import 'package:flutter/material.dart';

class BrandIcon extends StatefulWidget {
  /// lobehub icons slug（如 openai / deepseek-color），可空
  final String? lobe;

  /// simpleicons slug（如 xiaomi / baidu），可空
  final String? simple;

  /// 品牌色（兜底字母头像背景）
  final int color;

  /// 兜底字母（一般为厂商名首字符）
  final String letter;

  final double size;

  const BrandIcon({
    super.key,
    this.lobe,
    this.simple,
    required this.color,
    required this.letter,
    this.size = 40,
  });

  @override
  State<BrandIcon> createState() => _BrandIconState();
}

class _BrandIconState extends State<BrandIcon> {
  int _idx = 0;

  List<String> get _urls => [
        if (widget.lobe != null) ...[
          'https://registry.npmmirror.com/@lobehub/icons-static-png/latest/files/light/${widget.lobe}.png',
          'https://unpkg.com/@lobehub/icons-static-png@latest/light/${widget.lobe}.png',
        ],
        if (widget.simple != null)
          'https://cdn.simpleicons.org/${widget.simple}',
      ];

  void _advance() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _idx++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final urls = _urls;
    final size = widget.size;
    final radius = BorderRadius.circular(size * 0.28);
    if (_idx < urls.length) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(size * 0.18),
          child: Image.network(
            urls[_idx],
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) {
              _advance();
              return const SizedBox.shrink();
            },
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : const SizedBox.shrink(),
          ),
        ),
      );
    }
    // 全部图标源失败 → 品牌色 + 首字母
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Color(widget.color), borderRadius: radius),
      alignment: Alignment.center,
      child: Text(
        widget.letter.isEmpty ? '?' : widget.letter.substring(0, 1).toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: size * 0.4),
      ),
    );
  }
}
