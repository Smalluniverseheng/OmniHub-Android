/// Legado-Tauri 书源引擎
///
/// 支持 legado-tauri（docs.legadoteam.org）JS 书源：
/// 头部 `// @name/@type/...` 注释 + async search/bookInfo/chapterList/
/// chapterContent/explore 函数。通过独立的 QuickJS 运行时执行，
/// 为书源提供 legado.http / legado.dom / legado.log 等宿主 API。
/// 覆盖小说 / 漫画 / 视频 / 音乐 / 网页 五种类型。
library tauri_engine;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlparser;

import 'book_source.dart';

/// Tauri 书源元数据（来自 // @ 头注释）
class TauriSourceMeta {
  final String uuid;
  final String name;
  final String version;
  final String author;
  final String url;
  final String type; // novel|comic|video|music|webpage
  final String logo;
  final String tags;
  final String description;

  const TauriSourceMeta({
    this.uuid = '',
    required this.name,
    this.version = '',
    this.author = '',
    this.url = '',
    this.type = 'novel',
    this.logo = '',
    this.tags = '',
    this.description = '',
  });

  /// 快速判断一段文本是否是 Tauri JS 书源
  static bool looksLike(String text) {
    final t = text.trimLeft();
    if (!RegExp(r'^//\s*@name\s+\S', multiLine: true).hasMatch(t)) {
      return false;
    }
    return RegExp(r'function\s+(search|explore|bookInfo|chapterList|chapterContent)\s*\(')
            .hasMatch(t) ||
        RegExp(r'^//\s*@type\s+\S', multiLine: true).hasMatch(t);
  }

  static const _typeAlias = {
    'novel': 'novel', '小说': 'novel', 'text': 'novel',
    'comic': 'comic', '漫画': 'comic', 'image': 'comic', '图片': 'comic',
    'video': 'video', '视频': 'video', '影视': 'video',
    'music': 'music', '音乐': 'music', '音频': 'music', '有声': 'music',
    'webpage': 'webpage', 'web': 'webpage', '网页': 'webpage',
  };

  static String _header(String text, String key) {
    final m = RegExp('^//\\s*@$key\\s+(.+?)\$', multiLine: true).firstMatch(text);
    return m?.group(1)?.trim() ?? '';
  }

  static TauriSourceMeta? parse(String text) {
    if (!looksLike(text)) return null;
    final rawType = _header(text, 'type');
    return TauriSourceMeta(
      uuid: _header(text, 'uuid'),
      name: _header(text, 'name'),
      version: _header(text, 'version'),
      author: _header(text, 'author'),
      url: _header(text, 'url'),
      type: _typeAlias[rawType.toLowerCase()] ?? _typeAlias[rawType] ?? 'novel',
      logo: _header(text, 'logo'),
      tags: _header(text, 'tags'),
      description: _header(text, 'description'),
    );
  }
}

/// Tauri 书源 JS 运行时（独立 QuickJS 实例，与 venera JsEngine 隔离）
class TauriEngine {
  TauriEngine._();
  static final TauriEngine instance = TauriEngine._();

  FlutterQjs? _engine;
  bool _initing = false;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.plain,
    responseDecoder: _decodeResponse,
    validateStatus: (_) => true,
  ));

  /// 按响应声明的编码解码（中文站常见 GBK/GB2312/GB18030）
  static String _decodeResponse(
      List<int> bytes, RequestOptions options, ResponseBody responseBody) {
    var charset = '';
    final ct = responseBody.headers['content-type']?.join(';') ?? '';
    final m = RegExp(r'charset=["\x27]?\s*([\w-]+)', caseSensitive: false)
        .firstMatch(ct);
    if (m != null) charset = m.group(1)!.toLowerCase();
    if (charset.isEmpty && bytes.isNotEmpty) {
      final headLen = bytes.length < 4096 ? bytes.length : 4096;
      final head = latin1.decode(bytes.sublist(0, headLen));
      final mm = RegExp(r'<meta[^>]+charset=["\x27]?\s*([\w-]+)',
              caseSensitive: false)
          .firstMatch(head);
      if (mm != null) charset = mm.group(1)!.toLowerCase();
    }
    if (charset.startsWith('gb')) {
      try {
        return const GbkCodec().decode(bytes);
      } catch (_) {}
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      try {
        return const GbkCodec().decode(bytes);
      } catch (_) {}
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 解析后的 DOM 句柄池
  final Map<int, Object> _domHandles = {}; // int -> Document|Element
  int _nextHandle = 1;

  static const String _initJs = r'''
var legado = {
  log: function(msg) { sendMessage({api:'legado',method:'log',msg:String(msg)}); },
  toast: function(msg) { sendMessage({api:'legado',method:'log',msg:'[toast] '+String(msg)}); },
  http: {
    get: function(url, opts) {
      return sendMessage({api:'legado',method:'http',http_method:'GET',url:String(url),headers:(opts&&opts.headers)||{}});
    },
    post: function(url, body, opts) {
      return sendMessage({api:'legado',method:'http',http_method:'POST',url:String(url),body:body,headers:(opts&&opts.headers)||{}});
    }
  },
  dom: {
    parse: function(html) { return sendMessage({api:'legado',method:'dom_parse',html:String(html)}); },
    selectAll: function(h, q) { return sendMessage({api:'legado',method:'dom_selectAll',handle:h,query:String(q)}); },
    select: function(h, q) { return sendMessage({api:'legado',method:'dom_select',handle:h,query:String(q)}); },
    text: function(h) { return sendMessage({api:'legado',method:'dom_text',handle:h}); },
    attr: function(h, name) { return sendMessage({api:'legado',method:'dom_attr',handle:h,name:String(name)}); },
    selectText: function(h, q) { return sendMessage({api:'legado',method:'dom_selectText',handle:h,query:String(q)}); },
    selectAttr: function(h, q, name) { return sendMessage({api:'legado',method:'dom_selectAttr',handle:h,query:String(q),name:String(name)}); },
    selectAllTexts: function(h, q) { return sendMessage({api:'legado',method:'dom_selectAllTexts',handle:h,query:String(q)}); },
    selectAllAttrs: function(h, q, name) { return sendMessage({api:'legado',method:'dom_selectAllAttrs',handle:h,query:String(q),name:String(name)}); },
    selectByText: function(h, text) { return sendMessage({api:'legado',method:'dom_selectByText',handle:h,text:String(text)}); },
    remove: function(h) { return sendMessage({api:'legado',method:'dom_remove',handle:h}); },
    free: function(h) { sendMessage({api:'legado',method:'dom_free',handle:h}); }
  },
  urlEncodeCharset: function(str, charset) { return sendMessage({api:'legado',method:'url_encode',str:String(str),charset:String(charset||'utf8')}); },
  base64Encode: function(str) { return sendMessage({api:'legado',method:'base64',isEncode:true,str:String(str)}); },
  base64Decode: function(str) { return sendMessage({api:'legado',method:'base64',isEncode:false,str:String(str)}); }
};
function __tauri_call(src, fn, args) {
  (0, eval)(src);
  var f = this[fn];
  if (typeof f !== 'function') throw new Error('书源缺少函数 ' + fn + '()');
  var r = f.apply(null, args);
  return Promise.resolve(r).then(function(v){ return JSON.stringify(v === undefined ? null : v); });
}
''';

  Future<void> ensureInit() async {
    if (_engine != null) return;
    if (_initing) {
      while (_initing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    _initing = true;
    try {
      final e = FlutterQjs();
      e.dispatch();
      final setGlobal =
          e.evaluate("(key, value) => { this[key] = value; }");
      (setGlobal as JSInvokable)(["sendMessage", _onMessage]);
      setGlobal.free();
      e.evaluate(_initJs, name: '<tauri-init>');
      _engine = e;
    } finally {
      _initing = false;
    }
  }

  // ---------------- 宿主 API ----------------

  Object? _onMessage(dynamic message) {
    try {
      if (message is! Map) return null;
      final m = Map<String, dynamic>.from(message);
      if (m['api'] != 'legado') return null;
      switch (m['method']) {
        case 'log':
          debugPrint('[TauriSource] ${m['msg']}');
          return null;
        case 'http':
          return _http(m);
        case 'url_encode':
          return _urlEncode((m['str'] ?? '').toString(), (m['charset'] ?? 'utf8').toString());
        case 'base64':
          final s = (m['str'] ?? '').toString();
          return m['isEncode'] == true ? base64Encode(utf8.encode(s)) : utf8.decode(base64Decode(s), allowMalformed: true);
        default:
          return _domApi(m);
      }
    } catch (e) {
      debugPrint('[TauriEngine] message error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _http(Map<String, dynamic> req) async {
    try {
      final headers = Map<String, dynamic>.from(req['headers'] ?? {});
      headers.putIfAbsent('User-Agent',
          () => 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36');
      final resp = await _dio.request(
        (req['url'] ?? '').toString(),
        data: req['body'],
        options: Options(method: (req['http_method'] ?? 'GET').toString(), headers: headers),
      );
      final data = resp.data;
      return {'status': resp.statusCode, 'body': data is String ? data : data?.toString() ?? '', 'error': null};
    } catch (e) {
      return {'status': null, 'body': '', 'error': e.toString()};
    }
  }

  String _urlEncode(String s, String charset) {
    List<int> bytes;
    if (charset.toLowerCase().startsWith('gb')) {
      bytes = const GbkEncoder().convert(s);
    } else {
      bytes = utf8.encode(s);
    }
    final sb = StringBuffer();
    for (final b in bytes) {
      final c = String.fromCharCode(b);
      if (RegExp(r'[A-Za-z0-9\-_.~]').hasMatch(c)) {
        sb.write(c);
      } else {
        sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return sb.toString();
  }

  // ---------------- DOM 宿主 API ----------------

  int _keep(Object o) {
    if (_domHandles.length > 200) {
      _domHandles.remove(_domHandles.keys.first);
    }
    final k = _nextHandle++;
    _domHandles[k] = o;
    return k;
  }

  List<dom.Element> _query(Object root, String q) {
    if (root is dom.Document) return root.querySelectorAll(q);
    if (root is dom.Element) return root.querySelectorAll(q);
    return const [];
  }

  Object? _domApi(Map<String, dynamic> m) {
    switch (m['method']) {
      case 'dom_parse':
        return _keep(htmlparser.parse((m['html'] ?? '').toString()));
      case 'dom_selectAll':
        final root = _domHandles[m['handle']];
        if (root == null) return <int>[];
        return _query(root, (m['query'] ?? '').toString()).map(_keep).toList();
      case 'dom_select':
        final root = _domHandles[m['handle']];
        if (root == null) return null;
        final list = _query(root, (m['query'] ?? '').toString());
        return list.isEmpty ? null : _keep(list.first);
      case 'dom_text':
        final o = _domHandles[m['handle']];
        if (o is dom.Document) return o.body?.text ?? '';
        if (o is dom.Element) return o.text;
        return '';
      case 'dom_attr':
        final o = _domHandles[m['handle']];
        if (o is dom.Element) return o.attributes[(m['name'] ?? '').toString()] ?? '';
        return '';
      case 'dom_selectText':
        final root = _domHandles[m['handle']];
        if (root == null) return '';
        final list = _query(root, (m['query'] ?? '').toString());
        return list.isEmpty ? '' : list.first.text;
      case 'dom_selectAttr':
        final root = _domHandles[m['handle']];
        if (root == null) return '';
        final list = _query(root, (m['query'] ?? '').toString());
        return list.isEmpty ? '' : (list.first.attributes[(m['name'] ?? '').toString()] ?? '');
      case 'dom_selectAllTexts':
        final root = _domHandles[m['handle']];
        if (root == null) return <String>[];
        return _query(root, (m['query'] ?? '').toString()).map((e) => e.text).toList();
      case 'dom_selectAllAttrs':
        final root = _domHandles[m['handle']];
        if (root == null) return <String>[];
        return _query(root, (m['query'] ?? '').toString())
            .map((e) => e.attributes[(m['name'] ?? '').toString()] ?? '')
            .toList();
      case 'dom_selectByText':
        final root = _domHandles[m['handle']];
        if (root == null) return null;
        final needle = (m['text'] ?? '').toString();
        for (final e in _query(root, 'a,option,li,span,div')) {
          if (e.text.trim().contains(needle)) return _keep(e);
        }
        return null;
      case 'dom_remove':
        final o = _domHandles[m['handle']];
        if (o is dom.Element) {
          final html = o.outerHtml;
          o.remove();
          return html;
        }
        return '';
      case 'dom_free':
        _domHandles.remove(m['handle']);
        return null;
    }
    return null;
  }

  // ---------------- 书源调用 ----------------

  /// 调用书源函数，返回 JSON 解码后的结果
  Future<dynamic> call(BookSource src, String fn, List<dynamic> args) async {
    await ensureInit();
    final code = src.jsCode!;
    final result = _engine!.evaluate(
      '__tauri_call(${jsonEncode(code)}, ${jsonEncode(fn)}, ${jsonEncode(args)})',
      name: '<tauri:${src.bookSourceName}>',
    );
    // async 函数 → Dart Future（JS Promise）
    dynamic resolved = result;
    if (result is Future) resolved = await result;
    if (resolved == null) return null;
    try {
      return jsonDecode(resolved.toString());
    } catch (_) {
      return resolved.toString();
    }
  }

  List<NovelBook> _toBooks(dynamic list, BookSource src, String mediaType) {
    if (list is! List) return const [];
    final books = <NovelBook>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final name = (m['name'] ?? '').toString();
      final url = (m['bookUrl'] ?? m['url'] ?? '').toString();
      if (name.isEmpty || url.isEmpty) continue;
      books.add(NovelBook(
        name: name,
        author: (m['author'] ?? '').toString(),
        intro: (m['intro'] ?? m['description'] ?? '').toString(),
        cover: (m['coverUrl'] ?? m['cover'] ?? '').toString(),
        lastChapter: (m['latestChapter'] ?? m['lastChapter'] ?? '').toString(),
        url: url,
        tocUrl: (m['tocUrl'] ?? '').toString(),
        sourceName: src.bookSourceName,
        mediaType: mediaType,
        wordCount: (m['wordCount'] ?? '').toString(),
        kind: (m['kind'] ?? m['category'] ?? '').toString(),
      ));
    }
    return books;
  }

  Future<List<NovelBook>> search(BookSource src, String keyword, int page, String mediaType) async {
    final r = await call(src, 'search', [keyword, page]);
    return _toBooks(r, src, mediaType);
  }

  Future<List<NovelBook>> explore(BookSource src, String category, int page, String mediaType) async {
    final r = await call(src, 'explore', [category, page]);
    return _toBooks(r, src, mediaType);
  }

  /// 网页型书源：获取分类列表（explore('GETALL') 返回字符串数组）
  Future<List<String>> exploreCategories(BookSource src) async {
    final r = await call(src, 'explore', ['GETALL', 1]);
    if (r is List) return r.map((e) => e.toString()).toList();
    return const [];
  }

  /// 网页型书源原始 explore 结果（可能是 url 字符串 / {type,url,html} / 分类数组）
  Future<dynamic> exploreRaw(BookSource src, String category) async {
    return call(src, 'explore', [category, 1]);
  }

  Future<NovelBook> bookInfo(BookSource src, NovelBook book) async {
    final r = await call(src, 'bookInfo', [book.url]);
    if (r is! Map) return book;
    final m = Map<String, dynamic>.from(r);
    return book.copyWith(
      name: (m['name'] ?? '').toString().isNotEmpty ? m['name'].toString() : book.name,
      author: (m['author'] ?? book.author).toString(),
      intro: (m['intro'] ?? m['description'] ?? book.intro).toString(),
      cover: (m['coverUrl'] ?? m['cover'] ?? book.cover).toString(),
      lastChapter: (m['latestChapter'] ?? m['lastChapter'] ?? book.lastChapter).toString(),
      tocUrl: (m['tocUrl'] ?? book.tocUrl).toString(),
      wordCount: (m['wordCount'] ?? book.wordCount).toString(),
      kind: (m['kind'] ?? m['category'] ?? book.kind).toString(),
    );
  }

  Future<List<NovelChapter>> chapterList(BookSource src, String tocUrl) async {
    final r = await call(src, 'chapterList', [tocUrl]);
    if (r is! List) return const [];
    final chapters = <NovelChapter>[];
    for (final e in r) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final name = (m['name'] ?? '').toString();
      final url = (m['url'] ?? '').toString();
      if (name.isEmpty) continue;
      chapters.add(NovelChapter(name, url, isVolume: m['group'] != null && m['group'] != false && url.isEmpty));
    }
    return chapters;
  }

  Future<NovelContent> chapterContent(BookSource src, NovelChapter chapter, String mediaType) async {
    final r = await call(src, 'chapterContent', [chapter.url]);
    if (r == null) return const NovelContent.text('');
    if (mediaType == 'comic') {
      // 漫画：返回图片数组或 JSON 数组字符串
      if (r is List) {
        return NovelContent.images(r.map((e) => e.toString()).toList());
      }
      final s = r.toString();
      try {
        final j = jsonDecode(s);
        if (j is List) return NovelContent.images(j.map((e) => e.toString()).toList());
      } catch (_) {}
      if (s.isNotEmpty) return NovelContent.images([s]);
      return const NovelContent.images([]);
    }
    if (mediaType == 'video' || mediaType == 'music') {
      // 视频/音乐：url 字符串 / {url,headers,qualities} / m3u8 文本 / {m3u8Content}
      if (r is Map) {
        final m = Map<String, dynamic>.from(r);
        if (m['m3u8Content'] != null) {
          return NovelContent.video(m['m3u8Content'].toString(), isM3u8Content: true);
        }
        return NovelContent.video(
          (m['url'] ?? '').toString(),
          headers: m['headers'] is Map ? Map<String, String>.from((m['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))) : null,
        );
      }
      final s = r.toString();
      if (s.trimLeft().startsWith('#EXTM3U')) {
        return NovelContent.video(s, isM3u8Content: true);
      }
      if (s.trimLeft().startsWith('{')) {
        try {
          final m = Map<String, dynamic>.from(jsonDecode(s));
          if (m['m3u8Content'] != null) {
            return NovelContent.video(m['m3u8Content'].toString(), isM3u8Content: true);
          }
          return NovelContent.video(
            (m['url'] ?? '').toString(),
            headers: m['headers'] is Map ? Map<String, String>.from((m['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))) : null,
          );
        } catch (_) {}
      }
      return NovelContent.video(s);
    }
    return NovelContent.text(r.toString());
  }
}
