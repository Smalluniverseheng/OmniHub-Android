/// Legado（开源阅读）书源模型与管理
///
/// 兼容 gedoor/legado 书源 JSON 格式。
library book_source;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class BookSource {
  String bookSourceName;
  String bookSourceUrl;
  int bookSourceType; // 0 文本 2 图片(漫画)
  bool enabled;
  String? searchUrl;
  String? header;
  Map<String, dynamic> ruleSearch;
  Map<String, dynamic> ruleBookInfo;
  Map<String, dynamic> ruleToc;
  Map<String, dynamic> ruleContent;
  Map<String, dynamic> raw;

  BookSource({
    required this.bookSourceName,
    required this.bookSourceUrl,
    this.bookSourceType = 0,
    this.enabled = true,
    this.searchUrl,
    this.header,
    Map<String, dynamic>? ruleSearch,
    Map<String, dynamic>? ruleBookInfo,
    Map<String, dynamic>? ruleToc,
    Map<String, dynamic>? ruleContent,
    Map<String, dynamic>? raw,
  })  : ruleSearch = ruleSearch ?? {},
        ruleBookInfo = ruleBookInfo ?? {},
        ruleToc = ruleToc ?? {},
        ruleContent = ruleContent ?? {},
        raw = raw ?? {};

  String get mediaType => bookSourceType == 2 ? 'comic' : 'novel';

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};

  factory BookSource.fromJson(Map<String, dynamic> j) => BookSource(
        bookSourceName: (j['bookSourceName'] ?? '').toString(),
        bookSourceUrl: (j['bookSourceUrl'] ?? '').toString(),
        bookSourceType: (j['bookSourceType'] as num?)?.toInt() ?? 0,
        enabled: j['enabled'] != false,
        searchUrl: j['searchUrl']?.toString(),
        header: j['header']?.toString(),
        ruleSearch: _map(j['ruleSearch']),
        ruleBookInfo: _map(j['ruleBookInfo']),
        ruleToc: _map(j['ruleToc']),
        ruleContent: _map(j['ruleContent']),
        raw: j,
      );

  Map<String, dynamic> toJson() => {
        'bookSourceName': bookSourceName,
        'bookSourceUrl': bookSourceUrl,
        'bookSourceType': bookSourceType,
        'enabled': enabled,
        if (searchUrl != null) 'searchUrl': searchUrl,
        if (header != null) 'header': header,
        'ruleSearch': ruleSearch,
        'ruleBookInfo': ruleBookInfo,
        'ruleToc': ruleToc,
        'ruleContent': ruleContent,
      };
}

class NovelBook {
  final String name;
  final String author;
  final String intro;
  final String cover;
  final String lastChapter;
  final String url;
  final String tocUrl;
  final String sourceName;
  final String mediaType;

  const NovelBook({
    required this.name,
    this.author = '',
    this.intro = '',
    this.cover = '',
    this.lastChapter = '',
    required this.url,
    this.tocUrl = '',
    required this.sourceName,
    this.mediaType = 'novel',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'author': author,
        'intro': intro,
        'cover': cover,
        'lastChapter': lastChapter,
        'url': url,
        'tocUrl': tocUrl,
        'sourceName': sourceName,
        'mediaType': mediaType,
      };

  factory NovelBook.fromJson(Map<String, dynamic> j) => NovelBook(
        name: (j['name'] ?? '').toString(),
        author: (j['author'] ?? '').toString(),
        intro: (j['intro'] ?? '').toString(),
        cover: (j['cover'] ?? '').toString(),
        lastChapter: (j['lastChapter'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        tocUrl: (j['tocUrl'] ?? '').toString(),
        sourceName: (j['sourceName'] ?? '').toString(),
        mediaType: (j['mediaType'] ?? 'novel').toString(),
      );
}

class NovelChapter {
  final String name;
  final String url;
  final bool isVolume;
  const NovelChapter(this.name, this.url, {this.isVolume = false});
}

class NovelContent {
  final String type; // 'text' | 'images'
  final String text;
  final List<String> images;
  const NovelContent.text(this.text)
      : type = 'text',
        images = const [];
  const NovelContent.images(this.images)
      : type = 'images',
        text = '';
}

/// 书源管理：增删改、启停、导入（JSON 文本/文件/URL 由页面层提供文本）
class BookSourceManager extends ChangeNotifier {
  BookSourceManager._();
  static final BookSourceManager instance = BookSourceManager._();

  final List<BookSource> sources = [];
  File? _file;
  bool _loaded = false;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/omnihub_book_sources.json');
    return _file!;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _ensureFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as List;
        sources.addAll(j.map((e) => BookSource.fromJson(e)));
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final f = await _ensureFile();
    await f.writeAsString(
        jsonEncode(sources.map((e) => e.toJson()).toList()));
  }

  List<BookSource> get enabledSources =>
      sources.where((e) => e.enabled && e.searchUrl != null).toList();

  /// 导入书源 JSON（支持单对象或数组），返回导入数量
  Future<int> importJson(String text) async {
    final j = jsonDecode(text.trim());
    final list = j is List ? j : [j];
    var count = 0;
    for (final e in list) {
      if (e is! Map) continue;
      final src = BookSource.fromJson(Map<String, dynamic>.from(e));
      if (src.bookSourceName.isEmpty) continue;
      final idx = sources.indexWhere((s) =>
          s.bookSourceName == src.bookSourceName &&
          s.bookSourceUrl == src.bookSourceUrl);
      if (idx >= 0) {
        sources[idx] = src;
      } else {
        sources.add(src);
      }
      count++;
    }
    if (count > 0) {
      await save();
      notifyListeners();
    }
    return count;
  }

  Future<void> toggle(BookSource src, bool enabled) async {
    src.enabled = enabled;
    await save();
    notifyListeners();
  }

  Future<void> remove(BookSource src) async {
    sources.remove(src);
    await save();
    notifyListeners();
  }
}

/// 小说书架（与漫画书架分离，存书源书籍的 URL 引用）
class NovelShelf extends ChangeNotifier {
  NovelShelf._();
  static final NovelShelf instance = NovelShelf._();

  final List<NovelBook> books = [];
  final Map<String, int> progress = {}; // bookUrl -> chapterIndex
  File? _file;
  bool _loaded = false;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/omnihub_novel_shelf.json');
    return _file!;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _ensureFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        books.addAll(
            (j['books'] as List).map((e) => NovelBook.fromJson(e)));
        (j['progress'] as Map?)?.forEach((k, v) {
          progress[k.toString()] = (v as num).toInt();
        });
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final f = await _ensureFile();
    await f.writeAsString(jsonEncode({
      'books': books.map((e) => e.toJson()).toList(),
      'progress': progress,
    }));
  }

  bool contains(String url) => books.any((e) => e.url == url);

  Future<void> add(NovelBook b) async {
    if (contains(b.url)) return;
    books.insert(0, b);
    await save();
    notifyListeners();
  }

  Future<void> remove(String url) async {
    books.removeWhere((e) => e.url == url);
    progress.remove(url);
    await save();
    notifyListeners();
  }

  Future<void> setProgress(String url, int chapterIndex) async {
    progress[url] = chapterIndex;
    await save();
  }
}

// ==================== Legado 扩展格式 ====================

/// TXT 目录规则（legado textTocRule）
class TxtTocRule {
  String name;
  String rule; // 正则
  bool enabled;

  TxtTocRule({required this.name, required this.rule, this.enabled = true});

  Map<String, dynamic> toJson() =>
      {'name': name, 'rule': rule, 'enabled': enabled};

  factory TxtTocRule.fromJson(Map<String, dynamic> j) => TxtTocRule(
        name: (j['name'] ?? '').toString(),
        rule: (j['rule'] ?? '').toString(),
        enabled: j['enabled'] != false && j['isEnabled'] != false,
      );
}

/// 替换规则（legado replaceRule），用于正文净化
class ReplaceRule {
  String name;
  String pattern; // 正则
  String replacement;
  bool enabled;

  ReplaceRule({
    required this.name,
    required this.pattern,
    this.replacement = '',
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'pattern': pattern,
        'replacement': replacement,
        'enabled': enabled,
      };

  factory ReplaceRule.fromJson(Map<String, dynamic> j) => ReplaceRule(
        name: (j['name'] ?? '').toString(),
        pattern: (j['pattern'] ?? j['regex'] ?? '').toString(),
        replacement: (j['replacement'] ?? '').toString(),
        enabled: j['enabled'] != false && j['isEnabled'] != false,
      );
}

/// 在线朗读引擎（legado httpTTS）——导入存储，播放用内置引擎
class HttpTtsEngine {
  String name;
  String url;
  Map<String, dynamic> raw;

  HttpTtsEngine({required this.name, required this.url, Map<String, dynamic>? raw})
      : raw = raw ?? {};

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'raw': raw};

  factory HttpTtsEngine.fromJson(Map<String, dynamic> j) => HttpTtsEngine(
        name: (j['name'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        raw: j,
      );
}

/// Legado 扩展数据管理（目录规则/替换规则/朗读引擎）
class LegadoExtras extends ChangeNotifier {
  LegadoExtras._();
  static final LegadoExtras instance = LegadoExtras._();

  final List<TxtTocRule> tocRules = [];
  final List<ReplaceRule> replaceRules = [];
  final List<HttpTtsEngine> ttsEngines = [];

  File? _file;
  bool _loaded = false;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/omnihub_legado_extras.json');
    return _file!;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _ensureFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        tocRules.addAll(((j['tocRules'] ?? []) as List)
            .map((e) => TxtTocRule.fromJson(Map<String, dynamic>.from(e))));
        replaceRules.addAll(((j['replaceRules'] ?? []) as List)
            .map((e) => ReplaceRule.fromJson(Map<String, dynamic>.from(e))));
        ttsEngines.addAll(((j['ttsEngines'] ?? []) as List)
            .map((e) => HttpTtsEngine.fromJson(Map<String, dynamic>.from(e))));
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final f = await _ensureFile();
    await f.writeAsString(jsonEncode({
      'tocRules': tocRules.map((e) => e.toJson()).toList(),
      'replaceRules': replaceRules.map((e) => e.toJson()).toList(),
      'ttsEngines': ttsEngines.map((e) => e.toJson()).toList(),
    }));
  }

  /// 当前生效的 TXT 目录正则（无则返回 null，用内置规则）
  String? get activeTocRuleRegex {
    for (final r in tocRules) {
      if (r.enabled && r.rule.isNotEmpty) return r.rule;
    }
    return null;
  }

  /// 对正文应用所有启用的替换规则
  String applyReplaceRules(String text) {
    var result = text;
    for (final r in replaceRules) {
      if (!r.enabled || r.pattern.isEmpty) continue;
      try {
        result = result.replaceAll(RegExp(r.pattern), r.replacement);
      } catch (_) {
        // 跳过非法正则
      }
    }
    return result;
  }
}

/// Legado 统一导入分发：根据 legado://import/{path} 的类型导入
class LegadoImport {
  /// 从不规范文本中提取 JSON（兼容首尾巴署说明文字、base64 包裹）
  static String extractJson(String text) {
    var t = text.trim();
    // 尝试整体 base64 解码（Legado 书源常以 base64 分享）
    if (!t.startsWith('[') && !t.startsWith('{')) {
      try {
        final decoded = utf8.decode(base64Decode(t));
        if (decoded.trim().startsWith('[') ||
            decoded.trim().startsWith('{')) {
          t = decoded.trim();
        }
      } catch (_) {}
    }
    if (!t.startsWith('[') && !t.startsWith('{')) {
      final i = t.indexOf('[');
      final j = t.indexOf('{');
      var start = -1;
      if (i >= 0 && j >= 0) {
        start = i < j ? i : j;
      } else {
        start = i >= 0 ? i : j;
      }
      if (start > 0) {
        final end = t.lastIndexOf(t[start] == '[' ? ']' : '}');
        if (end > start) t = t.substring(start, end + 1);
      }
    }
    return t;
  }

  /// 按类型导入，返回 (数量, 类型说明)；不支持的类型抛出异常
  static Future<(int, String)> importByType(String type, String text) async {
    final json = extractJson(text);
    switch (type) {
      case 'bookSource':
        final n = await BookSourceManager.instance.importJson(json);
        return (n, '书源');
      case 'textTocRule':
        final j = jsonDecode(json);
        final list = j is List ? j : [j];
        var n = 0;
        for (final e in list) {
          if (e is! Map) continue;
          final r = TxtTocRule.fromJson(Map<String, dynamic>.from(e));
          if (r.rule.isEmpty) continue;
          LegadoExtras.instance.tocRules.removeWhere((x) => x.name == r.name);
          LegadoExtras.instance.tocRules.add(r);
          n++;
        }
        await LegadoExtras.instance.save();
        return (n, 'TXT目录规则');
      case 'replaceRule':
        final j = jsonDecode(json);
        final list = j is List ? j : [j];
        var n = 0;
        for (final e in list) {
          if (e is! Map) continue;
          final r = ReplaceRule.fromJson(Map<String, dynamic>.from(e));
          if (r.pattern.isEmpty) continue;
          LegadoExtras.instance.replaceRules
              .removeWhere((x) => x.name == r.name);
          LegadoExtras.instance.replaceRules.add(r);
          n++;
        }
        await LegadoExtras.instance.save();
        return (n, '替换规则');
      case 'httpTTS':
        final j = jsonDecode(json);
        final list = j is List ? j : [j];
        var n = 0;
        for (final e in list) {
          if (e is! Map) continue;
          final r = HttpTtsEngine.fromJson(Map<String, dynamic>.from(e));
          if (r.name.isEmpty) continue;
          LegadoExtras.instance.ttsEngines.removeWhere((x) => x.name == r.name);
          LegadoExtras.instance.ttsEngines.add(r);
          n++;
        }
        await LegadoExtras.instance.save();
        return (n, '朗读引擎');
      default:
        throw '暂不支持的导入类型：$type';
    }
  }
}
