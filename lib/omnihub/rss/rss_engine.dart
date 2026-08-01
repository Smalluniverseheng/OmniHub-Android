/// RSS 抓取引擎：分类解析 / 文章列表 / 正文提取
library rss_engine;

import 'dart:convert';

import '../novel/legado_engine.dart';
import 'rss_source.dart';

class RssEngine {
  RssEngine._();

  /// 解析分类（sortUrl）：支持 "名称::URL" 用 && 或换行分隔，
  /// 以及 <js>…</js> / @js: 动态生成分类；singleUrl 或无 sortUrl 时直接用 sourceUrl
  static List<(String, String)> categories(RssSource src) {
    if (src.singleUrl || (src.sortUrl ?? '').trim().isEmpty) {
      return [(src.sourceName, src.sourceUrl)];
    }
    final raw = src.sortUrl!.trim();
    final pseudo = src.toPseudoBookSource();
    if (raw.startsWith('<js>') || raw.startsWith('@js:')) {
      var code = raw;
      if (code.startsWith('@js:')) code = code.substring(4);
      if (code.startsWith('<js>')) code = code.substring(4, code.length - 5);
      final v = LegadoEngine.runJs(
          code, '', EvalContext(baseUrl: src.sourceUrl, source: pseudo));
      final out = <(String, String)>[];
      try {
        final parsed = jsonDecode(v.toString());
        if (parsed is List) {
          for (final it in parsed) {
            if (it is Map) {
              final title = (it['title'] ?? it['name'] ?? '').toString();
              final url = (it['url'] ?? '').toString();
              if (title.isNotEmpty && url.isNotEmpty) out.add((title, url));
            }
          }
        }
      } catch (_) {}
      if (out.isEmpty) out.add((src.sourceName, src.sourceUrl));
      return out;
    }
    final out = <(String, String)>[];
    for (final part in raw.split(RegExp(r'\n|&&'))) {
      var p = LegadoEngine.trim(part);
      if (p.isEmpty) continue;
      // 去掉 legado 地址尾部附加参数 ,{"webView":...}
      final comma = p.indexOf(',{');
      if (comma > 0 && p.endsWith('}')) p = p.substring(0, comma).trim();
      final idx = p.indexOf('::');
      if (idx > 0) {
        out.add((LegadoEngine.trim(p.substring(0, idx)),
            LegadoEngine.trim(p.substring(idx + 2))));
      } else {
        out.add((src.sourceName, p));
      }
    }
    return out.isEmpty ? [(src.sourceName, src.sourceUrl)] : out;
  }

  static bool _looksLikeXml(String t) {
    final head = t.length > 400 ? t.substring(0, 400) : t;
    return RegExp(r'<(rss|rdf|feed|channel)[\s>]', caseSensitive: false)
        .hasMatch(head);
  }

  /* ---------------- XML 解析（RSS 2.0 / Atom，正则轻量实现） ---------------- */

  static String _tagText(String block, String tag) {
    final m = RegExp('<$tag(?:\\s[^>]*)?>([\\s\\S]*?)</$tag>',
            caseSensitive: false)
        .firstMatch(block);
    if (m == null) return '';
    var s = m.group(1) ?? '';
    final cd = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(s);
    if (cd != null) return cd.group(1)!.trim();
    return LegadoEngine.decodeEntities(
        s.replaceAll(RegExp(r'<[^>]+>'), '').trim());
  }

  static String _tagHtml(String block, String tag) {
    final m = RegExp('<$tag(?:\\s[^>]*)?>([\\s\\S]*?)</$tag>',
            caseSensitive: false)
        .firstMatch(block);
    if (m == null) return '';
    var s = m.group(1) ?? '';
    final cd = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(s);
    if (cd != null) return cd.group(1)!.trim();
    return s.trim();
  }

  static List<RssArticle> _parseRssXml(String text, String baseUrl) {
    final out = <RssArticle>[];
    final items = RegExp(r'<item[\s>][\s\S]*?</item>', caseSensitive: false)
        .allMatches(text)
        .map((m) => m.group(0)!);
    for (final it in items) {
      final a = RssArticle(
        title: _tagText(it, 'title'),
        description: _tagText(it, 'description'),
        author: _tagText(it, 'author').isNotEmpty
            ? _tagText(it, 'author')
            : _tagText(it, 'dc:creator'),
        date: _tagText(it, 'pubDate').isNotEmpty
            ? _tagText(it, 'pubDate')
            : _tagText(it, 'dc:date'),
        bodyHtml: _tagHtml(it, 'content:encoded'),
      );
      var link = _tagText(it, 'link');
      if (link.isEmpty) {
        final guid = _tagText(it, 'guid');
        if (RegExp(r'^https?:', caseSensitive: false).hasMatch(guid)) {
          link = guid;
        }
      }
      a.link = LegadoEngine.absUrl(link, baseUrl);
      // 图片：enclosure / media:content / media:thumbnail / description 内 img
      final enc = RegExp(r'<enclosure[^>]*url="([^"]+)"[^>]*>',
              caseSensitive: false)
          .firstMatch(it);
      if (enc != null &&
          RegExp(r'type="image', caseSensitive: false)
              .hasMatch(enc.group(0)!)) {
        a.image = LegadoEngine.absUrl(enc.group(1)!, baseUrl);
      }
      if (a.image.isEmpty) {
        final media = RegExp(
                r'<media:(?:content|thumbnail)[^>]*url="([^"]+)"',
                caseSensitive: false)
            .firstMatch(it);
        if (media != null) {
          a.image = LegadoEngine.absUrl(media.group(1)!, baseUrl);
        }
      }
      if (a.image.isEmpty) {
        final img = RegExp(r'<img[^>]*src="([^"]+)"', caseSensitive: false)
            .firstMatch(_tagHtml(it, 'description'));
        if (img != null) {
          a.image = LegadoEngine.absUrl(img.group(1)!, baseUrl);
        }
      }
      if (a.title.isNotEmpty || a.link.isNotEmpty) out.add(a);
    }
    return out;
  }

  static List<RssArticle> _parseAtomXml(String text, String baseUrl) {
    final out = <RssArticle>[];
    final entries = RegExp(r'<entry[\s>][\s\S]*?</entry>', caseSensitive: false)
        .allMatches(text)
        .map((m) => m.group(0)!);
    for (final e in entries) {
      final a = RssArticle(
        title: _tagText(e, 'title'),
        description: _tagText(e, 'summary').isNotEmpty
            ? _tagText(e, 'summary')
            : _tagText(e, 'content'),
        author: _tagText(e, 'name'),
        date: _tagText(e, 'published').isNotEmpty
            ? _tagText(e, 'published')
            : _tagText(e, 'updated'),
        bodyHtml: _tagHtml(e, 'content'),
      );
      final link = RegExp(r'<link[^>]*href="([^"]+)"', caseSensitive: false)
          .firstMatch(e);
      if (link != null) {
        a.link = LegadoEngine.absUrl(link.group(1)!, baseUrl);
      }
      if (a.title.isNotEmpty || a.link.isNotEmpty) out.add(a);
    }
    return out;
  }

  /* ---------------- 文章列表 ---------------- */

  /// 抓取某个分类地址的文章列表
  static Future<List<RssArticle>> fetchArticles(RssSource src, String url,
      {int page = 1}) async {
    final pseudo = src.toPseudoBookSource();
    var target = url
        .replaceAll('{{page}}', '$page')
        .replaceAll('{{page-1}}', '${page - 1}');
    if (target.startsWith('<js>') || target.startsWith('@js:')) {
      var code = target;
      if (code.startsWith('@js:')) code = code.substring(4);
      if (code.startsWith('<js>')) code = code.substring(4, code.length - 5);
      target = LegadoEngine.runJs(
              code, '', EvalContext(baseUrl: src.sourceUrl, source: pseudo),
              vars: {'page': page})
          .toString();
    }
    target = LegadoEngine.absUrl(target, src.sourceUrl);
    final resp = await LegadoEngine.fetchText(target, src: pseudo);
    final text = resp.text ?? '';

    // XML 订阅源：直接解析（无 articleList 规则时优先）
    if (_looksLikeXml(text)) {
      final out = RegExp(r'<feed[\s>]', caseSensitive: false).hasMatch(text)
          ? _parseAtomXml(text, target)
          : _parseRssXml(text, target);
      if (out.isNotEmpty || src.articleList == null) return out;
    }

    // HTML/JSON 页面：走 Legado 规则
    if (src.articleList == null) {
      throw Exception(
          '订阅源「${src.sourceName}」既不是标准 RSS/Atom，也未配置文章列表规则');
    }
    await LegadoEngine.prefetchAjax(src.articleList, resp, src: pseudo);
    final items = LegadoEngine.evalItems(src.articleList, resp);
    final out = <RssArticle>[];
    for (final ictx in items) {
      try {
        final a = RssArticle(
          title: LegadoEngine.decodeEntities(
              LegadoEngine.evalRule(src.ruleTitle, ictx, false).toString()),
          author: LegadoEngine.decodeEntities(
              LegadoEngine.evalRule(src.ruleAuthor, ictx, false).toString()),
          date: LegadoEngine.decodeEntities(
              LegadoEngine.evalRule(src.ruleDate, ictx, false).toString()),
          description: LegadoEngine.decodeEntities(
              LegadoEngine.evalRule(src.ruleDescription, ictx, false)
                  .toString()),
        );
        var link = LegadoEngine.evalRule(src.ruleLink, ictx, false).toString();
        if (link.isEmpty && ictx.element != null) {
          final href = ictx.element!.attributes['href'] ?? '';
          if (href.isNotEmpty) link = href;
        }
        a.link = LegadoEngine.absUrl(link, target);
        a.image = LegadoEngine.absUrl(
            LegadoEngine.evalRule(src.ruleImage, ictx, false).toString(),
            target);
        if (a.title.isNotEmpty || a.link.isNotEmpty) out.add(a);
      } catch (_) {}
    }
    return out;
  }

  /* ---------------- 正文 ---------------- */

  static String _applyWhiteBlack(String html, RssSource src) {
    var s = html;
    final w = src.contentWhitelist;
    if (w != null && w.isNotEmpty) {
      try {
        final ms = RegExp(w).allMatches(s).map((m) => m.group(0)!).join();
        if (ms.isNotEmpty) s = ms;
      } catch (_) {}
    }
    final b = src.contentBlacklist;
    if (b != null && b.isNotEmpty) {
      try {
        s = s.replaceAll(RegExp(b), '');
      } catch (_) {}
    }
    return s;
  }

  /// 获取文章正文 HTML（优先 XML 自带正文，其次 content 规则，最后智能提取）
  static Future<String> fetchContent(RssSource src, RssArticle article) async {
    if (article.bodyHtml.trim().isNotEmpty) {
      return _applyWhiteBlack(article.bodyHtml, src);
    }
    if (article.link.isEmpty) {
      return article.description;
    }
    final pseudo = src.toPseudoBookSource();
    final resp = await LegadoEngine.fetchText(article.link, src: pseudo);

    if (src.ruleContent != null) {
      await LegadoEngine.prefetchAjax(src.ruleContent, resp, src: pseudo);
      final v = LegadoEngine.evalRule(src.ruleContent, resp, false);
      final html = v?.toString() ?? '';
      if (html.trim().isNotEmpty) return _applyWhiteBlack(html, src);
    }

    // 智能提取：文字密度最高的容器
    final doc = resp.document;
    if (doc == null) return article.description;
    final root = doc.body;
    if (root == null) return article.description;
    var best = root;
    var bestLen = 0;
    for (final el in root.querySelectorAll(
        'article,main,[class*=content],[class*=article],[class*=post],[id*=content],[id*=article]')) {
      final len = el.text.trim().length;
      if (len > bestLen) {
        bestLen = len;
        best = el;
      }
    }
    if (bestLen < 80) best = root;
    best
        .querySelectorAll(
            'script,style,nav,header,footer,iframe,form,.comment,#comment')
        .forEach((e) => e.remove());
    return _applyWhiteBlack(best.innerHtml, src);
  }

  /// 正文 HTML → 渲染块（文本段与图片按原始顺序交错）
  static List<RssBlock> htmlToBlocks(String html, String baseUrl) {
    final blocks = <RssBlock>[];
    final s = html
        .replaceAll(
            RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '');
    final imgRe = RegExp(r'<img[^>]*(?:src|data-src)="([^"]+)"[^>]*>',
        caseSensitive: false);
    var last = 0;
    for (final m in imgRe.allMatches(s)) {
      _pushText(blocks, s.substring(last, m.start));
      final url = LegadoEngine.absUrl(m.group(1)!, baseUrl);
      if (url.isNotEmpty && !url.endsWith('.svg')) {
        blocks.add(RssBlock.image(url));
      }
      last = m.end;
    }
    _pushText(blocks, s.substring(last));
    // 合并相邻文本块
    final merged = <RssBlock>[];
    for (final b in blocks) {
      if (!b.isImage && merged.isNotEmpty && !merged.last.isImage) {
        merged.last.text += '\n${b.text}';
      } else {
        merged.add(b);
      }
    }
    return merged.where((b) => b.isImage || b.text.trim().isNotEmpty).toList();
  }

  static void _pushText(List<RssBlock> blocks, String html) {
    final t = LegadoEngine.htmlToText(html);
    if (t.trim().isNotEmpty) blocks.add(RssBlock.text(t));
  }
}

/// 正文渲染块
class RssBlock {
  final bool isImage;
  String text;
  RssBlock.text(this.text) : isImage = false;
  RssBlock.image(this.text) : isImage = true;
}
