/// 小说模块页面：书源管理 / 搜索 / 详情目录 / 正文阅读
library novel_pages;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/omnihub/novel/book_source.dart';
import 'package:venera/omnihub/novel/legado_engine.dart';
import 'package:venera/omnihub/novel/local_import.dart';
import 'package:venera/omnihub/novel/source_detect.dart';
import 'package:venera/omnihub/rss/rss_source.dart';
import 'package:venera/omnihub/video/tvbox.dart';
import 'package:venera/pages/novel/rss_pages.dart';
import 'package:venera/pages/video/video_pages.dart';
import 'package:venera/omnihub/stats/reading_stats.dart';
import 'package:venera/omnihub/tts/edge_tts.dart';
import 'package:venera/omnihub/tts/tts_service.dart';
import 'package:venera/utils/translations.dart';

/// 小说 Tab（主页内嵌）：书架 + 搜索入口 + 书源管理入口
class NovelTab extends StatefulWidget {
  const NovelTab({super.key});

  @override
  State<NovelTab> createState() => _NovelTabState();
}

class _NovelTabState extends State<NovelTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    BookSourceManager.instance.load().then((_) => _onChange());
    NovelShelf.instance.load().then((_) => _onChange());
    BookSourceManager.instance.addListener(_onChange);
    NovelShelf.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    BookSourceManager.instance.removeListener(_onChange);
    NovelShelf.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final books = NovelShelf.instance.books;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 搜索入口
        Material(
          color: context.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(32),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: () => context.to(() => const NovelSearchPage()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.search),
                  const SizedBox(width: 8),
                  Text("搜索全网小说".tl),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          dense: true,
          leading: const Icon(Icons.dns_outlined),
          title: Text("书源管理".tl),
          subtitle: Text(
              "@c 个书源，@e 个已启用".tlParams({
                'c': BookSourceManager.instance.sources.length,
                'e': BookSourceManager.instance.enabledSources.length,
              }),
              style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.to(() => const NovelSourcesPage()),
        ),
        const Divider(height: 24),
        if (books.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text("搜索小说后可加入书架".tl,
                  style: TextStyle(color: context.colorScheme.outline)),
            ),
          )
        else
          for (final b in books)
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  b.author,
                  if (NovelShelf.instance.progress.containsKey(b.url))
                    "读到第 @c 章".tlParams(
                        {'c': NovelShelf.instance.progress[b.url]! + 1}),
                ].where((e) => e.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: "移出书架".tl,
                onPressed: () => NovelShelf.instance.remove(b.url),
              ),
              onTap: () => context.to(() => NovelBookPage(book: b)),
            ),
      ],
    );
  }
}

/// 书源管理
class NovelSourcesPage extends StatefulWidget {
  const NovelSourcesPage({super.key});

  /// 通用入口：处理 http(s) 书源地址与 legado://import/{path}?src={url} 协议
  static Future<void> importLegadoUrl(String url, BuildContext context) async {
    var type = 'bookSource';
    var target = url.trim();
    if (target.startsWith('legado://')) {
      final uri = Uri.parse(target);
      // legado://import/{path}?src={url}
      final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      // host 为 import 时 path 在 host 之后；也兼容 path 直接是类型
      final p = uri.host == 'import' ? seg : uri.host;
      const supported = ['bookSource', 'textTocRule', 'replaceRule', 'httpTTS', 'rssSource'];
      if (!supported.contains(p)) {
        if (context.mounted) {
          context.showMessage(
              message: "暂不支持导入 @t 类型".tlParams({'t': p}));
        }
        return;
      }
      type = p;
      target = uri.queryParameters['src'] ?? '';
      if (target.isEmpty) {
        if (context.mounted) context.showMessage(message: "链接缺少 src 参数".tl);
        return;
      }
    }
    // URL 自动识别：候选地址逐个探测（原样 / .html 截断 / yckceo 模式 / 路径截断）
    final candidates = type == 'bookSource'
        ? SourceUrlResolver.candidates(target)
        : <String>[target];
    final tried = candidates.isEmpty ? <String>[target] : candidates;
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 25),
      headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android) legado/3.0'},
    ));
    Object? lastError;
    for (final c in tried) {
      try {
        final res = await dio.get<String>(c);
        final text = res.data ?? '';
        if (text.isEmpty) continue;
        if (type == 'rssSource') {
          final (n, skip) =
              await RssSourceManager.instance.importJson(text);
          if (context.mounted) {
            context.showMessage(
                message: (n > 0
                        ? "导入 @c 个订阅源（到 RSS 订阅）"
                            .tlParams({'c': n})
                        : "没有可导入的内容".tl) +
                    (skip > 0 ? '，跳过 $skip 个重复' : ''));
          }
          return;
        }
        if (type != 'bookSource') {
          // 指定类型（目录规则/替换规则/TTS）直接按类型导入
          final (n, label) = await LegadoImport.importByType(type, text);
          if (context.mounted) {
            context.showMessage(
                message: n > 0
                    ? "导入 @c 个@l".tlParams({'c': n, 'l': label})
                    : "没有可导入的内容".tl);
          }
          return;
        }
        final detect = SourceDetect.detect(text);
        if (detect.type == SourceDetectType.unknown &&
            tried.length > 1 &&
            c != tried.last) {
          continue; // 尝试下一个候选地址
        }
        if (context.mounted) await importAutoText(text, context, detect);
        return;
      } catch (e) {
        lastError = e;
      }
    }
    if (context.mounted) {
      context.showMessage(
          message: "下载失败：@e".tlParams({'e': '${lastError ?? '无可用地址'}'}));
    }
  }

  /// 粘贴内容自动识别导入（Legado / CSS 配置 / TVBox / Venera / fox 压缩串）
  static Future<void> importAutoText(String text, BuildContext context,
      [SourceDetectResult? detected]) async {
    final d = detected ?? SourceDetect.detect(text);
    try {
      switch (d.type) {
        case SourceDetectType.legado:
          final (n, label) = await LegadoImport.importByType('bookSource', text);
          if (context.mounted) {
            context.showMessage(
                message: (n > 0
                        ? "导入 @c 个@l".tlParams({'c': n, 'l': label})
                        : "没有可导入的内容".tl) +
                    (d.message.isNotEmpty ? '（${d.message}）' : ''));
          }
          return;
        case SourceDetectType.cssConfig:
          final list = d.sources
              .map((e) => SourceDetect.cssToLegado((e as Map).cast()))
              .toList();
          final (n, skip) = await BookSourceManager.instance
              .importJson(jsonEncode(list));
          if (context.mounted) {
            context.showMessage(
                message: (n > 0
                        ? "导入 @c 个书源（CSS 配置已转换）".tlParams({'c': n})
                        : "没有可导入的内容".tl) +
                    (skip > 0 ? '，跳过 $skip 个重复' : ''));
          }
          return;
        case SourceDetectType.tauriJs:
          final (n, skip) =
              await BookSourceManager.instance.importTauri(text.trim());
          if (context.mounted) {
            context.showMessage(
                message: n > 0
                    ? (d.message.isNotEmpty ? d.message : '已导入 Tauri 书源')
                    : '书源已存在，无需重复导入');
          }
          return;
        case SourceDetectType.tvbox:
          final (ok, skip) =
              await TvboxSourceManager.instance.importConfig(d.sources.first);
          if (context.mounted) {
            context.showMessage(
                message: "导入 @ok 个视频源（到影视模块）@skip".tlParams(
                    {'ok': ok, 'skip': skip > 0 ? '，跳过 $skip 个' : ''}));
          }
          return;
        case SourceDetectType.legadoRss:
          final (n, skip) = await RssSourceManager.instance
              .importJson(jsonEncode(d.sources));
          if (context.mounted) {
            context.showMessage(
                message: (n > 0
                        ? "导入 @c 个订阅源（到 RSS 订阅）"
                            .tlParams({'c': n})
                        : "没有可导入的内容".tl) +
                    (skip > 0 ? '，跳过 $skip 个重复' : ''));
          }
          return;
        case SourceDetectType.venera:
        case SourceDetectType.veneraIndex:
          if (context.mounted) {
            context.showMessage(
                message: "检测到 Venera 漫画图源脚本，请到「设置-漫画源」中导入".tl);
          }
          return;
        case SourceDetectType.legadoJs:
        case SourceDetectType.unknown:
          // 兜底：按 Legado 书源再试一次（兼容 base64 包装/杂质）
          try {
            final (n, label) =
                await LegadoImport.importByType('bookSource', text);
            if (context.mounted) {
              context.showMessage(
                  message: n > 0
                      ? "导入 @c 个@l".tlParams({'c': n, 'l': label})
                      : (d.message.isNotEmpty ? d.message : "没有可导入的内容".tl));
            }
          } catch (_) {
            if (context.mounted) {
              context.showMessage(
                  message: d.message.isNotEmpty ? d.message : "无法识别的内容".tl);
            }
          }
          return;
      }
    } catch (e) {
      if (context.mounted) {
        context.showMessage(message: "导入失败：@e".tlParams({'e': e.toString()}));
      }
    }
  }


  @override
  State<NovelSourcesPage> createState() => _NovelSourcesPageState();
}

class _NovelSourcesPageState extends State<NovelSourcesPage> {
  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    BookSourceManager.instance.addListener(_onChange);
    BookSourceManager.instance.load().then((_) => _onChange());
  }

  @override
  void dispose() {
    BookSourceManager.instance.removeListener(_onChange);
    super.dispose();
  }

  /// 导入期间显示加载动画（网络下载 + 解析可能耗时较长）
  Future<void> _withImportLoading(Future<void> Function() task) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('正在导入书源，请稍候…')),
          ],
        ),
      ),
    );
    try {
      await task();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _importText(String text, {String type = 'bookSource'}) async {
    if (type == 'bookSource') {
      // 自动识别书源格式（Legado / CSS 配置 / TVBox / fox 压缩串…）
      await _withImportLoading(
          () => NovelSourcesPage.importAutoText(text, context));
      return;
    }
    try {
      final (n, label) = await LegadoImport.importByType(type, text);
      if (mounted) {
        context.showMessage(
            message: n > 0
                ? "导入 @c 个@l".tlParams({'c': n, 'l': label})
                : "没有可导入的内容".tl);
      }
    } catch (e) {
      if (mounted) {
        context.showMessage(message: "导入失败：@e".tlParams({'e': e.toString()}));
      }
    }
  }

  /// 网络 URL 导入（支持 http/https 与 legado://import/{path}?src= 协议）
  Future<void> _importFromUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("网络导入".tl),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'https://…/sources.json\nlegado://import/bookSource?src=…',
            helperText:
                "支持 Legado 书源地址与 legado:// 协议，.json 无法导入时可改后缀为 .txt 再试"
                    .tl,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel".tl),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text("导入".tl),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _withImportLoading(
        () => NovelSourcesPage.importLegadoUrl(url, context));
  }

  /// 二维码导入
  Future<void> _scanQr() async {
    final code = await context.to<String>(() => const _QrScanPage());
    if (code == null || code.isEmpty || !mounted) return;
    if (code.startsWith('http') || code.startsWith('legado://')) {
      await _withImportLoading(
          () => NovelSourcesPage.importLegadoUrl(code, context));
    } else {
      await _importText(code);
    }
  }

  void _importMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: Text("网络导入".tl),
              subtitle: Text("书源 URL 或 legado:// 链接".tl,
                  style: const TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.of(context).pop();
                _importFromUrl();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: Text("本地文件导入".tl),
              subtitle: Text("支持 .json / .txt 书源文件".tl,
                  style: const TextStyle(fontSize: 12)),
              onTap: () async {
                Navigator.of(context).pop();
                final f = await openFile(
                  acceptedTypeGroups: [
                    const XTypeGroup(label: 'json', extensions: ['json', 'txt'])
                  ],
                );
                if (f != null) {
                  _importText(await File(f.path).readAsString());
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text("二维码导入".tl),
              onTap: () {
                Navigator.of(context).pop();
                _scanQr();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: Text("从剪贴板导入".tl),
              onTap: () async {
                Navigator.of(context).pop();
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null && data!.text!.isNotEmpty) {
                  final t = data.text!.trim();
                  if (t.startsWith('http') || t.startsWith('legado://')) {
                    _withImportLoading(() =>
                        NovelSourcesPage.importLegadoUrl(t, this.context));
                  } else {
                    _importText(t);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mgr = BookSourceManager.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text("书源管理".tl),
        actions: [
          IconButton(
            icon: const Icon(Icons.rss_feed),
            tooltip: "RSS 订阅源".tl,
            onPressed: () => context.to(() => const RssHomePage()),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: "导入书源".tl,
            onPressed: _importMenu,
          ),
        ],
      ),
      body: mgr.sources.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "你未添加书源".tl,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colorScheme.outline),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _importMenu,
                      icon: const Icon(Icons.add),
                      label: Text("点击去添加".tl),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              itemCount: mgr.sources.length,
              itemBuilder: (context, i) {
                final s = mgr.sources[i];
                return ListTile(
                  leading: Icon(s.bookSourceType == 2
                      ? Icons.image_outlined
                      : Icons.article_outlined),
                  title: Text(s.bookSourceName),
                  subtitle: Text(s.bookSourceUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: s.enabled,
                        onChanged: (v) => mgr.toggle(s, v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => mgr.remove(s),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// 二维码扫描页（书源导入）
class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _handled = false;
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emit(String raw) {
    if (_handled) return;
    _handled = true;
    context.pop(raw);
  }

  /// 从相册选取二维码图片并解码
  Future<void> _pickFromGallery() async {
    try {
      const typeGroup = XTypeGroup(
        label: '图片',
        extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final result = await _controller.analyzeImage(file.path);
      final raw = result?.barcodes.firstOrNull?.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _emit(raw);
      } else if (mounted) {
        context.showMessage(message: "未识别到二维码".tl);
      }
    } catch (_) {
      if (mounted) context.showMessage(message: "相册二维码识别失败".tl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("扫码导入".tl)),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final raw = capture.barcodes.firstOrNull?.rawValue;
              if (raw != null && raw.isNotEmpty) {
                _emit(raw);
              }
            },
          ),
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // 相册入口：屏幕中间靠下
          Positioned(
            left: 0,
            right: 0,
            bottom: 120,
            child: Center(
              child: Material(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(28),
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: _pickFromGallery,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_library_outlined,
                            color: Colors.white, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          "相册".tl,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Text(
              "对准二维码，或从相册选择二维码图片".tl,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

/// 搜索页
class NovelSearchPage extends StatefulWidget {
  /// 嵌入模式：作为统一搜索页的「小说」分页内容，不带 Scaffold/AppBar
  final bool embedded;

  const NovelSearchPage({super.key, this.embedded = false});

  @override
  State<NovelSearchPage> createState() => _NovelSearchPageState();
}

class _NovelSearchPageState extends State<NovelSearchPage> {
  final _controller = TextEditingController();
  bool _searching = false;
  List<NovelBook> _results = [];
  String? _error;

  /// 失败/无结果书源：sourceName → 原因（折叠展示，点击才展开）
  final Map<String, String> _sourceFails = {};

  /// 书源范围：all / novel / comic / custom
  String _scope = 'all';

  /// 自选书源（scope == custom 时生效）：bookSourceName 集合
  Set<String> _customSources = {};

  /// 搜索模式：true=精确（书名/作者必须包含关键字），false=聚合（全部结果）
  bool _exactMode = false;

  /// 排序：0=综合（默认） 1=字数多→少 2=字数少→多 3=按书名
  int _sortMode = 0;

  /// 标签筛选（来自结果的 kind 字段）
  String? _tagFilter;

  /// 书源筛选（null=全部书源）
  String? _sourceFilter;

  /// 参与搜索的书源（按范围筛选）
  List<BookSource> get _searchSources {
    var list = BookSourceManager.instance.enabledSources;
    if (_scope == 'novel') {
      list = list.where((s) => s.mediaType == 'novel').toList();
    } else if (_scope == 'comic') {
      list = list.where((s) => s.mediaType == 'comic').toList();
    } else if (_scope == 'custom') {
      list = list.where((s) => _customSources.contains(s.bookSourceName)).toList();
    }
    return list;
  }

  List<NovelBook> get _visible {
    var list = _results;
    if (_exactMode) {
      // 精确搜索：书名/作者必须包含关键字
      final key = _controller.text.trim().toLowerCase();
      if (key.isNotEmpty) {
        list = list
            .where((b) =>
                b.name.toLowerCase().contains(key) ||
                b.author.toLowerCase().contains(key))
            .toList();
      }
    }
    if (_tagFilter != null && _tagFilter!.isNotEmpty) {
      list = list.where((b) => b.kind.contains(_tagFilter!)).toList();
    }
    if (_sourceFilter != null) {
      list = list.where((b) => b.sourceName == _sourceFilter).toList();
    }
    switch (_sortMode) {
      case 1:
        list = [...list]..sort((a, b) => b.wordCountValue - a.wordCountValue);
      case 2:
        list = [...list]..sort((a, b) => a.wordCountValue - b.wordCountValue);
      case 3:
        list = [...list]..sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  /// 结果里出现过的标签（去重，取前 12 个）
  List<String> get _tags {
    final seen = <String>{};
    for (final b in _results) {
      for (var t in b.kind.split(RegExp(r'[,，、\s]+'))) {
        t = t.trim();
        if (t.isNotEmpty && t.length <= 8) seen.add(t);
      }
    }
    return seen.take(12).toList();
  }

  Future<void> _search() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    final sources = _searchSources;
    if (sources.isEmpty) {
      setState(() {
        _error = 'no-sources';
        _results = [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
      _tagFilter = null;
      _sourceFilter = null;
      _sourceFails.clear();
    });
    // 并发搜索范围内的书源，逐个追加结果（聚合搜索）
    await Future.wait(sources.map((s) async {
      try {
        final res = await LegadoEngine.search(s, key);
        if (!mounted) return;
        if (res.isNotEmpty) {
          setState(() => _results = [..._results, ...res]);
        } else {
          _sourceFails[s.bookSourceName] = '无结果';
        }
      } catch (_) {
        _sourceFails[s.bookSourceName] = '加载失败';
      }
    }));
    if (mounted) setState(() => _searching = false);
  }

  /// 搜索结果封面（加载失败回退占位图标）
  Widget _resultCover(NovelBook b) {
    final placeholder = Container(
      width: 40,
      height: 56,
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        b.mediaType == 'comic' ? Icons.image_outlined : Icons.menu_book_outlined,
        size: 20,
        color: context.colorScheme.outline,
      ),
    );
    if (b.cover.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        b.cover,
        width: 40,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }

  /// 自选书源多选对话框（按分组展示，可整组选择）
  Future<void> _pickSources() async {
    final all = BookSourceManager.instance.enabledSources;
    final selected = Set<String>.from(_customSources);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          // 按分组归类（空分组归「未分组」）
          final groups = <String, List<BookSource>>{};
          for (final s in all) {
            final g = s.bookSourceGroup.isEmpty ? '未分组' : s.bookSourceGroup;
            groups.putIfAbsent(g, () => []).add(s);
          }
          return AlertDialog(
            title: Text("选择书源范围".tl),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: ListView(
                children: [
                  for (final e in groups.entries) ...[
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(e.key,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${e.value.length} 个书源',
                          style: const TextStyle(fontSize: 12)),
                      tristate: true,
                      value: e.value.every(
                              (s) => selected.contains(s.bookSourceName))
                          ? true
                          : (e.value.any(
                                  (s) => selected.contains(s.bookSourceName))
                              ? null
                              : false),
                      onChanged: (v) => setDlg(() {
                        for (final s in e.value) {
                          if (v ?? false) {
                            selected.add(s.bookSourceName);
                          } else {
                            selected.remove(s.bookSourceName);
                          }
                        }
                      }),
                    ),
                    for (final s in e.value)
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: selected.contains(s.bookSourceName),
                          onChanged: (v) => setDlg(() {
                            if (v ?? false) {
                              selected.add(s.bookSourceName);
                            } else {
                              selected.remove(s.bookSourceName);
                            }
                          }),
                          title: Text(s.bookSourceName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          secondary: Icon(
                              s.mediaType == 'comic'
                                  ? Icons.image_outlined
                                  : Icons.menu_book_outlined,
                              size: 18),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setDlg(() {
                  selected
                    ..clear()
                    ..addAll(all.map((s) => s.bookSourceName));
                }),
                child: Text("全选".tl),
              ),
              TextButton(
                onPressed: () => setDlg(selected.clear),
                child: Text("清空".tl),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text("确定".tl),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) {
      setState(() {
        _customSources = selected;
        _scope = 'custom';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "书名 / 作者".tl,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          // 书源范围选择（全部/小说/漫画/自选多选）
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (v, label) in [
                  ('all', '全部书源'),
                  ('novel', '只看小说'),
                  ('comic', '只看漫画'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _scope == v,
                      onSelected: (_) => setState(() => _scope = v),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: const Icon(Icons.checklist_outlined, size: 14),
                    label: Text(
                      _scope == 'custom'
                          ? '已选 ${_customSources.length} 个书源'
                          : '自选书源',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _pickSources,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          // 模式切换 + 排序
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text("聚合".tl)),
                    ButtonSegment(value: true, label: Text("精确".tl)),
                  ],
                  selected: {_exactMode},
                  onSelectionChanged: (s) =>
                      setState(() => _exactMode = s.first),
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact),
                ),
                const Spacer(),
                PopupMenuButton<int>(
                  initialValue: _sortMode,
                  onSelected: (v) => setState(() => _sortMode = v),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 0, child: Text("综合排序".tl)),
                    PopupMenuItem(value: 1, child: Text("字数从多到少".tl)),
                    PopupMenuItem(value: 2, child: Text("字数从少到多".tl)),
                    PopupMenuItem(value: 3, child: Text("按书名".tl)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.sort, size: 18, color: context.colorScheme.primary),
                      Text("排序".tl,
                          style: TextStyle(color: context.colorScheme.primary)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          // 标签 + 书源筛选
          if (_results.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final t in _tags)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        selected: _tagFilter == t,
                        onSelected: (v) =>
                            setState(() => _tagFilter = v ? t : null),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  for (final s in _results.map((b) => b.sourceName).toSet().take(6))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        avatar: const Icon(Icons.dns_outlined, size: 14),
                        label: Text(s,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                        selected: _sourceFilter == s,
                        onSelected: (v) =>
                            setState(() => _sourceFilter = v ? s : null),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          if (_searching) const LinearProgressIndicator(),
          Expanded(
            child: _error == 'no-sources'
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("你未添加书源".tl,
                            style: TextStyle(
                                color: context.colorScheme.outline)),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              context.to(() => const NovelSourcesPage()),
                          icon: const Icon(Icons.add),
                          label: Text("点击去添加".tl),
                        ),
                      ],
                    ),
                  )
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _searching ? "搜索中…".tl : "输入关键字开始搜索".tl,
                          style:
                              TextStyle(color: context.colorScheme.outline),
                        ),
                      )
                    : Builder(builder: (context) {
                        final list = _visible;
                        if (list.isEmpty) {
                          return Center(
                            child: Text("没有符合筛选条件的结果".tl,
                                style: TextStyle(
                                    color: context.colorScheme.outline)),
                          );
                        }
                        return ListView.builder(
                          itemCount:
                              list.length + (_sourceFails.isNotEmpty ? 1 : 0),
                          itemBuilder: (context, i) {
                            // 末尾：失败/无结果书源折叠区
                            if (i == list.length) {
                              return Card(
                                margin: const EdgeInsets.all(8),
                                child: ExpansionTile(
                                  dense: true,
                                  leading: Icon(Icons.folder_off_outlined,
                                      color: context.colorScheme.outline),
                                  title: Text(
                                    '${_sourceFails.length} 个书源无结果或加载失败（已折叠）',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: context.colorScheme.outline),
                                  ),
                                  children: [
                                    for (final e in _sourceFails.entries)
                                      ListTile(
                                        dense: true,
                                        leading: const Icon(
                                            Icons.error_outline,
                                            size: 18),
                                        title: Text(e.key,
                                            style:
                                                const TextStyle(fontSize: 13)),
                                        trailing: Text(e.value,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: context
                                                    .colorScheme.outline)),
                                      ),
                                  ],
                                ),
                              );
                            }
                            final b = list[i];
                            final inShelf = NovelShelf.instance.contains(b.url);
                            return ListTile(
                              leading: _resultCover(b),
                              title: Text(b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                [
                                  b.author,
                                  b.sourceName,
                                  b.wordCount,
                                  b.kind,
                                  b.lastChapter
                                ]
                                    .where((e) => e.isNotEmpty)
                                    .join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                tooltip: inShelf ? '已在书架' : '加入书架',
                                icon: Icon(
                                  inShelf
                                      ? Icons.bookmark_added
                                      : Icons.bookmark_add_outlined,
                                  color: inShelf
                                      ? context.colorScheme.primary
                                      : null,
                                ),
                                onPressed: () async {
                                  if (inShelf) {
                                    await NovelShelf.instance.remove(b.url);
                                  } else {
                                    await NovelShelf.instance.add(b);
                                    if (context.mounted) {
                                      context.showMessage(message: '已加入书架');
                                    }
                                  }
                                  setState(() {});
                                },
                              ),
                              onTap: () =>
                                  context.to(() => NovelBookPage(book: b)),
                            );
                          },
                        );
                      }),
          ),
        ],
      );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text("搜索小说".tl)),
      body: body,
    );
  }
}

/// 书籍详情 + 目录
class NovelBookPage extends StatefulWidget {
  final NovelBook book;
  const NovelBookPage({super.key, required this.book});

  @override
  State<NovelBookPage> createState() => _NovelBookPageState();
}

class _NovelBookPageState extends State<NovelBookPage> {
  late NovelBook _book = widget.book;
  BookSource? _source;
  List<NovelChapter> _toc = [];
  bool _loading = true;
  String? _error;
  bool _inShelf = false;

  @override
  void initState() {
    super.initState();
    _inShelf = NovelShelf.instance.contains(_book.url);
    _load();
  }

  BookSource? _findSource() {
    final mgr = BookSourceManager.instance;
    for (final s in mgr.sources) {
      if (s.bookSourceName == _book.sourceName) return s;
    }
    return null;
  }

  Widget _coverPlaceholder() {
    return Container(
      width: 72,
      height: 96,
      color: context.colorScheme.surfaceContainerHigh,
      child: Icon(Icons.menu_book_outlined,
          color: context.colorScheme.outline, size: 28),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // 本地导入的书（local://）：直接读本地存储
    if (LocalNovelStore.isLocalUrl(_book.url)) {
      try {
        final id = LocalNovelStore.idOf(_book.url);
        final chapters = await LocalNovelStore.instance.readChapters(id);
        _toc = [
          for (var i = 0; i < chapters.length; i++)
            NovelChapter(chapters[i].title, 'local://$id#$i'),
        ];
        setState(() => _loading = false);
      } catch (e) {
        setState(() {
          _loading = false;
          _error = '本地文件读取失败：$e';
        });
      }
      return;
    }
    _source = _findSource();
    if (_source == null) {
      setState(() {
        _loading = false;
        _error = '找不到书源「${_book.sourceName}」，可能已被删除';
      });
      return;
    }
    try {
      try {
        final info = await LegadoEngine.getBookInfo(_source!, _book);
        _book = _book.copyWith(
          name: info.name.isNotEmpty ? info.name : null,
          author: info.author.isNotEmpty ? info.author : null,
          intro: info.intro.isNotEmpty ? info.intro : null,
          cover: info.cover.isNotEmpty ? info.cover : null,
          lastChapter: info.lastChapter.isNotEmpty ? info.lastChapter : null,
          tocUrl: info.tocUrl.isNotEmpty ? info.tocUrl : null,
          wordCount: info.wordCount.isNotEmpty ? info.wordCount : null,
          kind: info.kind.isNotEmpty ? info.kind : null,
        );
      } catch (_) {
        // 详情失败不阻塞目录（保留搜索结果里的书名/作者/简介）
      }
      if (!mounted) return;
      _toc = await LegadoEngine.getToc(_source!, _book);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_toc.isEmpty) {
          _error = '目录加载为空，可能是书源规则失效或站点拒绝访问，请重试或更换书源';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = NovelShelf.instance.progress[_book.url];
    return Scaffold(
      appBar: AppBar(
        title: Text(_book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(_inShelf ? Icons.favorite : Icons.favorite_border),
            tooltip: _inShelf ? "移出书架".tl : "加入书架".tl,
            onPressed: () async {
              if (_inShelf) {
                await NovelShelf.instance.remove(_book.url);
              } else {
                await NovelShelf.instance.add(_book);
              }
              setState(() => _inShelf = !_inShelf);
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 书籍信息头（始终显示，避免空白页）
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _book.cover.isNotEmpty
                      ? Image.network(
                          _book.cover,
                          width: 72,
                          height: 96,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _coverPlaceholder(),
                        )
                      : _coverPlaceholder(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_book.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      if (_book.author.isNotEmpty)
                        Text(_book.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                color: context.colorScheme.outline)),
                      const SizedBox(height: 4),
                      Text(
                        [
                          _book.wordCount,
                          _book.kind,
                          _book.lastChapter,
                        ].where((e) => e.isNotEmpty).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_book.intro.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _book.intro,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 13, color: context.colorScheme.outline),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_error!,
                      style: TextStyle(color: context.colorScheme.error)),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _load,
                    child: Text("重试".tl),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _toc.length,
              itemBuilder: (context, i) {
                final c = _toc[i];
                final isCurrent = progress == i;
                return ListTile(
                  dense: true,
                  enabled: !c.isVolume,
                  title: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          c.isVolume ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? context.colorScheme.primary : null,
                    ),
                  ),
                  onTap: c.isVolume
                      ? null
                      : () => context.to(() => NovelReaderPage(
                            source: _source,
                            book: _book,
                            toc: _toc,
                            chapterIndex: i,
                          )),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _toc.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                final idx = (progress ?? -1) + 1;
                final target =
                    idx < _toc.length && !_toc[idx].isVolume ? idx : 0;
                context.to(() => NovelReaderPage(
                      source: _source,
                      book: _book,
                      toc: _toc,
                      chapterIndex: target,
                    ));
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(progress != null ? "继续阅读".tl : "开始阅读".tl),
            )
          : null,
    );
  }
}

/// 正文阅读器（番茄样式：顶栏 加入书架/听，底栏 目录/日间/设置 + 章节滑条）
class NovelReaderPage extends StatefulWidget {
  final BookSource? source; // 本地书（local://）为 null
  final NovelBook book;
  final List<NovelChapter> toc;
  final int chapterIndex;

  const NovelReaderPage({
    super.key,
    required this.source,
    required this.book,
    required this.toc,
    required this.chapterIndex,
  });

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  late int _index;
  NovelContent? _content;
  bool _loading = true;
  String? _error;
  late double _fontSize;
  late double _lineHeight;
  bool _inShelf = false;

  OmniTts get _tts => OmniTts.instance;

  bool get _isLocal => LocalNovelStore.isLocalUrl(widget.book.url);

  @override
  void initState() {
    super.initState();
    _index = widget.chapterIndex;
    _fontSize =
        (appdata.settings['novelFontSize'] as num?)?.toDouble() ?? 17;
    _lineHeight =
        (appdata.settings['novelLineHeight'] as num?)?.toDouble() ?? 1.7;
    _inShelf = NovelShelf.instance.contains(widget.book.url);
    _tts.addListener(_onTts);
    _tts.onChapterEnd = _onTtsChapterEnd;
    ReadingStats.instance.startSession();
    _load();
  }

  @override
  void dispose() {
    _tts.removeListener(_onTts);
    if (_tts.isActive) {
      _tts.stop();
      _tts.onChapterEnd = null;
    }
    ReadingStats.instance.endSession();
    super.dispose();
  }

  void _onTts() {
    if (mounted) setState(() {});
  }

  /// 本章听完后自动朗读下一章
  void _onTtsChapterEnd() {
    if (!mounted) return;
    final next = _nextReadable(_index + 1, 1);
    if (next < widget.toc.length) {
      setState(() => _index = next);
      _load().then((_) {
        if (mounted &&
            _content?.type == 'text' &&
            _content!.text.trim().isNotEmpty) {
          _tts.start(_content!.text);
        }
      });
    }
  }

  int _nextReadable(int from, int dir) {
    var i = from;
    while (i >= 0 && i < widget.toc.length && widget.toc[i].isVolume) {
      i += dir;
    }
    return i;
  }

  Future<void> _load() async {
    if (_index < 0 || _index >= widget.toc.length) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      NovelContent c;
      if (_isLocal) {
        final chapters = await LocalNovelStore.instance
            .readChapters(LocalNovelStore.idOf(widget.book.url));
        c = NovelContent.text(
            _index < chapters.length ? chapters[_index].text : '');
      } else {
        c = await LegadoEngine.getContent(widget.source!, widget.toc[_index]);
      }
      if (mounted) {
        setState(() {
          _content = c;
          _loading = false;
        });
        NovelShelf.instance.setProgress(widget.book.url, _index);
        if (c.type == 'video') {
          _playVideo(c);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  /// 视频/音乐章节：解析播放地址并跳转播放器
  Future<void> _playVideo(NovelContent c) async {
    var url = c.text.trim();
    if (c.isM3u8Content) {
      try {
        final dir = await Directory.systemTemp.createTemp('omni_m3u8');
        final f = File('${dir.path}/play.m3u8');
        await f.writeAsString(url);
        url = f.path;
      } catch (_) {}
    }
    if (url.isEmpty) {
      context.showMessage(message: "未解析到播放地址".tl);
      return;
    }
    if (!mounted) return;
    context.to(() => VideoPlayerPage(
        title: widget.toc[_index].name, url: url, headers: c.headers));
  }

  void _go(int dir) {
    final next = _nextReadable(_index + dir, dir);
    if (next >= 0 && next < widget.toc.length) {
      if (_tts.isActive) _tts.stop();
      setState(() => _index = next);
      _load();
    }
  }

  Future<void> _toggleShelf() async {
    if (_inShelf) {
      await NovelShelf.instance.remove(widget.book.url);
    } else {
      await NovelShelf.instance.add(widget.book);
    }
    setState(() => _inShelf = !_inShelf);
    if (mounted) {
      context.showMessage(
          message: _inShelf ? "已加入书架".tl : "已移出书架".tl);
    }
  }

  Future<void> _toggleTts() async {
    if (_tts.isActive) {
      await _tts.stop();
      return;
    }
    if (_content?.type != 'text' || _content!.text.trim().isEmpty) {
      context.showMessage(message: "本章没有可朗读的文字".tl);
      return;
    }
    _tts.onChapterEnd = _onTtsChapterEnd;
    await _tts.start(_content!.text);
    if (_tts.error != null && mounted) {
      context.showMessage(message: _tts.error!);
    }
  }

  void _openToc() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text("目录".tl,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.toc.length,
                  itemBuilder: (context, i) {
                    final c = widget.toc[i];
                    return ListTile(
                      dense: true,
                      enabled: !c.isVolume,
                      title: Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: i == _index
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          fontWeight: c.isVolume
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      onTap: c.isVolume
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              if (_tts.isActive) _tts.stop();
                              setState(() => _index = i);
                              _load();
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleDayNight() {
    final cur = appdata.settings['theme_mode']?.toString() ?? 'system';
    final isDark = switch (cur) {
      'dark' => true,
      'light' => false,
      _ => Theme.of(context).brightness == Brightness.dark,
    };
    appdata.settings['theme_mode'] = isDark ? 'light' : 'dark';
    appdata.saveData();
    App.forceRebuild();
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("字号".tl, style: const TextStyle(fontSize: 13)),
                Row(
                  children: [
                    const Text('A', style: TextStyle(fontSize: 14)),
                    Expanded(
                      child: Slider(
                        value: _fontSize,
                        min: 13,
                        max: 28,
                        onChanged: (v) {
                          setState(() => _fontSize = v);
                          appdata.settings['novelFontSize'] = v;
                          appdata.saveData();
                          setSheet(() {});
                        },
                      ),
                    ),
                    const Text('A', style: TextStyle(fontSize: 22)),
                  ],
                ),
                Text("行距".tl, style: const TextStyle(fontSize: 13)),
                Slider(
                  value: _lineHeight,
                  min: 1.3,
                  max: 2.4,
                  onChanged: (v) {
                    setState(() => _lineHeight = v);
                    appdata.settings['novelLineHeight'] = v;
                    appdata.saveData();
                    setSheet(() {});
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _toggleDayNight();
                        },
                        icon: Icon(_isDark
                            ? Icons.wb_sunny_outlined
                            : Icons.dark_mode_outlined),
                        label: Text(_isDark ? "日间模式".tl : "夜间模式".tl),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _openTtsSettings();
                        },
                        icon: const Icon(Icons.record_voice_over_outlined),
                        label: Text("朗读设置".tl),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openTtsSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final engine = _tts.engine;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("朗读引擎".tl,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text("系统语音（手机自带）".tl),
                        selected: engine == 'system',
                        onSelected: (_) {
                          appdata.settings[OmniTts.kEngine] = 'system';
                          appdata.saveData();
                          setSheet(() {});
                        },
                      ),
                      ChoiceChip(
                        label: Text("在线语音（Edge TTS）".tl),
                        selected: engine == 'edge',
                        onSelected: (_) {
                          appdata.settings[OmniTts.kEngine] = 'edge';
                          appdata.saveData();
                          setSheet(() {});
                        },
                      ),
                    ],
                  ),
                  if (engine == 'edge') ...[
                    const SizedBox(height: 12),
                    Text("音色".tl, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final v in kEdgeTtsVoices)
                              ChoiceChip(
                                label: Text(v.name),
                                selected: _tts.voice == v.id,
                                onSelected: (_) {
                                  appdata.settings[OmniTts.kVoice] = v.id;
                                  appdata.saveData();
                                  setSheet(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text("语速 @x×".tlParams(
                      {'x': _tts.rate.toStringAsFixed(1)}),
                      style: const TextStyle(fontSize: 13)),
                  Slider(
                    value: _tts.rate,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    onChanged: (v) {
                      appdata.settings[OmniTts.kRate] = v;
                      appdata.saveData();
                      _tts.applySettings();
                      setSheet(() {});
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTtsBar() {
    final playing = _tts.state == OmniTtsState.playing;
    final loading = _tts.state == OmniTtsState.loading;
    return Material(
      color: context.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => _tts.stop(),
            ),
            Text(
              "@i/@n".tlParams(
                  {'i': _tts.index + 1, 'n': _tts.paragraphs.length}),
              style: TextStyle(fontSize: 12, color: context.colorScheme.outline),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.skip_previous),
              onPressed: () => _tts.prev(),
            ),
            IconButton(
              iconSize: 34,
              icon: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled),
              onPressed: loading ? null : () => _tts.toggle(),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              onPressed: () => _tts.next(),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.tune, size: 20),
              tooltip: "朗读设置".tl,
              onPressed: _openTtsSettings,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.toc[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text(chapter.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16)),
        actions: [
          // 加入书架（番茄样式：顶栏醒目按钮）
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    _inShelf ? context.colorScheme.outline : Colors.red,
                side: BorderSide(
                    color:
                        _inShelf ? context.colorScheme.outline : Colors.red),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
              ),
              onPressed: _toggleShelf,
              icon: Icon(
                  _inShelf ? Icons.bookmark_added : Icons.bookmark_add_outlined,
                  size: 16),
              label: Text(_inShelf ? "已在书架".tl : "加入书架".tl,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          IconButton(
            tooltip: "听书".tl,
            icon: Icon(_tts.isActive
                ? Icons.stop_circle_outlined
                : Icons.headphones_outlined),
            onPressed: _toggleTts,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: TextStyle(color: context.colorScheme.error)),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                          onPressed: _load, child: Text("重试".tl)),
                    ],
                  ),
                )
              : _content!.type == 'images'
                  ? ListView.builder(
                      itemCount: _content!.images.length,
                      itemBuilder: (context, i) => Image.network(
                        _content!.images[i],
                        loadingBuilder: (c, w, p) => p == null
                            ? w
                            : const SizedBox(
                                height: 200,
                                child: Center(
                                    child: CircularProgressIndicator())),
                        errorBuilder: (c, e, s) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: SelectableText(
                        _content!.text,
                        style: TextStyle(
                            fontSize: _fontSize, height: _lineHeight),
                      ),
                    ),
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_tts.isActive) _buildTtsBar(),
            // 章节滑条
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _index > 0 ? () => _go(-1) : null,
                  ),
                  Expanded(
                    child: Slider(
                      value: (_index + 1).toDouble(),
                      min: 1,
                      max: widget.toc.length.toDouble(),
                      divisions:
                          (widget.toc.length - 1).clamp(1, 1 << 16),
                      onChanged: (v) {
                        final target = v.toInt() - 1;
                        if (target != _index &&
                            target >= 0 &&
                            target < widget.toc.length) {
                          if (_tts.isActive) _tts.stop();
                          setState(() => _index = target);
                          _load();
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed:
                        _index < widget.toc.length - 1 ? () => _go(1) : null,
                  ),
                ],
              ),
            ),
            // 底栏：目录 / 日夜间 / 设置（番茄样式）
            Row(
              children: [
                _BottomEntry(
                  icon: Icons.format_list_bulleted,
                  label: "目录".tl,
                  onTap: _openToc,
                ),
                _BottomEntry(
                  icon: _isDark
                      ? Icons.wb_sunny_outlined
                      : Icons.dark_mode_outlined,
                  label: _isDark ? "日间".tl : "夜间".tl,
                  onTap: _toggleDayNight,
                ),
                _BottomEntry(
                  icon: Icons.settings_outlined,
                  label: "设置".tl,
                  onTap: _openSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomEntry extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomEntry(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
