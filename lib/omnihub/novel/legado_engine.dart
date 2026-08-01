/// Legado（开源阅读）书源引擎 —— Dart 移植版
///
/// 移植自网页版 js/legado-engine.js（同规则语义）：
/// 搜索 / 详情 / 目录 / 正文，规则求值支持
/// XPath（常用子集）/ JSONPath（简易）/ JSoup 简写 CSS / JS 段。
library legado_engine;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlparser;
import 'package:venera/foundation/js_engine.dart';

import 'book_source.dart';
import 'tauri_engine.dart';

class EvalContext {
  dom.Element? element; // CSS/XPath 上下文
  dom.Document? document;
  dynamic json;
  String? text;
  String baseUrl;
  Map<String, dynamic>? book;
  Map<String, dynamic>? chapter;

  EvalContext({
    this.element,
    this.document,
    this.json,
    this.text,
    this.baseUrl = '',
    this.book,
    this.chapter,
  });

  EvalContext child({
    dom.Element? element,
    dynamic json,
    String? text,
  }) =>
      EvalContext(
        element: element,
        document: document,
        json: json,
        text: text,
        baseUrl: baseUrl,
        book: book,
        chapter: chapter,
      );

  dom.Element? get root => element ?? document?.documentElement;
}

class LegadoEngine {
  LegadoEngine._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    responseType: ResponseType.plain,
    validateStatus: (s) => s != null && s < 400,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
    },
  ));

  static String trim(Object? s) => (s ?? '').toString().trim();
  static bool isNonEmpty(Object? s) => trim(s) != '';

  static String absUrl(String rel, String base) {
    rel = trim(rel);
    if (rel.isEmpty) return '';
    try {
      return Uri.parse(base).resolve(rel).toString();
    } catch (_) {
      return rel;
    }
  }

  static String decodeEntities(String? s) {
    if (s == null || s.isEmpty) return '';
    return s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'&#39;|&apos;'), "'")
        .replaceAllMapped(RegExp(r'&#(\d+);'),
            (m) => String.fromCharCode(int.parse(m.group(1)!)))
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
            (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
  }

  /* ---------------- JS 沙箱 ---------------- */

  // java stub + md5/base64（纯 JS 实现，QuickJS 无 btoa/atob）
  static const String _jsPreamble = r'''
var __legadoVars = (globalThis.__legadoVars = globalThis.__legadoVars || {});
function __b64e(s){var c='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';var o='';var i=0;var str=unescape(encodeURIComponent(String(s)));while(i<str.length){var a=str.charCodeAt(i++),b=str.charCodeAt(i++),d=str.charCodeAt(i++);var x=(isNaN(b)?0:b),y=(isNaN(d)?0:d);var n=(a<<16)|(x<<8)|y;o+=c[(n>>18)&63]+c[(n>>12)&63]+(isNaN(b)?'=':c[(n>>6)&63])+(isNaN(d)?'=':c[n&63]);}return o;}
function __b64d(s){var c='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';var o='';var i=0;s=String(s).replace(/[^A-Za-z0-9+/=]/g,'');while(i<s.length){var a=c.indexOf(s.charAt(i++)),b=c.indexOf(s.charAt(i++)),d=c.indexOf(s.charAt(i++)),e=c.indexOf(s.charAt(i++));var n=(a<<18)|(b<<12)|(d<<6)|e;o+=String.fromCharCode((n>>16)&255);if(d!=64)o+=String.fromCharCode((n>>8)&255);if(e!=64)o+=String.fromCharCode(n&255);}try{return decodeURIComponent(escape(o));}catch(_){return o;}}
function __md5cycle(x,k){var a=x[0],b=x[1],c=x[2],d=x[3];a=__ff(a,b,c,d,k[0],7,-680876936);d=__ff(d,a,b,c,k[1],12,-389564586);c=__ff(c,d,a,b,k[2],17,606105819);b=__ff(b,c,d,a,k[3],22,-1044525330);a=__ff(a,b,c,d,k[4],7,-176418897);d=__ff(d,a,b,c,k[5],12,1200080426);c=__ff(c,d,a,b,k[6],17,-1473231341);b=__ff(b,c,d,a,k[7],22,-45705983);a=__ff(a,b,c,d,k[8],7,1770035416);d=__ff(d,a,b,c,k[9],12,-1958414417);c=__ff(c,d,a,b,k[10],17,-42063);b=__ff(b,c,d,a,k[11],22,-1990404162);a=__ff(a,b,c,d,k[12],7,1804603682);d=__ff(d,a,b,c,k[13],12,-40341101);c=__ff(c,d,a,b,k[14],17,-1502002290);b=__ff(b,c,d,a,k[15],22,1236535329);a=__gg(a,b,c,d,k[1],5,-165796510);d=__gg(d,a,b,c,k[6],9,-1069501632);c=__gg(c,d,a,b,k[11],14,643717713);b=__gg(b,c,d,a,k[0],20,-373897302);a=__gg(a,b,c,d,k[5],5,-701558691);d=__gg(d,a,b,c,k[10],9,38016083);c=__gg(c,d,a,b,k[15],14,-660478335);b=__gg(b,c,d,a,k[4],20,-405537848);a=__gg(a,b,c,d,k[9],5,568446438);d=__gg(d,a,b,c,k[14],9,-1019803690);c=__gg(c,d,a,b,k[3],14,-187363961);b=__gg(b,c,d,a,k[8],20,1163531501);a=__gg(a,b,c,d,k[13],5,-1444681467);d=__gg(d,a,b,c,k[2],9,-51403784);c=__gg(c,d,a,b,k[7],14,1735328473);b=__gg(b,c,d,a,k[12],20,-1926607734);a=__hh(a,b,c,d,k[5],4,-378558);d=__hh(d,a,b,c,k[8],11,-2022574463);c=__hh(c,d,a,b,k[11],16,1839030562);b=__hh(b,c,d,a,k[14],23,-35309556);a=__hh(a,b,c,d,k[1],4,-1530992060);d=__hh(d,a,b,c,k[4],11,1272893353);c=__hh(c,d,a,b,k[7],16,-155497632);b=__hh(b,c,d,a,k[10],23,-1094730640);a=__hh(a,b,c,d,k[13],4,681279174);d=__hh(d,a,b,c,k[0],11,-358537222);c=__hh(c,d,a,b,k[3],16,-722521979);b=__hh(b,c,d,a,k[6],23,76029189);a=__hh(a,b,c,d,k[9],4,-640364487);d=__hh(d,a,b,c,k[12],11,-421815835);c=__hh(c,d,a,b,k[15],16,530742520);b=__hh(b,c,d,a,k[2],23,-995338651);a=__ii(a,b,c,d,k[0],6,-198630844);d=__ii(d,a,b,c,k[7],10,1126891415);c=__ii(c,d,a,b,k[14],15,-1416354905);b=__ii(b,c,d,a,k[5],21,-57434055);a=__ii(a,b,c,d,k[12],6,1700485571);d=__ii(d,a,b,c,k[3],10,-1894986606);c=__ii(c,d,a,b,k[10],15,-1051523);b=__ii(b,c,d,a,k[1],21,-2054922799);a=__ii(a,b,c,d,k[8],6,1873313359);d=__ii(d,a,b,c,k[15],10,-30611744);c=__ii(c,d,a,b,k[6],15,-1560198380);b=__ii(b,c,d,a,k[13],21,1309151649);a=__ii(a,b,c,d,k[4],6,-145523070);d=__ii(d,a,b,c,k[11],10,-1120210379);c=__ii(c,d,a,b,k[2],15,718787259);b=__ii(b,c,d,a,k[9],21,-343485551);x[0]=__add32(a,x[0]);x[1]=__add32(b,x[1]);x[2]=__add32(c,x[2]);x[3]=__add32(d,x[3]);}
function __cmn(q,a,b,x,s,t){a=__add32(__add32(a,q),__add32(x,t));return __add32((a<<s)|(a>>>(32-s)),b);}
function __ff(a,b,c,d,x,s,t){return __cmn((b&c)|((~b)&d),a,b,x,s,t);}
function __gg(a,b,c,d,x,s,t){return __cmn((b&d)|(c&(~d)),a,b,x,s,t);}
function __hh(a,b,c,d,x,s,t){return __cmn(b^c^d,a,b,x,s,t);}
function __ii(a,b,c,d,x,s,t){return __cmn(c^(b|(~d)),a,b,x,s,t);}
function __add32(a,b){return(a+b)|0;}
function __md5(s){var str=unescape(encodeURIComponent(String(s)));var n=str.length;var tail=[1518500249,1859775393,2400959708,3395469782];var i;var words=[];for(i=0;i<n;i++){words[i>>2]=(words[i>>2]||0)|(str.charCodeAt(i)<<((i%4)*8));}
words[n>>2]=(words[n>>2]||0)|(0x80<<((n%4)*8));var blen=((n+8)>>6)*16+16;while(words.length<blen)words.push(0);words[blen-2]=n*8;var state=[1732584193,-271733879,-1732584194,271733878];for(i=0;i<words.length;i+=16){var k=words.slice(i,i+16);while(k.length<16)k.push(0);__md5cycle(state,k);}
return state.map(function(v){var out='';for(var j=0;j<4;j++){var b=(v>>>(8*j))&255;out+=(b<16?'0':'')+b.toString(16);}return out;}).join('');}
var java = {
  put: function(k, v) { __legadoVars[k] = v; return v; },
  get: function(k) { return __legadoVars[k]; },
  ajax: function(url) { return ''; },
  md5Encode: function(s) { return __md5(s); },
  base64Decode: function(s) { return __b64d(s); },
  base64Encode: function(s) { return __b64e(s); },
  log: function() {}
};
''';

  /// 跨规则持久变量（对应 Legado 的 java.put/java.get，源级共享）
  static final Map<String, dynamic> _jsVars = {};

  /// java.ajax 预抓取缓存：URL → 响应文本
  static final Map<String, String> _ajaxCache = {};

  /// 执行 JS 段；失败降级为空字符串
  static dynamic runJs(String code, Object? result, EvalContext context) {
    try {
      final wrapper = StringBuffer()
        ..write('(function(){')
        ..write(_jsPreamble)
        ..write('__legadoVars=')
        ..write(jsonEncode(_jsVars))
        ..write(';var __ajaxCache=')
        ..write(jsonEncode(_ajaxCache))
        ..write(';java.ajax=function(u){var s=String(u);return __ajaxCache[s]||"";};')
        ..write('var result=')
        ..write(jsonEncode(result?.toString() ?? ''))
        ..write(';var book=')
        ..write(jsonEncode(context.book ?? {}))
        ..write(';var chapter=')
        ..write(jsonEncode(context.chapter ?? {}))
        ..write(';var baseUrl=')
        ..write(jsonEncode(context.baseUrl))
        ..write(';var cookie={};var cache={};var __r=eval(')
        ..write(jsonEncode(code))
        ..write(');return JSON.stringify({r:(__r===null||__r===undefined)?"":__r,v:__legadoVars});})()');
      final out = JsEngine().runCode(wrapper.toString());
      if (out is String && out.isNotEmpty) {
        try {
          final decoded = jsonDecode(out);
          if (decoded is Map) {
            // 合并 java.put 写入的变量，供后续规则读取
            if (decoded['v'] is Map) {
              (decoded['v'] as Map).forEach((k, v) {
                _jsVars[k.toString()] = v;
              });
            }
            return decoded['r'] ?? '';
          }
        } catch (_) {}
        return out;
      }
      return out ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 从规则中提取全部 JS 代码段（<js>…</js>、{{}} 模板、@js: 尾段）
  static List<String> _extractJsCodes(String rule) {
    final out = <String>[];
    for (final m in RegExp(r'<js>([\s\S]*?)</js>').allMatches(rule)) {
      out.add(m.group(1)!);
    }
    for (final m in RegExp(r'\{\{([\s\S]*?)\}\}').allMatches(rule)) {
      out.addAll(_extractJsCodes(m.group(1)!));
    }
    final noJsBlock = rule.replaceAll(RegExp(r'<js>[\s\S]*?</js>'), '');
    for (final seg in splitTop(noJsBlock, '||')) {
      for (final s2 in splitTop(seg, '&&')) {
        final i = topLevelIndexOf(s2, '@js:');
        if (i > -1) out.add(s2.substring(i + 4));
      }
    }
    return out;
  }

  /// 预抓取规则 JS 中 java.ajax(...) 的目标地址。
  ///
  /// QuickJS 是同步沙箱，无法在 JS 内直接发起异步网络请求；
  /// 这里先用“记录型 ajax 桩”跑一遍 JS 收集 URL，在 Dart 侧真实请求，
  /// 结果写入 [_ajaxCache]，正式执行时 java.ajax 同步回读缓存。
  static Future<void> prefetchAjax(dynamic ruleRaw, EvalContext ctx,
      {BookSource? src}) async {
    if (ruleRaw == null) return;
    final rule = ruleRaw.toString();
    if (!rule.contains('ajax')) return;
    final codes = _extractJsCodes(rule)
        .where((c) => c.contains('ajax'))
        .toList();
    if (codes.isEmpty) return;
    if (_ajaxCache.length > 300) _ajaxCache.clear();

    final urls = <String>{};
    for (final code in codes) {
      try {
        final wrapper = StringBuffer()
          ..write('(function(){')
          ..write(_jsPreamble)
          ..write('__legadoVars=')
          ..write(jsonEncode(_jsVars))
          ..write(';var __ajaxUrls=[];'
              'java.ajax=function(u){__ajaxUrls.push(String(u));return "";};')
          ..write('var result=')
          ..write(jsonEncode(ctx.text ?? ''))
          ..write(';var book=')
          ..write(jsonEncode(ctx.book ?? {}))
          ..write(';var chapter=')
          ..write(jsonEncode(ctx.chapter ?? {}))
          ..write(';var baseUrl=')
          ..write(jsonEncode(ctx.baseUrl))
          ..write(';var cookie={};var cache={};try{eval(')
          ..write(jsonEncode(code))
          ..write(');}catch(e){}return JSON.stringify(__ajaxUrls);})()');
        final out = JsEngine().runCode(wrapper.toString());
        if (out is String && out.isNotEmpty) {
          final arr = jsonDecode(out);
          if (arr is List) {
            for (final u in arr) {
              final s = u.toString();
              if (RegExp(r'^(https?:)?//', caseSensitive: false)
                  .hasMatch(s)) {
                urls.add(s);
              }
            }
          }
        }
      } catch (_) {}
    }

    for (final u in urls) {
      final full = absUrl(u, ctx.baseUrl);
      if (full.isEmpty || _ajaxCache.containsKey(u)) continue;
      try {
        final resp = await fetchText(full, src: src);
        _ajaxCache[u] = resp.text ?? '';
        if (full != u) _ajaxCache[full] = resp.text ?? '';
      } catch (_) {
        _ajaxCache[u] = '';
      }
    }
  }

  /* ---------------- 规则拆解辅助 ---------------- */

  /// 按顶层分隔符拆分（跳过 {{}}、<js></js> 与 ## 正则尾部）
  static List<String> splitTop(String str, String sep) {
    final parts = <String>[];
    var depth = 0, inJs = false, i = 0, start = 0;
    while (i < str.length) {
      if (!inJs && str.startsWith('<js>', i)) {
        inJs = true;
        i += 4;
        continue;
      }
      if (inJs && str.startsWith('</js>', i)) {
        inJs = false;
        i += 5;
        continue;
      }
      if (inJs) {
        i++;
        continue;
      }
      if (str.startsWith('{{', i)) {
        depth++;
        i += 2;
        continue;
      }
      if (str.startsWith('}}', i) && depth > 0) {
        depth--;
        i += 2;
        continue;
      }
      if (depth == 0 && str.startsWith('##', i)) break;
      if (depth == 0 && str.startsWith(sep, i)) {
        parts.add(str.substring(start, i));
        i += sep.length;
        start = i;
        continue;
      }
      i++;
    }
    parts.add(str.substring(start));
    return parts;
  }

  /// 拆出 ##正则##替换 尾部
  static (String, List<(String, String)>) splitRegexTail(String rule) {
    var idx = -1;
    var depth = 0, inJs = false, i = 0;
    while (i < rule.length) {
      if (!inJs && rule.startsWith('<js>', i)) {
        inJs = true;
        i += 4;
        continue;
      }
      if (inJs && rule.startsWith('</js>', i)) {
        inJs = false;
        i += 5;
        continue;
      }
      if (inJs) {
        i++;
        continue;
      }
      if (rule.startsWith('{{', i)) {
        depth++;
        i += 2;
        continue;
      }
      if (rule.startsWith('}}', i) && depth > 0) {
        depth--;
        i += 2;
        continue;
      }
      if (depth == 0 && rule.startsWith('##', i)) {
        idx = i;
        break;
      }
      i++;
    }
    if (idx < 0) return (rule, const []);
    final main = rule.substring(0, idx);
    final tail = rule.substring(idx + 2).split('##');
    final replaces = <(String, String)>[];
    for (var k = 0; k < tail.length; k += 2) {
      replaces.add((tail[k], k + 1 < tail.length ? tail[k + 1] : ''));
    }
    return (main, replaces);
  }

  static dynamic applyReplaces(dynamic value, List<(String, String)> reps) {
    if (reps.isEmpty) return value;
    String rep(String str) {
      var out = str;
      for (final r in reps) {
        if (r.$1.isEmpty) continue;
        try {
          out = out.replaceAll(RegExp(r.$1), r.$2);
        } catch (_) {}
      }
      return out;
    }

    if (value is List) return value.map((e) => rep(e.toString())).toList();
    return rep(value?.toString() ?? '');
  }

  static int topLevelIndexOf(String str, String token) {
    var depth = 0, inJs = false;
    for (var i = 0; i <= str.length - token.length; i++) {
      if (!inJs && str.startsWith('<js>', i)) {
        inJs = true;
        i += 3;
        continue;
      }
      if (inJs && str.startsWith('</js>', i)) {
        inJs = false;
        i += 4;
        continue;
      }
      if (inJs) continue;
      if (str.startsWith('{{', i)) {
        depth++;
        i++;
        continue;
      }
      if (str.startsWith('}}', i) && depth > 0) {
        depth--;
        i++;
        continue;
      }
      if (depth == 0 && str.startsWith('##', i)) return -1;
      if (depth == 0 && str.startsWith(token, i)) return i;
    }
    return -1;
  }

  /* ---------------- 取值器：XPath（常用子集） ---------------- */

  static bool _isXpath(String s) =>
      s.startsWith('//') || s.startsWith('./') || s.startsWith('.//') || s.startsWith('../');

  /// 返回选中的节点值（元素文本 / 属性值）
  static List<String> xpathSelect(String xpath, EvalContext ctx) {
    final root = ctx.root;
    if (root == null) return [];
    try {
      return _xpathEval(xpath, root);
    } catch (_) {
      return [];
    }
  }

  static List<String> _xpathEval(String xpath, dom.Element root) {
    var path = xpath;
    if (path.startsWith('./')) path = path.substring(1);
    // tokenize 步骤
    final steps = <_XStep>[];
    var i = 0;
    while (i < path.length) {
      var descendant = false;
      if (path.startsWith('//', i)) {
        descendant = true;
        i += 2;
      } else if (path.startsWith('/', i)) {
        i += 1;
      }
      final buf = StringBuffer();
      var bracket = 0;
      while (i < path.length && (bracket > 0 || path[i] != '/')) {
        if (path[i] == '[') bracket++;
        if (path[i] == ']') bracket--;
        buf.write(path[i]);
        i++;
      }
      final step = buf.toString();
      if (step.isNotEmpty) steps.add(_XStep(descendant, step));
    }
    if (steps.isEmpty) return [];

    List<dom.Element> current = [root];
    for (var s = 0; s < steps.length; s++) {
      final step = steps[s];
      final last = s == steps.length - 1;
      // 终值步骤
      if (last && step.expr == 'text()') {
        return current.map((e) => trim(e.text)).where(isNonEmpty).toList();
      }
      if (last && step.expr.startsWith('@')) {
        final attr = step.expr.substring(1);
        return current
            .map((e) => trim(e.attributes[attr]))
            .where(isNonEmpty)
            .toList();
      }
      final next = <dom.Element>[];
      for (final base in current) {
        next.addAll(_xpathStep(base, step));
      }
      current = next;
      if (current.isEmpty) return [];
    }
    return current.map((e) => trim(e.text)).where(isNonEmpty).toList();
  }

  static List<dom.Element> _xpathStep(dom.Element base, _XStep step) {
    // 解析 tag[@attr='v'][@attr2][n]
    var expr = step.expr;
    int? index;
    final attrs = <String, String?>{};
    final attrRe = RegExp(r"\[@([\w-]+)(?:='([^']*)')?\]");
    expr = expr.replaceAllMapped(attrRe, (m) {
      attrs[m.group(1)!] = m.group(2);
      return '';
    });
    final idxRe = RegExp(r'\[(\d+)\]$');
    final idxM = idxRe.firstMatch(expr);
    if (idxM != null) {
      index = int.parse(idxM.group(1)!);
      expr = expr.replaceAll(idxRe, '');
    }
    final tag = expr.isEmpty ? '*' : expr;

    bool match(dom.Element e) {
      if (tag != '*' && e.localName != tag) return false;
      for (final a in attrs.entries) {
        final v = e.attributes[a.key];
        if (v == null) return false;
        if (a.value != null && v != a.value) return false;
      }
      return true;
    }

    Iterable<dom.Element> candidates;
    if (step.descendant) {
      candidates = tag == '*'
          ? base.querySelectorAll('*')
          : base.querySelectorAll(tag);
      candidates = candidates.where(match);
    } else {
      candidates = base.children.where(match);
    }
    var list = candidates.toList();
    if (index != null) {
      // XPath 1 基
      final i = index - 1;
      return (i >= 0 && i < list.length) ? [list[i]] : [];
    }
    return list;
  }

  /* ---------------- 取值器：JSONPath（简易） ---------------- */

  static dynamic _jsonFindKey(dynamic obj, String key) {
    if (obj is Map) {
      if (obj.containsKey(key)) return obj[key];
      for (final v in obj.values) {
        final r = _jsonFindKey(v, key);
        if (r != null) return r;
      }
    } else if (obj is List) {
      for (final v in obj) {
        final r = _jsonFindKey(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }

  static dynamic jsonPath(dynamic obj, String path) {
    path = trim(path);
    if (obj == null) return null;
    if (path == r'$' || path.isEmpty) return obj;
    if (path.startsWith(r'$..')) return _jsonFindKey(obj, path.substring(3));
    if (path.startsWith('..')) return _jsonFindKey(obj, path.substring(2));
    if (path.startsWith(r'$')) path = path.substring(1);
    if (path.startsWith('.')) path = path.substring(1);
    if (path.isEmpty) return obj;
    var cur = obj;
    for (final token in path.split('.')) {
      if (cur == null) return null;
      final m = RegExp(r'^([^\[]*)((?:\[\d+\])*)$').firstMatch(token);
      if (m == null) return null;
      final name = m.group(1)!;
      if (name.isNotEmpty) {
        cur = cur is Map ? cur[name] : null;
      }
      for (final im in RegExp(r'\[(\d+)\]').allMatches(token)) {
        final idx = int.parse(im.group(1)!);
        cur = (cur is List && idx < cur.length) ? cur[idx] : null;
      }
    }
    return cur;
  }

  static List<String> jsonValues(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v
          .map((e) => (e is Map || e is List) ? jsonEncode(e) : e.toString())
          .where(isNonEmpty)
          .toList();
    }
    if (v is Map) return [jsonEncode(v)];
    final s = v.toString();
    return isNonEmpty(s) ? [s] : [];
  }

  /* ---------------- 取值器：JSoup 简写 CSS ---------------- */

  static ({String? selector, _CssValue? value}) parseCssRule(String rule) {
    final segs = rule.split('@');
    _CssValue? value;
    if (segs.length == 1 &&
        RegExp(r'^(text|textNodes|ownText|html)$', caseSensitive: false)
            .hasMatch(trim(segs[0]))) {
      return (
        selector: null,
        value: _CssValue(trim(segs[0]).toLowerCase(), null)
      );
    }
    if (segs.length > 1) {
      final last = trim(segs.last);
      if (RegExp(r'^(text|textNodes|ownText|html)$', caseSensitive: false)
          .hasMatch(last)) {
        value = _CssValue(last.toLowerCase(), null);
        segs.removeLast();
      } else if (RegExp(r'^[a-zA-Z][\w-]*$').hasMatch(last)) {
        value = _CssValue('attr', last);
        segs.removeLast();
      }
    }
    final selParts = <String>[];
    for (final segRaw in segs) {
      final seg = trim(segRaw);
      if (seg.isEmpty) continue;
      if (seg.startsWith('class.')) {
        selParts.add('.${seg.substring(6).split(RegExp(r'\s+')).join('.')}');
      } else if (seg.startsWith('id.')) {
        selParts.add('#${seg.substring(3)}');
      } else if (seg.startsWith('tag.')) {
        final t = seg.substring(4);
        final m = RegExp(r'^([\w-]+)\.(-?\d+)$').firstMatch(t);
        if (m != null) {
          final n = int.parse(m.group(2)!);
          selParts.add(n >= 0
              ? '${m.group(1)}:nth-of-type(${n + 1})'
              : '${m.group(1)}:nth-last-of-type(${-n})');
        } else {
          selParts.add(t);
        }
      } else {
        selParts.add(seg);
      }
    }
    return (
      selector: selParts.isEmpty ? null : selParts.join(' '),
      value: value
    );
  }

  static List<dom.Element> cssSelect(String? selector, EvalContext ctx) {
    final root = ctx.root;
    if (root == null) return [];
    if (selector == null) return [root];
    try {
      return root.querySelectorAll(selector);
    } catch (_) {
      return [];
    }
  }

  static String cssExtract(dom.Element el, _CssValue? value, String baseUrl) {
    if (value == null) return trim(el.text);
    switch (value.kind) {
      case 'text':
        return trim(el.text);
      case 'html':
        return trim(el.innerHtml);
      case 'textnodes':
      case 'owntext':
        final out = <String>[];
        for (final n in el.nodes) {
          if (n.nodeType == dom.Node.TEXT_NODE && trim(n.text).isNotEmpty) {
            out.add(trim(n.text));
          }
        }
        return out.join('\n');
      case 'attr':
        final v = el.attributes[value.name];
        if (v == null) return '';
        final t = trim(v);
        if (RegExp(r'^(href|src)$', caseSensitive: false)
            .hasMatch(value.name!)) {
          return absUrl(t, baseUrl);
        }
        return t;
      default:
        return trim(el.text);
    }
  }

  /* ---------------- 规则求值 evalRule ---------------- */

  static dynamic _finalize(dynamic out, bool wantList) {
    if (wantList) {
      if (out is List) {
        return out
            .map((e) => e?.toString() ?? '')
            .where(isNonEmpty)
            .toList();
      }
      return isNonEmpty(out) ? [out.toString()] : <String>[];
    }
    if (out is List) return out.isEmpty ? '' : (out.first?.toString() ?? '');
    return out?.toString() ?? '';
  }

  /// 单个取值器求值 → 字符串数组
  static List<String> evalValue(String rule, EvalContext ctx) {
    if (RegExp(r'^@XPath:', caseSensitive: false).hasMatch(rule)) {
      return xpathSelect(rule.substring(7), ctx);
    }
    if (_isXpath(rule)) {
      return xpathSelect(rule, ctx);
    }
    if (RegExp(r'^@JSon:', caseSensitive: false).hasMatch(rule)) {
      return jsonValues(jsonPath(ctx.json, rule.substring(6)));
    }
    if (rule.startsWith(r'$')) {
      return jsonValues(jsonPath(ctx.json, rule));
    }
    var cssRule = rule;
    if (RegExp(r'^@CSS:', caseSensitive: false).hasMatch(cssRule)) {
      cssRule = cssRule.substring(5);
    }
    final parsed = parseCssRule(cssRule);
    return cssSelect(parsed.selector, ctx)
        .map((el) => cssExtract(el, parsed.value, ctx.baseUrl))
        .toList();
  }

  static dynamic evalRule(dynamic ruleRaw, EvalContext context, bool wantList) {
    if (ruleRaw == null) return wantList ? <String>[] : '';
    var rule = trim(ruleRaw.toString());
    if (rule.isEmpty) return wantList ? <String>[] : '';

    // 1) 整段 <js>...</js>
    if (rule.startsWith('<js>') && rule.endsWith('</js>')) {
      final jsCode = rule.substring(4, rule.length - 5);
      return _finalize(runJs(jsCode, context.text ?? '', context), wantList);
    }

    // 2) ## 正则替换后缀
    final (main0, replaces) = splitRegexTail(rule);
    final main = trim(main0);
    if (main.isEmpty) return wantList ? <String>[] : '';

    // 3) || 组合：取第一个非空
    final alts = splitTop(main, '||');
    if (alts.length > 1) {
      for (final a in alts) {
        final v = evalRule(a, context, wantList);
        if (wantList ? (v as List).isNotEmpty : isNonEmpty(v)) {
          return applyReplaces(v, replaces);
        }
      }
      return wantList ? <String>[] : '';
    }

    // 4) && 组合：结果拼接
    final ands = splitTop(main, '&&');
    if (ands.length > 1) {
      final buf = <String>[];
      for (final a in ands) {
        final av = evalRule(a, context, false);
        if (isNonEmpty(av)) buf.add(av.toString());
      }
      final joined = buf.join(wantList ? '\n' : '');
      return applyReplaces(
          wantList ? (joined.isNotEmpty ? [joined] : <String>[]) : joined,
          replaces);
    }

    // 5) @js: 尾段
    final jsIdx = topLevelIndexOf(main, '@js:');
    if (jsIdx > -1) {
      final preRule = main.substring(0, jsIdx);
      final jsTail = main.substring(jsIdx + 4);
      final preRes = preRule.isNotEmpty
          ? evalRule(preRule, context, false)
          : (context.text ?? '');
      return applyReplaces(
          _finalize(runJs(jsTail, preRes, context), wantList), replaces);
    }

    // 6) {{ }} 模板插值
    if (main.contains('{{')) {
      var out = '', rest = main, guard = 0;
      while (rest.contains('{{') && guard++ < 50) {
        final s = rest.indexOf('{{');
        var e = rest.indexOf('}}', s + 2);
        if (e < 0) break;
        out += rest.substring(0, s);
        out += evalRule(rest.substring(s + 2, e), context, false).toString();
        rest = rest.substring(e + 2);
      }
      out += rest;
      final inter = trim(out);
      return applyReplaces(
          wantList ? (inter.isNotEmpty ? [inter] : <String>[]) : inter,
          replaces);
    }

    // 7) 取值器
    final vals = evalValue(main, context);
    final res = wantList ? vals : (vals.isNotEmpty ? vals.first : '');
    return applyReplaces(res, replaces);
  }

  /* ---------------- 列表规则 ---------------- */

  static List<EvalContext> evalItems(String? ruleRaw, EvalContext context) {
    if (!isNonEmpty(ruleRaw)) return [];
    var rule = trim(ruleRaw);

    List<EvalContext> fromDom(List<dom.Element> els) => els
        .map((el) => context.child(element: el))
        .toList();

    List<EvalContext> fromJson(List arr) => arr.map((item) {
          if (item is Map || item is List) {
            return context.child(json: item);
          }
          return context.child(text: item.toString());
        }).toList();

    // JS 段：结果尝试解析为 JSON 数组
    if (rule.startsWith('<js>') || topLevelIndexOf(rule, '@js:') > -1) {
      final out = evalRule(rule, context, false);
      try {
        final parsed = jsonDecode(out.toString());
        return fromJson(parsed is List ? parsed : [parsed]);
      } catch (_) {
        return [];
      }
    }

    if (rule.contains('{{')) {
      rule = evalRule(rule, context, false).toString();
    }

    if (RegExp(r'^@XPath:', caseSensitive: false).hasMatch(rule)) {
      return _xpathElements(rule.substring(7), context)
          .map((el) => context.child(element: el))
          .toList();
    }
    if (_isXpath(rule)) {
      return _xpathElements(rule, context)
          .map((el) => context.child(element: el))
          .toList();
    }
    if (RegExp(r'^@JSon:', caseSensitive: false).hasMatch(rule)) {
      final v = jsonPath(context.json, rule.substring(6));
      return fromJson(v is List ? v : (v != null ? [v] : []));
    }
    if (rule.startsWith(r'$')) {
      final v = jsonPath(context.json, rule);
      return fromJson(v is List ? v : (v != null ? [v] : []));
    }
    var cssRule = rule;
    if (RegExp(r'^@CSS:', caseSensitive: false).hasMatch(cssRule)) {
      cssRule = cssRule.substring(5);
    }
    final parsed = parseCssRule(cssRule);
    return fromDom(cssSelect(parsed.selector, context));
  }

  /// XPath 返回元素（用于列表规则）
  static List<dom.Element> _xpathElements(String xpath, EvalContext ctx) {
    final root = ctx.root;
    if (root == null) return [];
    try {
      var path = xpath;
      if (path.startsWith('./')) path = path.substring(1);
      final steps = <_XStep>[];
      var i = 0;
      while (i < path.length) {
        var descendant = false;
        if (path.startsWith('//', i)) {
          descendant = true;
          i += 2;
        } else if (path.startsWith('/', i)) {
          i += 1;
        }
        final buf = StringBuffer();
        var bracket = 0;
        while (i < path.length && (bracket > 0 || path[i] != '/')) {
          if (path[i] == '[') bracket++;
          if (path[i] == ']') bracket--;
          buf.write(path[i]);
          i++;
        }
        final step = buf.toString();
        if (step.isNotEmpty) steps.add(_XStep(descendant, step));
      }
      List<dom.Element> current = [root];
      for (final step in steps) {
        final next = <dom.Element>[];
        for (final base in current) {
          next.addAll(_xpathStep(base, step));
        }
        current = next;
        if (current.isEmpty) break;
      }
      return current;
    } catch (_) {
      return [];
    }
  }

  /* ---------------- 网络 ---------------- */

  static ({String url, String method, Map<String, String> headers, String? body})
      buildRequest(String searchUrl, String key, int page) {
    var raw = trim(searchUrl);
    var url = raw;
    Map<String, dynamic>? options;
    final optIdx = raw.indexOf(',{');
    if (optIdx > -1) {
      url = trim(raw.substring(0, optIdx));
      var optText = raw.substring(optIdx + 1);
      optText = optText
          .replaceAll('{{key}}', Uri.encodeComponent(key))
          .replaceAll('{{searchKey}}', Uri.encodeComponent(key))
          .replaceAll('{{page}}', '$page')
          .replaceAll('{{searchPage}}', '$page');
      try {
        options = jsonDecode(optText) as Map<String, dynamic>;
      } catch (_) {
        options = null;
      }
    }
    url = url
        .replaceAll('{{key}}', Uri.encodeComponent(key))
        .replaceAll('{{searchKey}}', Uri.encodeComponent(key))
        .replaceAll('{{page}}', '$page')
        .replaceAll('{{searchPage}}', '$page');

    var method = 'GET';
    final headers = <String, String>{};
    String? body;
    if (options != null) {
      if (options['method'] != null) {
        method = options['method'].toString().toUpperCase();
      }
      if (options['headers'] is Map) {
        (options['headers'] as Map).forEach((k, v) {
          headers[k.toString()] = v.toString();
        });
      }
      if (options['body'] != null) {
        body = options['body']
            .toString()
            .replaceAll('searchKey', key)
            .replaceAll('{{searchPage}}', '$page')
            .replaceAll('{{page}}', '$page');
      }
    }
    return (url: url, method: method, headers: headers, body: body);
  }

  static Map<String, String> _sourceHeaders(BookSource src) {
    final raw = src.header;
    if (raw == null) return {};
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        return j.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  static Future<EvalContext> fetchText(String url,
      {String method = 'GET',
      Map<String, String> headers = const {},
      String? body,
      BookSource? src}) async {
    final mergedHeaders = <String, String>{
      ..._sourceHeaders(src ?? BookSource(bookSourceName: '', bookSourceUrl: '')),
      ...headers,
    };
    Response res;
    try {
      res = await _dio.request(
        url,
        data: body,
        options: Options(method: method, headers: mergedHeaders),
      );
    } catch (e) {
      throw Exception('网络请求失败：目标站点无法访问');
    }
    final text = res.data?.toString() ?? '';
    final t = trim(text);
    if (t.startsWith('{') || t.startsWith('[')) {
      try {
        return EvalContext(
            text: text, json: jsonDecode(text), baseUrl: url);
      } catch (_) {}
    }
    dom.Document? doc;
    try {
      doc = htmlparser.parse(text);
    } catch (_) {}
    return EvalContext(text: text, document: doc, baseUrl: url);
  }

  /* ---------------- 流程：搜索 ---------------- */

  static Future<List<NovelBook>> search(BookSource src, String keyword) async {
    if (src.isTauri) {
      return TauriEngine.instance.search(src, keyword, 1, src.mediaType);
    }
    if (src.searchUrl == null) {
      throw Exception('书源「${src.bookSourceName}」未配置搜索地址');
    }
    final req = buildRequest(src.searchUrl!, keyword, 1);
    final resp = await fetchText(req.url,
        method: req.method, headers: req.headers, body: req.body, src: src);
    final rs = src.ruleSearch;
    await prefetchAjax(rs['bookList'], resp, src: src);
    final items = evalItems(rs['bookList']?.toString(), resp);
    final out = <NovelBook>[];
    for (final ictx in items) {
      try {
        for (final k in const [
          'name', 'author', 'intro', 'coverUrl', 'bookUrl', 'lastChapter'
        ]) {
          await prefetchAjax(rs[k], ictx, src: src);
        }
        var name = evalRule(rs['name'], ictx, false).toString();
        var bookUrl = evalRule(rs['bookUrl'], ictx, false).toString();
        if (bookUrl.isEmpty &&
            ictx.text != null &&
            RegExp(r'^https?:', caseSensitive: false)
                .hasMatch(trim(ictx.text))) {
          bookUrl = trim(ictx.text);
        }
        if (name.isEmpty && ictx.element != null) {
          name = trim(ictx.element!.text);
        }
        if (name.isEmpty) continue;
        out.add(NovelBook(
          name: decodeEntities(name),
          author: decodeEntities(evalRule(rs['author'], ictx, false).toString()),
          intro: decodeEntities(evalRule(rs['intro'], ictx, false).toString()),
          cover: absUrl(
              evalRule(rs['coverUrl'], ictx, false).toString(), req.url),
          lastChapter: decodeEntities(
              evalRule(rs['lastChapter'], ictx, false).toString()),
          url: absUrl(bookUrl, req.url),
          sourceName: src.bookSourceName,
          mediaType: src.mediaType,
          wordCount: decodeEntities(
              evalRule(rs['wordCount'], ictx, false).toString()),
          kind: decodeEntities(evalRule(rs['kind'], ictx, false).toString()),
        ));
      } catch (_) {}
    }
    return out;
  }

  /* ---------------- 流程：发现（explore） ---------------- */

  /// 解析 exploreUrl 分类列表：每行/&& 分隔「名称::URL」
  static List<(String, String)> exploreCategories(BookSource src) {
    final raw = trim(src.exploreUrl ?? '');
    if (raw.isEmpty) return [];
    final out = <(String, String)>[];
    for (final part in raw.split(RegExp(r'\n|&&'))) {
      final p = trim(part);
      if (p.isEmpty) continue;
      final idx = p.indexOf('::');
      if (idx > 0) {
        out.add((trim(p.substring(0, idx)), trim(p.substring(idx + 2))));
      } else {
        out.add((src.bookSourceName, p));
      }
    }
    return out;
  }

  /// 加载某个发现分类的列表（规则用 ruleExplore，字段与搜索一致）
  static Future<List<NovelBook>> explore(
      BookSource src, String url, {int page = 1}) async {
    if (src.isTauri) {
      return TauriEngine.instance.explore(src, url, page, src.mediaType);
    }
    final req = buildRequest(url, '', page);
    final resp = await fetchText(req.url,
        method: req.method, headers: req.headers, body: req.body, src: src);
    final re = src.ruleExplore.isNotEmpty ? src.ruleExplore : src.ruleSearch;
    await prefetchAjax(re['bookList'], resp, src: src);
    final items = evalItems(re['bookList']?.toString(), resp);
    final out = <NovelBook>[];
    for (final ictx in items) {
      try {
        var name = evalRule(re['name'], ictx, false).toString();
        var bookUrl = evalRule(re['bookUrl'], ictx, false).toString();
        if (bookUrl.isEmpty &&
            ictx.text != null &&
            RegExp(r'^https?:', caseSensitive: false)
                .hasMatch(trim(ictx.text))) {
          bookUrl = trim(ictx.text);
        }
        if (name.isEmpty && ictx.element != null) {
          name = trim(ictx.element!.text);
        }
        if (name.isEmpty) continue;
        out.add(NovelBook(
          name: decodeEntities(name),
          author: decodeEntities(evalRule(re['author'], ictx, false).toString()),
          intro: decodeEntities(evalRule(re['intro'], ictx, false).toString()),
          cover:
              absUrl(evalRule(re['coverUrl'], ictx, false).toString(), req.url),
          lastChapter: decodeEntities(
              evalRule(re['lastChapter'], ictx, false).toString()),
          url: absUrl(bookUrl, req.url),
          sourceName: src.bookSourceName,
          mediaType: src.mediaType,
          wordCount: decodeEntities(
              evalRule(re['wordCount'], ictx, false).toString()),
          kind: decodeEntities(evalRule(re['kind'], ictx, false).toString()),
        ));
      } catch (_) {}
    }
    return out;
  }

  /* ---------------- 流程：书籍详情 ---------------- */

  static Future<NovelBook> getBookInfo(BookSource src, NovelBook book) async {
    if (src.isTauri) {
      return TauriEngine.instance.bookInfo(src, book);
    }
    final resp = await fetchText(book.url, src: src);
    final ri = src.ruleBookInfo;
    for (final k in ri.keys) {
      await prefetchAjax(ri[k], resp, src: src);
    }
    String v(String? r) => decodeEntities(evalRule(r, resp, false).toString());
    final name = v(ri['name']?.toString());
    final toc =
        absUrl(evalRule(ri['tocUrl'], resp, false).toString(), book.url);
    return NovelBook(
      name: name.isNotEmpty ? name : book.name,
      author: v(ri['author']?.toString()),
      intro: v(ri['intro']?.toString()),
      lastChapter: v(ri['lastChapter']?.toString()),
      cover: absUrl(evalRule(ri['coverUrl'], resp, false).toString(),
          book.url),
      url: book.url,
      tocUrl: toc,
      sourceName: book.sourceName,
      mediaType: book.mediaType,
      wordCount: v(ri['wordCount']?.toString()),
      kind: v(ri['kind']?.toString()),
    );
  }

  /* ---------------- 流程：目录 ---------------- */

  static Future<List<NovelChapter>> getToc(BookSource src, NovelBook book,
      {String? tocUrl}) async {
    if (src.isTauri) {
      return TauriEngine.instance.chapterList(src,
          tocUrl ?? (book.tocUrl.isNotEmpty ? book.tocUrl : book.url));
    }
    final rt = src.ruleToc;
    var url = tocUrl ?? (book.tocUrl.isNotEmpty ? book.tocUrl : book.url);
    final chapters = <NovelChapter>[];
    var page = 0;
    var redirected = false;

    while (url.isNotEmpty && page < 5) {
      final resp = await fetchText(url, src: src);
      resp.book = book.toJson();
      await prefetchAjax(rt['chapterList'], resp, src: src);
      final items = evalItems(rt['chapterList']?.toString(), resp);

      if (items.isEmpty &&
          !redirected &&
          isNonEmpty(rt['tocUrl']?.toString())) {
        redirected = true;
        final next =
            absUrl(evalRule(rt['tocUrl'], resp, false).toString(), url);
        if (next.isNotEmpty && next != url) {
          url = next;
          continue;
        }
      }

      for (final ictx in items) {
        try {
          await prefetchAjax(rt['chapterName'], ictx, src: src);
          await prefetchAjax(rt['chapterUrl'], ictx, src: src);
          var name = evalRule(rt['chapterName'], ictx, false).toString();
          if (name.isEmpty && ictx.element != null) {
            name = trim(ictx.element!.text);
          }
          final volVal = evalRule(rt['isVolume'], ictx, false).toString();
          final isVolume =
              isNonEmpty(volVal) && volVal != 'false' && volVal != '0';
          final curl = isVolume
              ? ''
              : absUrl(evalRule(rt['chapterUrl'], ictx, false).toString(),
                  url);
          if (name.isEmpty) continue;
          chapters.add(
              NovelChapter(decodeEntities(name), curl, isVolume: isVolume));
        } catch (_) {}
      }

      var nextToc = '';
      if (isNonEmpty(rt['nextTocUrl']?.toString())) {
        final nv = evalRule(rt['nextTocUrl'], resp, true) as List;
        nextToc = nv.isNotEmpty ? absUrl(nv.first.toString(), url) : '';
      }
      url = (nextToc.isNotEmpty && nextToc != url) ? nextToc : '';
      page++;
    }
    return chapters;
  }

  /* ---------------- 流程：正文 ---------------- */

  static String htmlToText(String html) {
    var s = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
            RegExp(r'</(p|div|li|tr|h[1-6])>', caseSensitive: false), '\n')
        .replaceAll(
            RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    s = decodeEntities(s);
    return s
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
  }

  static bool _looksLikeImageUrl(String s) => RegExp(
          r'^https?://\S+?\.(jpe?g|png|webp|gif|bmp)(\?\S*)?$',
          caseSensitive: false)
      .hasMatch(trim(s));

  static Future<NovelContent> getContent(
      BookSource src, NovelChapter chapter) async {
    if (src.isTauri) {
      return TauriEngine.instance.chapterContent(src, chapter, src.mediaType);
    }
    final rc = src.ruleContent;
    if (!isNonEmpty(rc['content']?.toString())) {
      throw Exception('书源「${src.bookSourceName}」未配置正文规则');
    }
    var url = chapter.url;
    if (url.isEmpty) throw Exception('缺少章节地址');

    final chunks = <String>[];
    var page = 0;
    while (url.isNotEmpty && page < 3) {
      final resp = await fetchText(url, src: src);
      resp.chapter = {'name': chapter.name, 'url': chapter.url};
      await prefetchAjax(rc['content'], resp, src: src);
      await prefetchAjax(rc['nextContentUrl'], resp, src: src);
      final vals = evalRule(rc['content'], resp, true) as List;
      if (vals.isNotEmpty) chunks.add(vals.join('\n'));

      var nextUrl = '';
      if (isNonEmpty(rc['nextContentUrl']?.toString())) {
        final nv = evalRule(rc['nextContentUrl'], resp, true) as List;
        nextUrl = nv.isNotEmpty ? absUrl(nv.first.toString(), url) : '';
      }
      url = (nextUrl.isNotEmpty && nextUrl != url) ? nextUrl : '';
      page++;
    }

    var content = chunks.join('\n');

    if (isNonEmpty(rc['replaceRegex']?.toString())) {
      try {
        content =
            content.replaceAll(RegExp(rc['replaceRegex'].toString()), '');
      } catch (_) {}
    }

    // 图片章节：含 <img 标签
    if (content.contains('<img')) {
      final images = <String>[];
      for (final m in RegExp("<img[^>]+src=[\"']([^\"']+)[\"']",
              caseSensitive: false)
          .allMatches(content)) {
        final u = absUrl(m.group(1)!, chapter.url);
        if (u.isNotEmpty) images.add(u);
      }
      if (images.isNotEmpty) return NovelContent.images(images);
    }

    // 图片章节：每行都是图片 URL
    final lines =
        content.split('\n').map(trim).where(isNonEmpty).toList();
    if (lines.isNotEmpty && lines.every(_looksLikeImageUrl)) {
      return NovelContent.images(
          lines.map((u) => absUrl(u, chapter.url)).toList());
    }

    // 全局替换规则（Legado 净化规则）
    var text = htmlToText(content);
    try {
      text = LegadoExtras.instance.applyReplaceRules(text);
    } catch (_) {}
    return NovelContent.text(text);
  }
}

class _XStep {
  final bool descendant;
  final String expr;
  const _XStep(this.descendant, this.expr);
}

class _CssValue {
  final String kind;
  final String? name;
  const _CssValue(this.kind, this.name);
}
