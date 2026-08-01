/// Legado RSS 订阅源（rssSource）模型、管理与抓取引擎
///
/// 兼容 gedoor/legado rssSource JSON 格式：
/// sourceName / sourceUrl / sortUrl / singleUrl / articleList / title /
/// author / date / description / link / image / content 等字段。
///
/// 抓取策略：
/// - 订阅地址返回 RSS 2.0 / Atom XML 时直接解析；
/// - 返回 HTML/JSON 且配置了 articleList 等规则时走 Legado 规则引擎。
library rss_source;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../novel/book_source.dart';

/// 单篇 RSS 文章
class RssArticle {
  String title;
  String link;
  String description;
  String author;
  String date;
  String image;

  /// XML 中自带的正文（content:encoded / atom content），非空则无需再抓正文页
  String bodyHtml;

  RssArticle({
    this.title = '',
    this.link = '',
    this.description = '',
    this.author = '',
    this.date = '',
    this.image = '',
    this.bodyHtml = '',
  });
}

/// Legado RSS 订阅源
class RssSource {
  String sourceName;
  String sourceUrl;
  String sourceGroup;
  String sourceIcon;
  bool enabled;
  String? sortUrl;
  bool singleUrl;
  String? articleList;
  String? ruleTitle;
  String? ruleAuthor;
  String? ruleDate;
  String? ruleDescription;
  String? ruleLink;
  String? ruleImage;
  String? ruleContent;
  String? contentWhitelist;
  String? contentBlacklist;
  Map<String, dynamic> raw;

  RssSource({
    required this.sourceName,
    required this.sourceUrl,
    this.sourceGroup = '',
    this.sourceIcon = '',
    this.enabled = true,
    this.sortUrl,
    this.singleUrl = false,
    this.articleList,
    this.ruleTitle,
    this.ruleAuthor,
    this.ruleDate,
    this.ruleDescription,
    this.ruleLink,
    this.ruleImage,
    this.ruleContent,
    this.contentWhitelist,
    this.contentBlacklist,
    Map<String, dynamic>? raw,
  }) : raw = raw ?? {};

  static String? _s(dynamic v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  factory RssSource.fromJson(Map<String, dynamic> j) => RssSource(
        sourceName: (j['sourceName'] ?? '').toString(),
        sourceUrl: (j['sourceUrl'] ?? '').toString(),
        sourceGroup: (j['sourceGroup'] ?? '').toString(),
        sourceIcon: (j['sourceIcon'] ?? '').toString(),
        enabled: j['enabled'] != false,
        sortUrl: _s(j['sortUrl']),
        singleUrl: j['singleUrl'] == true,
        articleList: _s(j['articleList']),
        ruleTitle: _s(j['title']),
        ruleAuthor: _s(j['author']),
        ruleDate: _s(j['date']),
        ruleDescription: _s(j['description']),
        ruleLink: _s(j['link']),
        ruleImage: _s(j['image']),
        ruleContent: _s(j['content']),
        contentWhitelist: _s(j['contentWhitelist']),
        contentBlacklist: _s(j['contentBlacklist']),
        raw: j,
      );

  Map<String, dynamic> toJson() => {
        'sourceName': sourceName,
        'sourceUrl': sourceUrl,
        if (sourceGroup.isNotEmpty) 'sourceGroup': sourceGroup,
        if (sourceIcon.isNotEmpty) 'sourceIcon': sourceIcon,
        'enabled': enabled,
        if (sortUrl != null) 'sortUrl': sortUrl,
        if (singleUrl) 'singleUrl': singleUrl,
        if (articleList != null) 'articleList': articleList,
        if (ruleTitle != null) 'title': ruleTitle,
        if (ruleAuthor != null) 'author': ruleAuthor,
        if (ruleDate != null) 'date': ruleDate,
        if (ruleDescription != null) 'description': ruleDescription,
        if (ruleLink != null) 'link': ruleLink,
        if (ruleImage != null) 'image': ruleImage,
        if (ruleContent != null) 'content': ruleContent,
        if (contentWhitelist != null) 'contentWhitelist': contentWhitelist,
        if (contentBlacklist != null) 'contentBlacklist': contentBlacklist,
      };

  /// 转为伪 BookSource，便于复用 Legado 规则引擎的 JS 上下文
  BookSource toPseudoBookSource() => BookSource(
        bookSourceName: sourceName,
        bookSourceUrl: sourceUrl,
        bookSourceGroup: sourceGroup,
        header: raw['header']?.toString(),
        raw: raw,
      );
}

/// 订阅源管理：增删改、启停、导入
class RssSourceManager extends ChangeNotifier {
  RssSourceManager._();
  static final RssSourceManager instance = RssSourceManager._();

  final List<RssSource> sources = [];
  File? _file;
  bool _loaded = false;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/omnihub_rss_sources.json');
    return _file!;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _ensureFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as List;
        sources.addAll(j.map((e) =>
            RssSource.fromJson(Map<String, dynamic>.from(e as Map))));
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final f = await _ensureFile();
    await f
        .writeAsString(jsonEncode(sources.map((e) => e.toJson()).toList()));
  }

  List<RssSource> get enabledSources =>
      sources.where((e) => e.enabled).toList();

  /// 导入 rssSource JSON（单对象或数组），返回 (导入/更新数, 跳过数)
  Future<(int, int)> importJson(String text) async {
    final j = jsonDecode(text.trim());
    final list = j is List ? j : [j];
    var count = 0;
    var skipped = 0;
    for (final e in list) {
      if (e is! Map) continue;
      final src = RssSource.fromJson(Map<String, dynamic>.from(e));
      if (src.sourceName.isEmpty || src.sourceUrl.isEmpty) continue;
      final idx = sources.indexWhere((s) =>
          s.sourceName == src.sourceName && s.sourceUrl == src.sourceUrl);
      if (idx >= 0) {
        final old = Map<String, dynamic>.from(sources[idx].toJson())
          ..remove('enabled');
        final neu = Map<String, dynamic>.from(src.toJson())
          ..remove('enabled');
        if (jsonEncode(old) == jsonEncode(neu)) {
          skipped++;
          continue;
        }
        src.enabled = sources[idx].enabled;
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
    return (count, skipped);
  }

  Future<void> toggle(RssSource src, bool enabled) async {
    src.enabled = enabled;
    await save();
    notifyListeners();
  }

  Future<void> remove(RssSource src) async {
    sources.remove(src);
    await save();
    notifyListeners();
  }
}
