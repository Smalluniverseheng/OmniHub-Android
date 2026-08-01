/// RSS 订阅页面：订阅源主页（列表+管理）/ 文章列表 / 正文阅读
library rss_pages;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/omnihub/rss/rss_engine.dart';
import 'package:venera/omnihub/rss/rss_source.dart';
import 'package:venera/utils/translations.dart';

/// RSS 订阅主页：订阅源列表（管理 + 进入阅读）
class RssHomePage extends StatefulWidget {
  const RssHomePage({super.key});

  @override
  State<RssHomePage> createState() => _RssHomePageState();
}

class _RssHomePageState extends State<RssHomePage> {
  bool _manageMode = false;

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    RssSourceManager.instance.addListener(_onChange);
    RssSourceManager.instance.load().then((_) => _onChange());
  }

  @override
  void dispose() {
    RssSourceManager.instance.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _addByUrl() async {
    final nameCtl = TextEditingController();
    final urlCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("添加订阅".tl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: "名称".tl,
                hintText: '例：少数派',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtl,
              maxLines: 2,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: "订阅地址".tl,
                hintText: 'https://…/feed.xml',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text("Cancel".tl),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text("添加".tl),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtl.text.trim();
    final url = urlCtl.text.trim();
    if (name.isEmpty || url.isEmpty) {
      context.showMessage(message: "名称和地址不能为空".tl);
      return;
    }
    await RssSourceManager.instance.importJson(
        '[{"sourceName":${jsonEncodeStr(name)},"sourceUrl":${jsonEncodeStr(url)}}]');
    if (mounted) context.showMessage(message: "已添加订阅".tl);
  }

  @override
  Widget build(BuildContext context) {
    final mgr = RssSourceManager.instance;
    final list = _manageMode ? mgr.sources : mgr.enabledSources;
    return Scaffold(
      appBar: AppBar(
        title: Text(_manageMode ? "管理订阅源".tl : "RSS 订阅".tl),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: "手动添加订阅".tl,
            onPressed: _addByUrl,
          ),
          IconButton(
            icon: Icon(_manageMode ? Icons.done : Icons.settings_outlined),
            tooltip: _manageMode ? "完成".tl : "管理订阅源".tl,
            onPressed: () => setState(() => _manageMode = !_manageMode),
          ),
        ],
      ),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rss_feed,
                        size: 64, color: context.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      _manageMode
                          ? "还没有订阅源，可在书源管理中导入 rssSource".tl
                          : "还没有启用的订阅源\n可在书源管理中导入 rssSource 订阅源，或点右上角手动添加"
                              .tl,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final s = list[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        context.colorScheme.primaryContainer,
                    child: Text(
                      s.sourceName.isNotEmpty ? s.sourceName[0] : 'R',
                      style: TextStyle(
                          color:
                              context.colorScheme.onPrimaryContainer),
                    ),
                  ),
                  title: Text(s.sourceName),
                  subtitle: Text(
                    s.sourceGroup.isNotEmpty
                        ? '${s.sourceGroup} · ${s.sourceUrl}'
                        : s.sourceUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: _manageMode
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: s.enabled,
                              onChanged: (v) =>
                                  RssSourceManager.instance.toggle(s, v),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  RssSourceManager.instance.remove(s),
                            ),
                          ],
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _manageMode
                      ? null
                      : () => context
                          .to(() => RssArticlesPage(source: s)),
                );
              },
            ),
    );
  }
}

/// 文章列表页：分类 Tab + 文章流 + 加载更多
class RssArticlesPage extends StatefulWidget {
  final RssSource source;
  const RssArticlesPage({super.key, required this.source});

  @override
  State<RssArticlesPage> createState() => _RssArticlesPageState();
}

class _RssArticlesPageState extends State<RssArticlesPage> {
  late final List<(String, String)> _cats;
  int _cat = 0;
  final List<RssArticle> _articles = [];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    try {
      _cats = RssEngine.categories(widget.source);
    } catch (_) {
      _cats = [(widget.source.sourceName, widget.source.sourceUrl)];
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _noMore = false;
      _articles.clear();
    });
    try {
      final list = await RssEngine.fetchArticles(
          widget.source, _cats[_cat].$2,
          page: 1);
      if (mounted) {
        setState(() {
          _articles.addAll(list);
          _loading = false;
          _noMore = list.isEmpty;
        });
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

  Future<void> _loadMore() async {
    if (_loadingMore || _noMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final list = await RssEngine.fetchArticles(
          widget.source, _cats[_cat].$2,
          page: _page + 1);
      if (mounted) {
        setState(() {
          _loadingMore = false;
          if (list.isEmpty) {
            _noMore = true;
          } else {
            _page++;
            _articles.addAll(list);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _switchCat(int i) {
    if (i == _cat) return;
    setState(() => _cat = i);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.sourceName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "刷新".tl,
            onPressed: _load,
          ),
        ],
        bottom: _cats.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (var i = 0; i < _cats.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_cats[i].$1),
                            selected: _cat == i,
                            onSelected: (_) => _switchCat(i),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: context.colorScheme.outline)),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _load,
                          child: Text("重试".tl),
                        ),
                      ],
                    ),
                  ),
                )
              : _articles.isEmpty
                  ? Center(
                      child: Text("这个分类暂时没有文章".tl,
                          style: TextStyle(
                              color: context.colorScheme.outline)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _articles.length + 1,
                        itemBuilder: (context, i) {
                          if (i == _articles.length) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: _noMore
                                    ? Text("没有更多了".tl,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context
                                                .colorScheme.outline))
                                    : TextButton(
                                        onPressed: _loadMore,
                                        child: _loadingMore
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : Text("加载更多".tl),
                                      ),
                              ),
                            );
                          }
                          final a = _articles[i];
                          return ListTile(
                            leading: a.image.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      a.image,
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.article_outlined,
                                              size: 32),
                                    ),
                                  )
                                : const Icon(Icons.article_outlined,
                                    size: 32),
                            title: Text(
                              a.title.isNotEmpty ? a.title : a.link,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (a.author.isNotEmpty) a.author,
                                if (a.date.isNotEmpty) a.date,
                                if (a.description.isNotEmpty) a.description,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () => context.to(() => RssArticlePage(
                                source: widget.source, article: a)),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// 正文阅读页：文本段与图片交错渲染，支持字体设置 / 复制全文
class RssArticlePage extends StatefulWidget {
  final RssSource source;
  final RssArticle article;
  const RssArticlePage(
      {super.key, required this.source, required this.article});

  @override
  State<RssArticlePage> createState() => _RssArticlePageState();
}

class _RssArticlePageState extends State<RssArticlePage> {
  List<RssBlock>? _blocks;
  String? _error;
  late double _fontSize;

  @override
  void initState() {
    super.initState();
    _fontSize =
        (appdata.settings['novelFontSize'] as num?)?.toDouble() ?? 17;
    _load();
  }

  Future<void> _load() async {
    try {
      final html =
          await RssEngine.fetchContent(widget.source, widget.article);
      final base =
          widget.article.link.isNotEmpty
              ? widget.article.link
              : widget.source.sourceUrl;
      if (mounted) {
        setState(() => _blocks = RssEngine.htmlToBlocks(html, base));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String get _fullText =>
      (_blocks ?? []).where((b) => !b.isImage).map((b) => b.text).join('\n\n');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.sourceName),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: "复制全文".tl,
            onPressed: _blocks == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _fullText));
                    context.showMessage(message: "已复制全文".tl);
                  },
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: context.colorScheme.outline)),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _blocks = null;
                        });
                        _load();
                      },
                      child: Text("重试".tl),
                    ),
                  ],
                ),
              ),
            )
          : _blocks == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
                  children: [
                    Text(
                      widget.article.title,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.bold),
                    ),
                    if (widget.article.author.isNotEmpty ||
                        widget.article.date.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          [
                            if (widget.article.author.isNotEmpty)
                              widget.article.author,
                            if (widget.article.date.isNotEmpty)
                              widget.article.date,
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 12,
                              color: context.colorScheme.outline),
                        ),
                      ),
                    const Divider(height: 24),
                    for (final b in _blocks!)
                      if (b.isImage)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              b.text,
                              fit: BoxFit.contain,
                              loadingBuilder: (c, w, p) => p == null
                                  ? w
                                  : const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Center(
                                          child:
                                              CircularProgressIndicator()),
                                    ),
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Text(
                            b.text,
                            style: TextStyle(
                                fontSize: _fontSize, height: 1.7),
                          ),
                        ),
                  ],
                ),
    );
  }
}

/// JSON 字符串转义（手动添加订阅时构造 JSON 用）
String jsonEncodeStr(String s) =>
    '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
