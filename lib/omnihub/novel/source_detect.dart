/// 书源格式自动识别（移植自网页版 js/source-detect.js）
///
/// 粘贴内容 → 识别为 Legado JSON / Legado RSS / TVBox 视频源 /
/// Venera JS / CSS 选择器配置 / Legado JS 片段。
library source_detect;

import 'dart:convert';

import 'package:archive/archive.dart';

/// 识别结果类型
enum SourceDetectType {
  legado,
  legadoRss,
  tvbox,
  venera,
  veneraIndex,
  cssConfig,
  legadoJs,
  unknown,
}

class SourceDetectResult {
  final SourceDetectType type;
  final double confidence;

  /// 已解析出的源数据（legado / legadoRss / tvbox / cssConfig 时有值）
  final List<dynamic> sources;
  final String message;

  const SourceDetectResult(this.type, this.confidence,
      [this.sources = const [], this.message = '']);
}

class SourceDetect {
  SourceDetect._();

  static String clean(String text) {
    return text
        .replaceAll('﻿', '')
        .replaceAll(RegExp('[​‌‍‎‏]'), '')
        .trim();
  }

  static int _legadoScore(dynamic obj) {
    if (obj is! Map || obj is List) return 0;
    var score = 0;
    if (obj['bookSourceName'] != null && obj['bookSourceUrl'] != null) {
      score += 5;
    }
    for (final k in ['ruleSearch', 'ruleBookInfo', 'ruleToc', 'ruleContent', 'searchUrl']) {
      if (obj[k] != null) score += 2;
    }
    return score;
  }

  static bool _isLegadoRss(dynamic o) {
    return o is Map &&
        o['sourceName'] != null &&
        o['sourceUrl'] != null &&
        o['bookSourceUrl'] == null;
  }

  /// TVBox 视频源接口判定：含 sites 数组且站点带 api 字段
  static bool _isTvboxConfig(dynamic o) {
    if (o is! Map) return false;
    final sites = o['sites'];
    if (sites is! List || sites.isEmpty) return false;
    return sites.any((s) => s is Map && (s['api'] != null || s['url'] != null));
  }

  static bool _looksLikeCssConfig(Map obj) {
    if (obj['name'] == null || obj['url'] == null) return false;
    const selectorKeys = [
      'bookList', 'name', 'author', 'chapterList', 'selectors',
      'searchList', 'searchName', 'images', 'chapterUrl'
    ];
    var hit = 0;
    for (final k in obj.keys) {
      final v = obj[k];
      if (v is! String) continue;
      if (selectorKeys.contains(k)) hit++;
      final probe = v.replaceAll('{{keyword}}', '');
      if (probe.contains('@') ||
          probe.contains('##') ||
          probe.contains('{{') ||
          probe.contains('<js>')) {
        return false;
      }
    }
    return hit > 0 ||
        obj.keys.any((k) =>
            ['searchUrl', 'searchList', 'chapterList', 'mediaType'].contains(k));
  }

  static Map<String, String> _toCssSource(Map obj) => {
        'name': '${obj['name'] ?? ''}',
        'url': '${obj['url'] ?? ''}',
        'mediaType': '${obj['mediaType'] ?? 'novel'}',
        'searchUrl': '${obj['searchUrl'] ?? ''}',
        'searchList': '${obj['searchList'] ?? obj['bookList'] ?? ''}',
        'searchName': '${obj['searchName'] ?? obj['name2'] ?? ''}',
        'chapterList': '${obj['chapterList'] ?? ''}',
        'images': '${obj['images'] ?? ''}',
      };

  static bool _looksLikeVeneraIndex(List items) {
    return items.every((o) =>
        o is Map &&
        o['name'] != null &&
        o['url'] != null &&
        (o['filename'] != null || o['version'] != null) &&
        o['ruleSearch'] == null &&
        o['ruleBookInfo'] == null &&
        o['ruleToc'] == null &&
        o['ruleContent'] == null);
  }

  static dynamic _tryRepairJson(String text) {
    var fixed = text
        .replaceAll(RegExp(r',\s*([}\]])'), r'$1')
        .replaceAll("'", '"');
    try {
      return jsonDecode(fixed);
    } catch (_) {
      return null;
    }
  }

  /// base64 / fox:// 解压（支持 gzip 魔数）
  static String? _tryDecompress(String text) {
    var b64 = text;
    if (b64.toLowerCase().startsWith('fox://')) b64 = b64.substring(6);
    b64 = b64.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(b64) || b64.length < 64) {
      return null;
    }
    try {
      final bytes =
          base64Decode(b64.replaceAll('-', '+').replaceAll('_', '/'));
      if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        final plain = utf8.decode(GZipDecoder().decodeBytes(bytes));
        return plain;
      }
      final plain = utf8.decode(bytes);
      if (RegExp(r'^\s*[{\[]').hasMatch(plain)) return plain;
      return null;
    } catch (_) {
      return null;
    }
  }

  static SourceDetectResult _parseJsonContent(dynamic data) {
    final items = data is List ? data : [data];

    // TVBox 视频源接口
    if (data is Map && _isTvboxConfig(data)) {
      return SourceDetectResult(
          SourceDetectType.tvbox, 0.9, [data], '识别为 TVBox 视频源接口');
    }

    // Legado 书源
    final scores = items.map(_legadoScore).toList();
    var maxScore = 0;
    for (final s in scores) {
      if (s > maxScore) maxScore = s;
    }
    if (maxScore >= 7) {
      final valid = items
          .where((o) =>
              _legadoScore(o) >= 7 &&
              o is Map &&
              o['bookSourceName'] != null &&
              o['bookSourceUrl'] != null)
          .toList();
      final skipped = items.length - valid.length;
      return SourceDetectResult(
        SourceDetectType.legado,
        (0.5 + maxScore * 0.04).clamp(0, 0.99),
        valid,
        skipped > 0 ? '已跳过 $skipped 个无效书源' : '',
      );
    }

    // Legado RSS 订阅源
    if (items.isNotEmpty && items.every(_isLegadoRss)) {
      return SourceDetectResult(
          SourceDetectType.legadoRss, 0.85, items, '识别为 RSS 订阅源');
    }

    // Venera 源索引
    if (data is List && items.isNotEmpty && _looksLikeVeneraIndex(items)) {
      return SourceDetectResult(SourceDetectType.veneraIndex, 0.85, [],
          '检测到 Venera 源索引文件，请粘贴单个图源的 JS 脚本内容');
    }

    // CSS 裸选择器配置
    if (data is Map && _looksLikeCssConfig(data)) {
      return SourceDetectResult(
          SourceDetectType.cssConfig, 0.75, [_toCssSource(data)], '');
    }
    if (data is List &&
        items.isNotEmpty &&
        items.every((o) => o is Map && _looksLikeCssConfig(o))) {
      return SourceDetectResult(SourceDetectType.cssConfig, 0.7,
          items.map((o) => _toCssSource(o as Map)).toList(), '');
    }

    return SourceDetectResult(
        SourceDetectType.unknown, 0.2, [], 'JSON 格式正确，但未识别出已知书源特征');
  }

  /// 主入口：识别粘贴文本
  static SourceDetectResult detect(String text) {
    final t = clean(text);
    if (t.isEmpty) {
      return SourceDetectResult(SourceDetectType.unknown, 0, [], '内容为空');
    }

    final first = t[0];
    if (first == '{' || first == '[') {
      try {
        return _parseJsonContent(jsonDecode(t));
      } catch (e) {
        final repaired = _tryRepairJson(t);
        if (repaired != null) return _parseJsonContent(repaired);
        return SourceDetectResult(
            SourceDetectType.unknown, 0.1, [], 'JSON 内容损坏，无法解析');
      }
    }

    // Venera JS 图源脚本
    if (RegExp(r'class\s+\w+\s+extends\s+ComicSource').hasMatch(t)) {
      return SourceDetectResult(SourceDetectType.venera, 0.95);
    }
    if (RegExp(r'key\s*[=:]').hasMatch(t) &&
        RegExp(r'version\s*[=:]').hasMatch(t) &&
        RegExp(r'loadInfo|loadEp').hasMatch(t)) {
      return SourceDetectResult(SourceDetectType.venera, 0.8);
    }

    // Legado JS 片段
    if (RegExp(r'bookSourceUrl|java\.ajax').hasMatch(t)) {
      return SourceDetectResult(SourceDetectType.legadoJs, 0.7, [],
          '检测到 Legado JS 片段，这不是完整书源，请粘贴完整的书源 JSON');
    }

    // fox:// 或长 Base64 压缩格式
    if (RegExp(r'^fox://', caseSensitive: false).hasMatch(t) ||
        (RegExp(r'^[A-Za-z0-9+/=\s_-]+$').hasMatch(t) &&
            t.replaceAll(RegExp(r'\s+'), '').length > 200)) {
      final decoded = _tryDecompress(t);
      if (decoded != null) return detect(decoded);
      return SourceDetectResult(
          SourceDetectType.unknown, 0.15, [], '压缩格式无法识别，请粘贴原始书源文本');
    }

    return SourceDetectResult(SourceDetectType.unknown, 0.1, [],
        '无法识别的书源格式，支持 Legado JSON / TVBox / Venera JS / CSS 选择器配置');
  }

  /// CSS 裸选择器配置 → Legado 书源 JSON（Legado 规则原生支持 CSS 选择器）
  static Map<String, dynamic> cssToLegado(Map<String, String> css) {
    final searchList = css['searchList'] ?? '';
    return {
      'bookSourceName': css['name'] ?? '',
      'bookSourceUrl': css['url'] ?? '',
      'bookSourceType': 0,
      'enabled': true,
      if ((css['searchUrl'] ?? '').isNotEmpty) 'searchUrl': css['searchUrl'],
      'ruleSearch': {
        'bookList': searchList,
        'name': css['searchName'] ?? '',
        if ((css['chapterUrl'] ?? '').isNotEmpty) 'bookUrl': css['chapterUrl'],
      },
      'ruleToc': {
        'chapterList': css['chapterList'] ?? '',
      },
      'ruleContent': {
        'content': css['images'] ?? '',
      },
    };
  }
}

/// 书源 URL 智能解析（移植自网页版 js/source-url-resolver.js）
///
/// 从任意粘贴串中提取 URL 并生成候选（原样 / .html 截断 /
/// yckceo 源仓库模式 / 路径逐级截断），JSON 候选优先，最多 8 个。
class SourceUrlResolver {
  SourceUrlResolver._();

  static final _urlRe = RegExp(
      'https?://(?:(?!https?://)[^\\s"\'<>，。；、）)】])+',
      caseSensitive: false);
  static final _trailPunctRe = RegExp('[，。；、：！？）)】"\'\\s]+\$');

  static List<String> split(String text) {
    final out = <String>[];
    for (final m in _urlRe.allMatches(text)) {
      final u = m.group(0)!.replaceAll(_trailPunctRe, '');
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }
    return out;
  }

  static List<String> expand(String url, [String? context]) {
    final out = <String>[];
    void add(String u) {
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }

    url = url.trim();
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) return out;
    final full = context ?? url;

    add(url);

    // '.html' 后粘连内容 → 截断为页面 URL
    final htmlIdx = url.toLowerCase().indexOf('.html');
    if (htmlIdx > -1) {
      final after = url.substring(htmlIdx + 5);
      if (after.isNotEmpty && !RegExp(r'^[?#]').hasMatch(after)) {
        add(url.substring(0, htmlIdx + 5));
      }
    }

    Uri? parsed;
    try {
      parsed = Uri.parse(url);
    } catch (_) {}

    // yckceo.com 源仓库模式：从全串提取 id 生成书源/RSS JSON 候选
    if (parsed != null &&
        parsed.host.toLowerCase().contains('yckceo.com') &&
        parsed.path.contains('/yuedu/')) {
      final idm = RegExp(r'id/(\d+)').firstMatch(full);
      if (idm != null) {
        add('https://www.yckceo.com/yuedu/shuyuan/json/id/${idm.group(1)}.json');
        add('https://www.yckceo.com/yuedu/rss/json/id/${idm.group(1)}.json');
      }
    }

    // 路径逐级截断（最多 2 级）
    if (parsed != null) {
      var path = parsed.path.replaceAll(RegExp(r'/+$'), '');
      for (var lvl = 0; lvl < 2; lvl++) {
        final cut = path.lastIndexOf('/');
        if (cut <= 0) break;
        path = path.substring(0, cut);
        add('${parsed.scheme}://${parsed.host}${parsed.hasPort ? ':${parsed.port}' : ''}$path/');
      }
    }
    return out;
  }

  /// split + expand 汇总去重，JSON 候选优先，最多 8 个
  static List<String> candidates(String text) {
    final urls = split(text);
    final seen = <String>[];
    for (final u in urls) {
      for (final c in expand(u, text)) {
        if (!seen.contains(c)) seen.add(c);
      }
    }
    bool jsonish(String u) =>
        RegExp(r'\.json($|[?#])', caseSensitive: false).hasMatch(u) ||
        RegExp(r'/json/', caseSensitive: false).hasMatch(u);
    final js = seen.where(jsonish).toList();
    final rest = seen.where((u) => !jsonish(u)).toList();
    return [...js, ...rest].take(8).toList();
  }
}
