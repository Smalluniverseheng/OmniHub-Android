/// 小说模块页面：书源管理 / 搜索 / 详情目录 / 正文阅读
library novel_pages;

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
      const supported = ['bookSource', 'textTocRule', 'replaceRule', 'httpTTS'];
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
    try {
      final res = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 25),
        headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android) legado/3.0'},
      )).get<String>(target);
      final text = res.data ?? '';
      if (text.isEmpty) throw 'empty';
      if (context.mounted) {
        // 书源类型走页面实例的提示逻辑
        final (n, label) = await LegadoImport.importByType(type, text);
        if (context.mounted) {
          context.showMessage(
              message: n > 0
                  ? "导入 @c 个@l".tlParams({'c': n, 'l': label})
                  : "没有可导入的内容".tl);
        }
      }
    } catch (e) {
      if (context.mounted) {
        context.showMessage(message: "下载失败：@e".tlParams({'e': e.toString()}));
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

  Future<void> _importText(String text, {String type = 'bookSource'}) async {
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
    await NovelSourcesPage.importLegadoUrl(url, context);
  }

  /// 二维码导入
  Future<void> _scanQr() async {
    final code = await context.to<String>(() => const _QrScanPage());
    if (code == null || code.isEmpty || !mounted) return;
    if (code.startsWith('http') || code.startsWith('legado://')) {
      await NovelSourcesPage.importLegadoUrl(code, context);
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
                    NovelSourcesPage.importLegadoUrl(t, this.context);
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
                child: Text(
                  "还没有书源。\n点右上角导入「开源阅读(Legado)」格式的书源 JSON。".tl,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colorScheme.outline),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("扫码导入".tl)),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_handled) return;
              final raw = capture.barcodes.firstOrNull?.rawValue;
              if (raw != null && raw.isNotEmpty) {
                _handled = true;
                context.pop(raw);
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Text(
              "对准 Legado 书源分享二维码".tl,
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
  const NovelSearchPage({super.key});

  @override
  State<NovelSearchPage> createState() => _NovelSearchPageState();
}

class _NovelSearchPageState extends State<NovelSearchPage> {
  final _controller = TextEditingController();
  bool _searching = false;
  List<NovelBook> _results = [];
  String? _error;

  Future<void> _search() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    final sources = BookSourceManager.instance.enabledSources;
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
    });
    // 并发搜索全部启用书源，逐个追加结果
    await Future.wait(sources.map((s) async {
      try {
        final res = await LegadoEngine.search(s, key);
        if (mounted && res.isNotEmpty) {
          setState(() => _results = [..._results, ...res]);
        }
      } catch (_) {}
    }));
    if (mounted) setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("搜索小说".tl)),
      body: Column(
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
          if (_searching) const LinearProgressIndicator(),
          Expanded(
            child: _error == 'no-sources'
                ? Center(
                    child: TextButton(
                      onPressed: () =>
                          context.to(() => const NovelSourcesPage()),
                      child: Text("没有启用的书源，点这里去导入".tl),
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
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final b = _results[i];
                          return ListTile(
                            leading: Icon(b.mediaType == 'comic'
                                ? Icons.image_outlined
                                : Icons.menu_book_outlined),
                            title: Text(b.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [b.author, b.sourceName, b.lastChapter]
                                  .where((e) => e.isNotEmpty)
                                  .join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () =>
                                context.to(() => NovelBookPage(book: b)),
                          );
                        },
                      ),
          ),
        ],
      ),
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
        _book = NovelBook(
          name: info.name,
          author: info.author.isNotEmpty ? info.author : _book.author,
          intro: info.intro.isNotEmpty ? info.intro : _book.intro,
          cover: info.cover.isNotEmpty ? info.cover : _book.cover,
          lastChapter: info.lastChapter,
          url: info.url,
          tocUrl: info.tocUrl,
          sourceName: info.sourceName,
          mediaType: info.mediaType,
        );
      } catch (_) {
        // 详情失败不阻塞目录
      }
      _toc = await LegadoEngine.getToc(_source!, _book);
      setState(() => _loading = false);
    } catch (e) {
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
