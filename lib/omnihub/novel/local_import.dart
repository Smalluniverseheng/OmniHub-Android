/// 本地小说导入（TXT / EPUB 直读）
///
/// 与 Legado「本地TXT/EPUB」能力对齐：
/// - TXT：自动识别编码（UTF-8/GBK），按内置目录规则或用户导入的
///   TXT目录规则（TxtTocRule）拆分章节
/// - EPUB：解析 OPF spine 顺序 + NCX/NAV 目录标题，提取正文文本与封面
///
/// 导入后存放在 app documents/local_novels/{id}/ 下，
/// NovelBook.url = local://{id}，阅读器对该 scheme 走本地读取。
library local_novel_import;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'book_source.dart';

class LocalNovelChapter {
  final String title;
  final String text;

  const LocalNovelChapter(this.title, this.text);

  Map<String, dynamic> toJson() => {'title': title, 'text': text};

  factory LocalNovelChapter.fromJson(Map<String, dynamic> j) =>
      LocalNovelChapter((j['title'] ?? '').toString(), (j['text'] ?? '').toString());
}

class LocalNovelStore {
  LocalNovelStore._();
  static final LocalNovelStore instance = LocalNovelStore._();

  static bool isLocalUrl(String url) => url.startsWith('local://');

  static String idOf(String url) => url.substring('local://'.length);

  Future<Directory> _dirOf(String id) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/local_novels/$id');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> get _root async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/local_novels');
  }

  Future<void> save(String id, NovelBook meta, List<LocalNovelChapter> chapters,
      {List<int>? coverBytes, String coverExt = 'jpg'}) async {
    final dir = await _dirOf(id);
    await File('${dir.path}/meta.json')
        .writeAsString(jsonEncode(meta.toJson()));
    await File('${dir.path}/content.json').writeAsString(
        jsonEncode(chapters.map((e) => e.toJson()).toList()));
    if (coverBytes != null && coverBytes.isNotEmpty) {
      await File('${dir.path}/cover.$coverExt').writeAsBytes(coverBytes);
    }
  }

  Future<NovelBook?> readMeta(String id) async {
    try {
      final dir = await _dirOf(id);
      final f = File('${dir.path}/meta.json');
      if (!f.existsSync()) return null;
      return NovelBook.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 本地封面文件（不存在返回 null）
  Future<File?> coverFile(String id) async {
    final dir = await _dirOf(id);
    for (final ext in ['jpg', 'jpeg', 'png', 'webp']) {
      final f = File('${dir.path}/cover.$ext');
      if (f.existsSync()) return f;
    }
    return null;
  }

  Future<List<LocalNovelChapter>> readChapters(String id) async {
    final dir = await _dirOf(id);
    final f = File('${dir.path}/content.json');
    final list = jsonDecode(await f.readAsString()) as List;
    return list
        .map((e) => LocalNovelChapter.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> delete(String id) async {
    final dir = Directory('${(await _root).path}/$id');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

class LocalNovelImporter {
  /// 按扩展名分派导入，返回导入后的 NovelBook
  static Future<NovelBook> import(String path, {String? tocRuleRegex}) async {
    final ext = path.split('.').last.toLowerCase();
    final file = File(path);
    if (ext == 'epub') return _importEpub(file);
    return _importTxt(file, tocRuleRegex: tocRuleRegex);
  }

  static bool isSupportedNovelFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return const ['txt', 'epub'].contains(ext);
  }

  // ---------------- TXT ----------------

  static final List<RegExp> _builtinChapterPatterns = [
    RegExp(
        r'^\s*第[零〇一二三四五六七八九十百千万两\d]+[章节回卷部集篇][^\n]{0,40}$',
        multiLine: true),
    RegExp(r'^\s*(楔子|序章|序言|序|番外篇?|尾声|终章|后记)[^\n]{0,40}$',
        multiLine: true),
    RegExp(r'^\s*chapter\s+\d+[^\n]{0,40}$',
        multiLine: true, caseSensitive: false),
    RegExp(r'^\s*卷[零〇一二三四五六七八九十百千万两\d]+[^\n]{0,40}$',
        multiLine: true),
  ];

  static Future<String> decodeTextFile(File file) async {
    final bytes = await file.readAsBytes();
    try {
      return utf8.decode(bytes);
    } catch (_) {
      try {
        return const GbkCodec().decode(bytes);
      } catch (_) {
        return latin1.decode(bytes);
      }
    }
  }

  static Future<NovelBook> _importTxt(File file,
      {String? tocRuleRegex}) async {
    var text = await decodeTextFile(file);
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final name = file.uri.pathSegments.last
        .replaceAll(RegExp(r'\.(txt|text)$', caseSensitive: false), '');

    final patterns = <RegExp>[
      if (tocRuleRegex != null && tocRuleRegex.isNotEmpty)
        RegExp(tocRuleRegex, multiLine: true),
      ..._builtinChapterPatterns,
    ];

    List<LocalNovelChapter> chapters = [];
    for (final p in patterns) {
      chapters = _splitByPattern(text, p);
      if (chapters.length >= 2) break;
    }
    if (chapters.isEmpty) {
      // 无任何章节标记：按长度分节
      const chunk = 8000;
      if (text.length <= chunk) {
        chapters = [LocalNovelChapter(name, text.trim())];
      } else {
        var i = 0, n = 1;
        while (i < text.length) {
          var end = (i + chunk).clamp(0, text.length);
          final nl = text.indexOf('\n', end);
          if (nl > 0 && nl < end + 200) end = nl;
          chapters.add(LocalNovelChapter(
              '第 $n 节', text.substring(i, end).trim()));
          i = end;
          n++;
        }
      }
    }

    final id = const Uuid().v4();
    final book = NovelBook(
      name: name,
      author: '',
      intro: '本地 TXT 导入，共 ${chapters.length} 章',
      cover: '',
      lastChapter: chapters.isNotEmpty ? chapters.last.title : '',
      url: 'local://$id',
      sourceName: '本地导入',
      mediaType: 'novel',
    );
    await LocalNovelStore.instance.save(id, book, chapters);
    return book;
  }

  static List<LocalNovelChapter> _splitByPattern(String text, RegExp pattern) {
    final matches = pattern.allMatches(text).toList();
    if (matches.isEmpty) return [];
    final chapters = <LocalNovelChapter>[];
    // 第一章之前的内容（前言/简介）
    if (matches.first.start > 0) {
      final pre = text.substring(0, matches.first.start).trim();
      if (pre.isNotEmpty) {
        chapters.add(LocalNovelChapter('正文前', pre));
      }
    }
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end =
          i + 1 < matches.length ? matches[i + 1].start : text.length;
      final title = text.substring(start, matches[i].end).trim();
      final body = text.substring(matches[i].end, end).trim();
      chapters.add(LocalNovelChapter(title, body));
    }
    return chapters;
  }

  // ---------------- EPUB ----------------

  static Future<NovelBook> _importEpub(File file) async {
    final bytes = await file.readAsBytes();
    final zip = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? findFile(String suffix) {
      for (final f in zip.files) {
        if (f.name.toLowerCase() == suffix.toLowerCase()) return f;
      }
      return null;
    }

    // 1) container.xml → OPF 路径
    final container = findFile('META-INF/container.xml');
    if (container == null) throw '无效的 EPUB：缺少 container.xml';
    final containerXml = utf8.decode(container.content as List<int>);
    final opfPath = RegExp(r'full-path="([^"]+)"')
            .firstMatch(containerXml)
            ?.group(1) ??
        '';
    if (opfPath.isEmpty) throw '无效的 EPUB：找不到 OPF';
    final opfDir =
        opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/')) : '';

    ArchiveFile? findInZip(String path) {
      for (final f in zip.files) {
        if (f.name == path) return f;
      }
      // 宽松匹配（忽略大小写与前导 ./）
      final lower = path.toLowerCase();
      for (final f in zip.files) {
        if (f.name.toLowerCase() == lower) return f;
      }
      return null;
    }

    final opfFile = findInZip(opfPath);
    if (opfFile == null) throw '无效的 EPUB：缺少 $opfPath';
    final opf = utf8.decode(opfFile.content as List<int>);

    // 2) 元数据
    String meta(String tag) =>
        RegExp('<dc:$tag[^>]*>([\\s\\S]*?)</dc:$tag>')
            .firstMatch(opf)
            ?.group(1)
            ?.trim() ??
        '';
    final title = meta('title').isNotEmpty
        ? meta('title')
        : file.uri.pathSegments.last.replaceAll(RegExp(r'\.epub$'), '');
    final author = meta('creator');
    final intro = meta('description');

    // 3) manifest: id → {href, media-type, properties}
    final manifest = <String, Map<String, String>>{};
    for (final m in RegExp(r'<item\b[^>]*>').allMatches(opf)) {
      final tag = m.group(0)!;
      String attr(String name) =>
          RegExp('$name="([^"]*)"').firstMatch(tag)?.group(1) ?? '';
      final id = attr('id');
      if (id.isEmpty) continue;
      manifest[id] = {
        'href': attr('href'),
        'media-type': attr('media-type'),
        'properties': attr('properties'),
      };
    }

    // 4) spine 顺序
    final spine = <String>[];
    for (final m in RegExp(r'<itemref\b[^>]*>').allMatches(opf)) {
      final idref =
          RegExp('idref="([^"]*)"').firstMatch(m.group(0)!)?.group(1) ?? '';
      if (idref.isNotEmpty) spine.add(idref);
    }

    String resolveHref(String href) {
      var h = Uri.decodeComponent(href);
      if (opfDir.isNotEmpty && !h.startsWith('/')) h = '$opfDir/$h';
      // 规范化 ./ 与 ../
      final parts = <String>[];
      for (final p in h.split('/')) {
        if (p == '.' || p.isEmpty) continue;
        if (p == '..') {
          if (parts.isNotEmpty) parts.removeLast();
        } else {
          parts.add(p);
        }
      }
      return parts.join('/');
    }

    // 5) 目录标题：优先 EPUB3 nav，其次 NCX
    final titlesByHref = <String, String>{};
    // EPUB3 nav
    for (final e in manifest.entries) {
      if (e.value['properties']!.contains('nav')) {
        final navFile = findInZip(resolveHref(e.value['href']!));
        if (navFile != null) {
          final nav = utf8.decode(navFile.content as List<int>);
          for (final m
              in RegExp(r'<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)</a>')
                  .allMatches(nav)) {
            final href = m.group(1)!.split('#').first;
            final t = _stripTags(m.group(2)!).trim();
            if (t.isNotEmpty && !titlesByHref.containsKey(href)) {
              titlesByHref[href] = t;
            }
          }
        }
      }
    }
    // NCX
    final ncxId = RegExp(r'<spine[^>]*toc="([^"]+)"')
        .firstMatch(opf)
        ?.group(1);
    final ncxHref = manifest[ncxId]?['href'] ??
        manifest.values
            .firstWhere((v) => v['media-type'] == 'application/x-dtbncx+xml',
                orElse: () => {'href': ''})
            .value['href']!;
    if (ncxHref.isNotEmpty) {
      final ncxFile = findInZip(resolveHref(ncxHref));
      if (ncxFile != null) {
        final ncx = utf8.decode(ncxFile.content as List<int>);
        for (final m in RegExp(
                r'<navPoint[\s\S]*?<text[^>]*>([\s\S]*?)</text>[\s\S]*?<content[^>]+src="([^"]+)"')
            .allMatches(ncx)) {
          final t = _stripTags(m.group(1)!).trim();
          final href = m.group(2)!.split('#').first;
          if (t.isNotEmpty && !titlesByHref.containsKey(href)) {
            titlesByHref[href] = t;
          }
        }
      }
    }

    // 6) 提取章节
    final chapters = <LocalNovelChapter>[];
    var idx = 1;
    for (final idref in spine) {
      final item = manifest[idref];
      if (item == null) continue;
      if (!item['media-type']!.contains('html')) continue;
      if (item['properties']!.contains('nav')) continue;
      final href = item['href']!;
      final f = findInZip(resolveHref(href));
      if (f == null) continue;
      final html = utf8.decode(f.content as List<int>);
      final text = _htmlToText(html);
      if (text.trim().isEmpty) continue;
      final shortHref = href.split('#').first;
      final t = titlesByHref[shortHref] ??
          titlesByHref[Uri.decodeComponent(shortHref)] ??
          '第 $idx 章';
      chapters.add(LocalNovelChapter(t, text));
      idx++;
    }
    if (chapters.isEmpty) throw 'EPUB 中没有可读章节';

    // 7) 封面
    List<int>? coverBytes;
    String coverExt = 'jpg';
    String? coverId = RegExp(r'<meta[^>]+name="cover"[^>]+content="([^"]+)"')
        .firstMatch(opf)
        ?.group(1);
    coverId ??= manifest.entries
        .where((e) => e.value['properties']!.contains('cover-image'))
        .map((e) => e.key)
        .firstOrNull;
    final coverItem = manifest[coverId];
    if (coverItem != null) {
      final f = findInZip(resolveHref(coverItem['href']!));
      if (f != null && f.isFile) {
        coverBytes = (f.content as List<int>);
        coverExt = coverItem['href']!.split('.').last.toLowerCase();
        if (!const ['jpg', 'jpeg', 'png', 'webp'].contains(coverExt)) {
          coverExt = 'jpg';
        }
      }
    }

    final id = const Uuid().v4();
    final book = NovelBook(
      name: title,
      author: author,
      intro: intro.isNotEmpty
          ? intro
          : '本地 EPUB 导入，共 ${chapters.length} 章',
      cover: '', // 本地封面经 LocalNovelStore.coverFile 提供
      lastChapter: chapters.last.title,
      url: 'local://$id',
      sourceName: '本地导入',
      mediaType: 'novel',
    );
    await LocalNovelStore.instance
        .save(id, book, chapters, coverBytes: coverBytes, coverExt: coverExt);
    return book;
  }

  static String _stripTags(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), '');

  /// HTML → 纯文本（保留段落换行）
  static String _htmlToText(String html) {
    var s = html;
    s = s.replaceAll(
        RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), '');
    s = s.replaceAll(
        RegExp(
            r'</(p|div|h[1-6]|li|tr|section|article|blockquote|br)\s*>',
            caseSensitive: false),
        '\n');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = _stripTags(s);
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
    // 收敛空行
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }
}
