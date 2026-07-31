/// 小说模块页面：书源管理 / 搜索 / 详情目录 / 正文阅读
library novel_pages;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/omnihub/novel/book_source.dart';
import 'package:venera/omnihub/novel/legado_engine.dart';
import 'package:venera/omnihub/stats/reading_stats.dart';
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

  Future<void> _importText(String text) async {
    try {
      final n = await BookSourceManager.instance.importJson(text);
      if (mounted) {
        context.showMessage(
            message: n > 0 ? "导入 @c 个书源".tlParams({'c': n}) : "没有可导入的书源".tl);
      }
    } catch (e) {
      if (mounted) context.showMessage(message: "导入失败：JSON 格式不正确".tl);
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
              leading: const Icon(Icons.content_paste),
              title: Text("从剪贴板导入".tl),
              onTap: () async {
                Navigator.of(context).pop();
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) _importText(data!.text!);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: Text("从文件导入".tl),
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
              leading: const Icon(Icons.edit_outlined),
              title: Text("粘贴 JSON".tl),
              onTap: () {
                Navigator.of(context).pop();
                final controller = TextEditingController();
                showDialog(
                  context: this.context,
                  builder: (context) => AlertDialog(
                    title: Text("粘贴书源 JSON".tl),
                    content: TextField(
                      controller: controller,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '{...} 或 [{...}, {...}]',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text("Cancel".tl),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _importText(controller.text);
                        },
                        child: Text("导入".tl),
                      ),
                    ],
                  ),
                );
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
                            source: _source!,
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
                      source: _source!,
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

/// 正文阅读器
class NovelReaderPage extends StatefulWidget {
  final BookSource source;
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
  double _fontSize = 17;

  @override
  void initState() {
    super.initState();
    _index = widget.chapterIndex;
    ReadingStats.instance.startSession();
    _load();
  }

  @override
  void dispose() {
    ReadingStats.instance.endSession();
    super.dispose();
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
      final c = await LegadoEngine.getContent(
          widget.source, widget.toc[_index]);
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
      setState(() => _index = next);
      _load();
    }
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
          IconButton(
            icon: const Icon(Icons.format_size),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) => StatefulBuilder(
                  builder: (context, setSheet) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Text('A', style: TextStyle(fontSize: 14)),
                        Expanded(
                          child: Slider(
                            value: _fontSize,
                            min: 13,
                            max: 26,
                            onChanged: (v) {
                              setState(() => _fontSize = v);
                              setSheet(() {});
                            },
                          ),
                        ),
                        const Text('A', style: TextStyle(fontSize: 22)),
                      ],
                    ),
                  ),
                ),
              );
            },
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
                        style: TextStyle(fontSize: _fontSize, height: 1.7),
                      ),
                    ),
      bottomNavigationBar: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: _index > 0 ? () => _go(-1) : null,
                icon: const Icon(Icons.chevron_left),
                label: Text("上一章".tl),
              ),
            ),
            Text("${_index + 1}/${widget.toc.length}",
                style: TextStyle(
                    fontSize: 12, color: context.colorScheme.outline)),
            Expanded(
              child: TextButton.icon(
                onPressed:
                    _index < widget.toc.length - 1 ? () => _go(1) : null,
                icon: const Icon(Icons.chevron_right),
                label: Text("下一章".tl),
                iconAlignment: IconAlignment.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
