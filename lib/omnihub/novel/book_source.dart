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
